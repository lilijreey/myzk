#!/usr/bin/env ruby
#
require 'json'
require 'logger'
#require './map.rb'

## 对方意图评估
## 攻击优化
## 防守优化
## 我方移动
#
# 局面评估
## 策略策略
#   1. 进攻老巢
#   2. 防守老巢
#   3. 占领安全区
#   4. 偷袭老巢
#
#  战力评估
#

=begin
 一些先验经验
 1. AI 情愿被打也要进辐射区

=end


$log = Logger.new("/tmp/ai.log")
$req = nil
$is_base_pos_break = false
$round = -1 #回合数
$sync_seq =0
$my_player = nil
$peer_player = nil

$my_robots={}
$peer_robots={}
$map = {}
$my_robots_move_order = []

T_AI = :AiBrain
T_GJ = :OverLordSoldier
T_TS = :SlungshotSoldier
T_FY = :ArmourSoldier

## events
EV_ATTACK = :attack

M_OCCUPY_SAFE_AREA = :occupy_safe_area
M_OCCUPY_PEER_HOME = :occupy_peer_home
M_DEFENCE_HOME = :defence_home

MAP_MAX_X = 39
MAP_MAX_Y = 29

MAP_WIDTH = 40
MAP_HIGHT = 30

def map_is_valid_pos?(pos)
  (0..MAP_MAX_X).include? pos.x and
  (0..MAP_MAX_Y).include? pos.y
end

def map_is_empty_pos?(pos)
  map_is_valid_pos?(pos) and
  $map[pos] == nil 
end


def assert(isTrue)
  raise "assert failed #{isTrue}" unless isTrue
end

GameOver = Class.new(Exception)


$robot_config =
{
    T_AI => {hp: 3000, attack:0, defence:15, attack_rang:nil, move_len:5, price:0},
    T_GJ => {hp: 300, attack:10, defence:5, attack_rang:nil, move_len:9, price:800},
    T_FY => {hp: 450, attack:5, defence:10, attack_rang:nil, move_len:5, price:600},
    T_TS => {hp: 280, attack:5, defence:5, attack_rang:nil, move_len:6, price:800},
}


Point = Struct.new(:x, :y) do
  def distance(o)
    (self.x - o.x).abs + (self.y-o.y).abs
  end

end

Event = Struct.new(:ev, :arg1, :arg2)

def get_move_intention(playerId, pos)
  ## 得到移动意图
  if playerId == 1
    {M_DEFENCE_HOME => Point.new(1,28).distance(pos),
     M_OCCUPY_SAFE_AREA => Point.new(19,1).distance(pos),
     M_OCCUPY_PEER_HOME => Point.new(38,28).distance(pos)
    }.min { |(_lk, lv), (_rk, rv)| lv <=> rv}[0]
  else ## 2
    {M_DEFENCE_HOME => Point.new(32,28).distance(pos),
     M_OCCUPY_SAFE_AREA => Point.new(20,1).distance(pos),
     M_OCCUPY_PEER_HOME => Point.new(1,28).distance(pos)
    }.min { |(_lk, lv), (_rk, rv)| lv <=> rv}[0]
  end
end

class Agent
  attr_accessor :id, :type, :pos, :hp, :event_box, :sync_seq, :move_intention
  def initialize(id, type, pos, hp=nil, attack=nil, defence=nil)
    @id = id
    @type = (type.is_a? String) ? type.to_sym : type
    @pos = pos

    @hp      ||= $robot_config[@type][:hp]
    @attach  ||= $robot_config[@type][:attack]
    @defence ||= $robot_config[@type][:defence]
    @event_box = []
    @sync_seq = $sync_seq
    @move_intention = nil
  end

  def to_output
    { roleid: @id,
      columnid: @pos.x,
      rowid: @pos.y,
      robottype: @type.to_s,
      hp: @hp,
    }
  end

  def get_moveable_count
    [[-1, 0], [1,0], [0,-1], [0, 1]].map do |(x,y)|
      Point.new(@pos.x+x, @pos.y+y)
    end.count(&method(:map_is_empty_pos?))
  end

  def update_move_intention(playerId)
    @move_intention = get_move_intention(playerId, @pos)
    #$log.debug("p[#{playerId}], robot:#{@id} update int #{@move_intention}")

  end

