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

%%_* Exports ===================================================================

%% cowboy handler callbacks
-export([init/3]).

%% cowboy rest callbacks
-export([ rest_init/2
        , allowed_methods/2
        , content_types_accepted/2
        , handle_post/2
        ]).

%%_* Includes ==================================================================
-include("kastle.hrl").

%%_* Records ===================================================================
-record(state, {}).

%%_* Macros ====================================================================
-define(TOPIC_REQ,     topic).
-define(PARTITION_REQ, partition).

%%_* cowboy handler callbacks ==================================================

-spec init({atom(), atom()}, cowboy_req:req(), _) ->
              {upgrade, protocol, cowboy_rest}.
init({tcp, http}, _, _) ->
  {upgrade, protocol, cowboy_rest}.

%%_* cowboy rest callbacks =====================================================

-spec rest_init(cowboy_req:req(), _) -> {ok, cowboy_req:req(), #state{}}.
rest_init(Req, _) ->
  {ok, Req, #state{}}.

-spec allowed_methods(cowboy_req:req(), #state{}) ->
                         {[binary()], cowboy_req:req(), #state{}}.
allowed_methods(Req, State) ->
  {[<<"POST">>], Req, State}.

-spec content_types_accepted(cowboy_req:req(), #state{}) ->
                                {[_], cowboy_req:req(), #state{}}.
content_types_accepted(Req, State) ->
  {[{{<<"application">>, <<"json">>, []}, handle_post}], Req, State}.

-spec handle_post(cowboy_req:req(), #state{}) ->
                     {halt, cowboy_req:req(), #state{}}.
handle_post(Req0, State) ->
  {Topic, Req1} = cowboy_req:binding(?TOPIC_REQ, Req0),
  {Partition, Req2} = cowboy_req:binding(?PARTITION_REQ, Req1),
  {ok, Body, Req3} = cowboy_req:body(Req2),
  {ok, Req} =
    case do_handle_post(Topic,
                        validate_partition(Partition),
                        validate_body(Body)) of
      ok ->
        log_info(Req3, 204),
        cowboy_req:reply(204, Req3);
      {error, Error} ->
        log_error(Req3, 400, Error),
        cowboy_req:reply(400, [], jiffy:encode(#{error => Error}), Req3);
      {error, Code, Error} ->
        log_error(Req3, Code, Error),
        cowboy_req:reply(Code, [], jiffy:encode(#{error => Error}), Req3)
    end,
  {halt, Req, State}.

%%_* Internal functions ========================================================
log_error(Req, ResponseCode, Error) ->
  do_log(error, Req, ResponseCode, ", error: ~p", [Error]).

log_info(Req, ResponseCode) ->
  do_log(info, Req, ResponseCode).

do_log(Level, Req, ResponseCode) ->
  do_log(Level, Req, ResponseCode, "", []).

do_log(Level, Req, ResponseCode, ExtraFmt, ExtraArgs) ->
  {Method, _} = cowboy_req:method(Req),
  {Path, _} = cowboy_req:path(Req),
  {Version, _} = cowboy_req:version(Req),
  {UserAgent, _} = cowboy_req:header(<<"user-agent">>, Req),
  {Host, _} = cowboy_req:header(<<"host">>, Req),
  {ContentType, _} = cowboy_req:header(<<"content-type">>, Req),
  {ContentLength, _} = cowboy_req:header(<<"content-length">>, Req),
  Format = "~s ~s ~s ~B, user-agent: ~s, host: ~s, content-type: ~s, content-length: ~s" ++ ExtraFmt,
  Args = [Method, Path, Version, ResponseCode, UserAgent, Host, ContentType, ContentLength] ++ ExtraArgs,
  lager:log(Level, self(), Format, Args).

validate_partition(Partition) ->
  string:to_integer(binary_to_list(Partition)).

validate_body(Body) ->
  do_validate_body(catch jiffy:decode(Body, [return_maps])).

do_validate_body({error, _Whatever}) ->
  {error, <<"invalid json">>};
do_validate_body(Data) ->
  case jesse:validate(?KASTLE_JSON_SCHEMA, Data) of
    {ok, _} = Res ->
      Res;
    {error, JesseErrors} ->
      parse_jesse_errors(JesseErrors)
  end.

parse_jesse_errors([{data_invalid, _Schema, ErrorType, _Value, _Path}]) ->
  ErrorMsg = iolist_to_binary(io_lib:format("json schema validation failed: ~p", [ErrorType])),
  {error, ErrorMsg};
parse_jesse_errors([{schema_invalid, Schema, ErrorType}]) ->
  lager:error("Invalid schema: ~p, ~p", [Schema, ErrorType]),
  {error, 500, <<"error validating json, please contact service maintainers">>};
parse_jesse_errors(Other) ->
  lager:error("Unexpected jesse error(s): ~p", [Other]),
  {error, 500, <<"error validating json, please contact service maintainers">>}.

do_handle_post(_Topic, _Partition, {error, _Any} = Error) ->
  Error;
do_handle_post(_Topic, _Partition, {error, _Code, _Any} = Error) ->
  Error;
do_handle_post(_Topic, {error, no_integer}, _Data) ->
  {error, <<"invalid partition">>};
do_handle_post(Topic, {Partition, []}, {ok, Data}) when is_integer(Partition) ->
  Key = maps:get(?MESSAGE_KEY, Data),
  Value = maps:get(?MESSAGE_VALUE, Data),
  produce(Topic, Partition, [{Key, Value}]).

produce(Topic, Partition, [{Key, Value}]) ->
  case get_producer(Topic, Partition) of
    {error, topic_not_found} ->
      {error, 404, <<"topic not found">>};
    {error, {producer_not_found, _Topic}} ->
      {error, 404, <<"topic not found">>};
    {error, {producer_not_found, _Topic, _Partition}} ->
      {error, 404, <<"partition not found">>};
    {error, _} -> % client_down or producer_down
      {error, 503, <<"infrastructure down">>};
    {ok, Producer} ->
      brod:produce_sync(Producer, Key, Value)
  end.

get_producer(Topic, Partition) ->
  case brod:get_producer(?BROD_CLIENT, Topic, Partition) of
    {error, _Any} ->
      try_start_producer(Topic, Partition);
    {ok, Producer} ->
      {ok, Producer}
  end.

try_start_producer(Topic, Partition) ->
  case brod:start_producer(?BROD_CLIENT, Topic, kastle:get_producer_config()) of
    {error, topic_not_found} = Error ->
      Error;
    {error, {already_started, _}} -> % may be by another request?
      brod:get_producer(?BROD_CLIENT, Topic, Partition);
    ok ->
      brod:get_producer(?BROD_CLIENT, Topic, Partition)
  end.

%%%_* Emacs ====================================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
