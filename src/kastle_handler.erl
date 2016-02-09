%%%
%%%   Copyright (c) 2016, Klarna AB
%%%
%%%   Licensed under the Apache License, Version 2.0 (the "License");
%%%   you may not use this file except in compliance with the License.
%%%   You may obtain a copy of the License at
%%%
%%%       http://www.apache.org/licenses/LICENSE-2.0
%%%
%%%   Unless required by applicable law or agreed to in writing, software
%%%   distributed under the License is distributed on an "AS IS" BASIS,
%%%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%%   See the License for the specific language governing permissions and
%%%   limitations under the License.
%%%

%%%=============================================================================
%%% @doc
%%% @copyright 2016 Klarna AB
%%% @end
%%%=============================================================================

-module(kastle_handler).
-author("kirill.zhiganov").

%% API
-export([]).

%%_* Exports ===================================================================

%% cowboy handler callbacks
-export([init/3]).

%% cowboy rest callbacks
-export([ rest_init/2
        , rest_terminate/2
        , allowed_methods/2
        %% POST
]).

%%_* Records ===================================================================
-record(state, { topic     :: {binary(), binary()}
               , partition :: {binary(), binary()}
}).

%%_* Macros ====================================================================
-define(TOPIC_REQ,     <<"topic">>).
-define(PARTITION_REQ, <<"partition">>).
-define(DEFAULT_VALUE, <<"undefined">>).

%% =============================================================================
%% cowboy handler callbacks
%% =============================================================================

-spec init({atom(), atom()}, cowboy_req:req(), _) ->
  {upgrade, protocol, cowboy_rest}.
init({tcp, http}, _, _) -> {upgrade, protocol, cowboy_rest}.

%% =============================================================================
%% cowboy rest callbacks
%% =============================================================================

-spec rest_init(cowboy_req:req(), _) ->
  {ok, cowboy_req:req(), #state{}}.
rest_init(Req0, _) ->
  {Topic, Req1}    = cowboy_req:binding(?TOPIC_REQ,     Req0, ?DEFAULT_VALUE),
  {Partition, Req} = cowboy_req:binding(?PARTITION_REQ, Req1, ?DEFAULT_VALUE),
  {ok, Req, #state{topic = Topic, partition = Partition}}.

-spec rest_terminate(cowboy_req:req(), #state{}) -> ok.
rest_terminate(_Req, _State) ->
%% We might need to add some logging here
  ok.

-spec allowed_methods(cowboy_req:req(), #state{}) ->
  {[binary()], cowboy_req:req(), #state{}}.
allowed_methods(Req, State) ->
  {[<<"POST">>], Req, State}.