end

SAFE_AREA =[Point.new(19,0), Point.new(20.0), Point.new(19,1),Point.new(20,1)].freeze
MOTHER_POS = [nil, Point.new(1,28), Point.new(38,28)].freeze



def output_rsp(rspName, ans)
  rsp =
  {
      'interface' => {
          'ans' => ans,
          'interfaceName' => rspName
      },
      'player' => $req['player'],
      'round'  => $req['round'],
      'seq'  => $req['seq'],
      'timestamp'  => $req['timestamp'],
      'version'  => $req['version'],
  }.to_json
  puts rsp
  STDOUT.flush

  $log.debug("output: #{rsp}")
end

def peer_player(myId)
  if myId == 1
    return 2
  else
    return 1
  end
end

def robot_init_req(req)
  $my_player = req['player']
  $peer_player = peer_player($my_player)

  #TODO
  $my_robots[0] =  Agent.new(0, T_AI, Point.new(1,28))
  $my_robots[1] =  Agent.new(1, T_GJ, Point.new(2,28))
  ans = {robotlist: $my_robots.values.map(&:to_output)}

  output_rsp('queryRobotInitInfoRsp', ans)
end


def fight_order_req(req)
  $sync_seq += 1
  $map.clear
  is_new_round = $round != req['round']
  $round = req['round'] if is_new_round

  para = req['interface']['para']


  # update my robot hp
  $log.debug("old my robot is #{$my_robots}")
  para['localrobotlist'].each do |e|
    $log.debug("parse my robot #{e['roleid']}")
    robot = $my_robots[e['roleid']]
    assert(robot)

    $map[robot.pos] = robot

    assert(robot.type.to_s == e['robottype'])
    assert(robot.pos.x == e['columnid'])
    assert(robot.pos.y == e['rowid'])

    if robot.hp != e['hp']
      robot.event_box << Event.new(EV_ATTACK, robot.hp - e['hp'])
      robot.hp = e['hp']
    end
    robot.sync_seq = $sync_seq
  end

  # delete dead robots
  $my_robots.delete_if do |k,v|
    #$log.debug("delte if key #{k} #{v}")
    v.sync_seq != $sync_seq
  end

  $log.debug("new my robot is #{$my_robots}")

  # update peer robot
  para['peerrobotlist'].each do |e|
    robot = $peer_robots[e['roleid']]
    if robot # update
      robot.pos.x = e['columnid']
      robot.pos.y = e['rowid']
      robot.hp = e['hp']
      robot.sync_seq = $sync_seq
      robot.update_move_intention($peer_player)
      #$log.debug("update peer robot:#{robot.id} move #{robot.move_intention}")
    else
      robot =
      $peer_robots[e['roleid']] = Agent.new(e['roleid'],
                                            e['robottype'],
                                            Point.new(e['columnid'], e['rowid']),
                                            e['hp'])
      #$log.debug("new peer robot #{e['roleid']}")
    end

    $map[robot.pos] = robot

  end

  $peer_robots.delete_if { |_k,v| v.sync_seq != $sync_seq }
  $log.debug("peer robots:#{$peer_robots}")

  fight_action(is_new_round)
end


def fight_action(is_new_round)
  if is_new_round

    ## 根据可移动方向确认移动顺序
    $my_robots_move_order = 
      $my_robots.values.map(&:get_moveable_count).zip($my_robots.keys).sort do |(lc, _), (rc, _)|
        rc <=> lc
      end

    #$log.debug("action order #{$my_robots_move_order}")


    ## 局面评估
    # 敌方兵力总算,战斗力总数，声明值总数,各兵种数量
    # 移动趋势
    #   敌方每个兵，对自己基地，对方基地和安全区的距离求中取最近的一个，作为该兵的移动趋势
    #
    peer_move_intertion = {}
  end
  # TODO get ans

  robot_id = $my_robots_move_order.pop
  $my_robots[robot_id].ai()

  ans = {'attack' => '',
         'roleid' => -1,
  }


  output_rsp('queryFightOrderRsp', ans)
