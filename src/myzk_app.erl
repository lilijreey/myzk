%%%-------------------------------------------------------------------
%% @doc myzk public API
%% @end
%%%-------------------------------------------------------------------

-module(myzk_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_StartType, _StartArgs) ->
    myzk_sup:start_link().


%%--------------------------------------------------------------------
stop(_State) ->


    ok.

%%====================================================================
%% Internal functions
%%====================================================================
