%%%-------------------------------------------------------------------
%%% @author Evgeniy Khramtsov <ekhramtsov@process-one.net>
%%% @copyright (C) 2013, Evgeniy Khramtsov
%%% @doc
%%%
%%% @end
%%% Created : 12 May 2013 by Evgeniy Khramtsov <ekhramtsov@process-one.net>
%%%
%%% ejabberd, Copyright (C) 2013   ProcessOne
%%%
%%% This program is free software; you can redistribute it and/or
%%% modify it under the terms of the GNU General Public License as
%%% published by the Free Software Foundation; either version 2 of the
%%% License, or (at your option) any later version.
%%%
%%% This program is distributed in the hope that it will be useful,
%%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
%%% General Public License for more details.
%%%
%%% You should have received a copy of the GNU General Public License
%%% along with this program; if not, write to the Free Software
%%% Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
%%% 02111-1307 USA

%%%-------------------------------------------------------------------
-module(ejabberd_logger).

%% API
-export([start/0, reopen_log/0, get/0, set/1, get_log_path/0]).

-include("ejabberd.hrl").

-type loglevel() :: 0 | 1 | 2 | 3 | 4 | 5.

-spec start() -> ok.
-spec get_log_path() -> string().
-spec reopen_log() -> ok.
-spec get() -> {loglevel(), atom(), string()}.
-spec set(loglevel() | {loglevel(), list()}) -> {module, module()}.

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Returns the full path to the ejabberd log file.
%% It first checks for application configuration parameter 'log_path'.
%% If not defined it checks the environment variable EJABBERD_LOG_PATH.
%% And if that one is neither defined, returns the default value:
%% "ejabberd.log" in current directory.
get_log_path() ->
    case application:get_env(ejabberd, log_path) of
	{ok, Path} ->
	    Path;
	undefined ->
	    case os:getenv("EJABBERD_LOG_PATH") of
		false ->
		    ?LOG_PATH;
		Path ->
		    Path
	    end
    end.

-ifdef(LAGER).

start() ->
    application:load(lager),
    ConsoleLog = get_log_path(),
    Dir = filename:dirname(ConsoleLog),
    ErrorLog = filename:join([Dir, "error.log"]),
    CrashLog = filename:join([Dir, "crash.log"]),
    application:set_env(
      lager, handlers,
      [{lager_console_backend, info},
       {lager_file_backend, [{file, ConsoleLog}, {level, info}, {count, 1}]},
       {lager_file_backend, [{file, ErrorLog}, {level, error}, {count, 1}]}]),
    application:set_env(lager, crash_log, CrashLog),
    ejabberd:start_app(lager),
    ok.

reopen_log() ->
    lists:foreach(
      fun({lager_file_backend, File}) ->
              whereis(lager_event) ! {rotate, File};
         (_) ->
              ok
      end, gen_event:which_handlers(lager_event)),
    reopen_sasl_log().

get() ->
    case lager:get_loglevel(lager_console_backend) of
        none -> {0, no_log, "No log"};
        emergency -> {1, critical, "Critical"};
        alert -> {1, critical, "Critical"};
        critical -> {1, critical, "Critical"};
        error -> {2, error, "Error"};
        warning -> {3, warning, "Warning"};
        notice -> {3, warning, "Warning"};
        info -> {4, info, "Info"};
        debug -> {5, debug, "Debug"}
    end.

set(LogLevel) when is_integer(LogLevel) ->
    LagerLogLevel = case LogLevel of
                        0 -> none;
                        1 -> critical;
                        2 -> error;
                        3 -> warning;
                        4 -> info;
                        5 -> debug
                    end,
    case lager:get_loglevel(lager_console_backend) of
        LagerLogLevel ->
            ok;
        _ ->
            ConsoleLog = get_log_path(),
            lists:foreach(
              fun({lager_file_backend, File} = H) when File == ConsoleLog ->
                      lager:set_loglevel(H, LagerLogLevel);
                 (lager_console_backend = H) ->
                      lager:set_loglevel(H, LagerLogLevel);
                 (_) ->
                      ok
              end, gen_event:which_handlers(lager_event))
    end,
    {module, lager};
set({_LogLevel, _}) ->
    error_logger:error_msg("custom loglevels are not supported for 'lager'"),
    {module, lager}.

-else.

start() ->
    set(4),
    LogPath = get_log_path(),
    error_logger:add_report_handler(p1_logger_h, LogPath),
    ok.

reopen_log() ->
    %% TODO: Use the Reopen log API for logger_h ?
    p1_logger_h:reopen_log(),
    reopen_sasl_log().

get() ->
    p1_loglevel:get().

set(LogLevel) ->
    p1_loglevel:set(LogLevel).

-endif.

%%%===================================================================
%%% Internal functions
%%%===================================================================
reopen_sasl_log() ->
    case application:get_env(sasl,sasl_error_logger) of
	{ok, {file, SASLfile}} ->
	    error_logger:delete_report_handler(sasl_report_file_h),
            rotate_sasl_log(SASLfile),
	    error_logger:add_report_handler(sasl_report_file_h,
	        {SASLfile, get_sasl_error_logger_type()});
	_ -> false
	end,
    ok.

rotate_sasl_log(Filename) ->
    case file:read_file_info(Filename) of
        {ok, _FileInfo} ->
            file:rename(Filename, [Filename, ".0"]),
            ok;
        {error, _Reason} ->
            ok
    end.

%% Function copied from Erlang/OTP lib/sasl/src/sasl.erl which doesn't export it
get_sasl_error_logger_type () ->
    case application:get_env (sasl, errlog_type) of
	{ok, error} -> error;
	{ok, progress} -> progress;
	{ok, all} -> all;
	{ok, Bad} -> exit ({bad_config, {sasl, {errlog_type, Bad}}});
	_ -> all
    end.