end

def game_over_req(req)
  raise GameOver, 'game over'
end

def init_env

end


def main
  begin
    init_env
    #game_loop
    while (line = STDIN.readline )
      $log.debug "get input #{line}"
      $req = JSON.parse(line)
      dispatch_req($req)
    end
  rescue GameOver
    $log.debug('game over normal')
  rescue StandardError => e
    $log.error('has a exception game exit '+ e.message)
    $log.error(e.backtrace.inspect)
  end
end

def dispatch_req(req)
  case req['interface']['interfaceName']
  when 'queryRobotInitInfoReq' then robot_init_req(req)
  when 'queryFightOrderReq' then fight_order_req(req)
  when 'gameOverOrderReq' then game_over_req(req)
  else raise 'unknow req ' + req
  end
end



def test_dispatch_req
  req = '{"interface":{"interfaceName":"queryRobotInitInfoReq"},"player":1,"round":0,"seq":0,"timestamp":1538747759,"version":"1.0"}'
  $req = JSON.parse(req)
  dispatch_req($req)
end


## 目标
# 占领
# 进攻
# 防守
# 移动到

# 寻找AI 进行攻击
# 跟随某个
class AttackIA
end

class MoveToAI
  ## 移动到point或者一个区域

end

#def map_empty_pos(pos)
#  # TODO
#  #
#end



def move_to_point(currPos, endPos)
  open = Set.new [currPos]
  close =Set.new
  path = []
  max_deep = 7

  while not open.empty?
  end

  return path
end


def find_path(srcPos, dstPos, maxDeep)
  #simple_path(srcPos, dstPos, maxDeep)
  #or
  astar_path(srcPos, dstPos, maxDeep)
end

#def simple_path(srcPos, dstPos, maxDeep)
#  return [] if srcPos == dstPos

#  path = []
#  curr = srcPos.dup
#  maxDeep.times do
#    if (curr.x - dstPos.x).abs >= (curr.y - dstPos.y).abs


#    if curr.x > dstPos.x
#      if curr.y > dstPos.y

#      else
#      end
#    else
#    end


#  end

#  return path
#end

## 最大深度 
## ->[Points]
def astar_path(srcPos, dstPos, maxDeep)
  return [] if srcPos == dstPos
  # k,v {pos, G, H, pervPos, move}
  #      0    1  2   3        4
  open = {srcPos => [srcPos, 0, srcPos.distance(dstPos), :start, nil]}
  close ={}

  deep = 1

  lastPos = 
  while not open.empty?
    minpos = open.values.min do |l, r| 
      # f = g + h
      (l[1] + l[2]) <=> (r[1] + r[2])
    end

    break minpos if minpos == dstPos
    break minpos if deep > maxDeep
    deep += 1

    value = open.delete(minpos)
    close[minpos] = value

    #add neiber nodes
    [[-1, 0, 'L'], [1,0,'R'], [0,-1,'U'], [0, 1,'D']].each do |n|
      npos = Point.new(minpos + n[0], minpos + n[1])
      next unless map_is_empty_pos?(npos)
      next if close.include? npos

      n_curr_g = value[2] + 1
      if open.include? npos
        ## try update f,g
        if open[npos][1] > n_curr_g
          open[npos][1] = n_curr_g
          open[npos][4] = n[2]
        end
      else
        open[npos] = [npos, n_curr_g, npos.distance(dstPos), minpos, n[2]]
      end
    end
  end

  path = []
  while lastPos
    break if lastPos == strPos
    v = open[lastPos] || close[lastPos]
    lastPos = v[3]
    path.unshift(v[4])
  end

  return path
end
