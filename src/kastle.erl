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
-module(kastle).
-author("kirill.zhiganov").

%% API
-export([ %%start/0
         start/2
        , stop/0
]).

%%%===================================================================
%%% API
%%%===================================================================

%% @doc Starts kastle service.
%%-spec start() -> ok.
%%start() -> application:start(?MODULE, permanent).

start(normal, _) -> application:start(?MODULE, permanent).

%% @doc Stops kastle service.
-spec stop() -> ok.
stop() -> application:stop(?MODULE).