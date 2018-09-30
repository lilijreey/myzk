%%%-------------------------------------------------------------------
%% @doc myzk top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(myzk_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: #{id => Id, start => {M, F, A}}
%% Optional keys are restart, shutdown, type, modules.
%% Before OTP 18 tuples must be used to specify a child. e.g.
%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
-define(zk_server, zk_server).
init([]) ->
    SupFlags = #{strategy => one_for_all, intensity => 1, period => 5},
    ChildSpecs = [#{id => ?zk_server,
                    start => {?zk_server, start_link, []},
                    restart => transient,
                    shutdown => 5,
                    type => worker,
                    modules => [?zk_server]}],
    {ok, {SupFlags, ChildSpecs}}.


%%====================================================================
%% Internal functions
%%====================================================================

