-module(elvis_SUITE).

-export([
         all/0,
         init_per_suite/1,
         end_per_suite/1
        ]).

-export([
         %% Rocking
         rock_with_empty_config/1,
         rock_with_incomplete_config/1,
         rock_with_file_config/1,
         %% Webhook
         run_webhook/1,
         %% Utill & Config
         throw_configuration/1,
         find_file_and_check_src/1,
         invalid_file/1,
         to_string/1,
         %% Mains & Commands
         main_help/1,
         main_commands/1,
         main_config/1,
         main_rock/1,
         main_git_hook_fail/1,
         main_git_hook_ok/1,
         main_default_config/1,
         main_unexistent/1
        ]).

-define(EXCLUDED_FUNS,
        [
         module_info,
         all,
         test,
         init_per_suite,
         end_per_suite
        ]).

-type config() :: [{atom(), term()}].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Common test
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec all() -> [atom()].
all() ->
    Exports = elvis_SUITE:module_info(exports),
    [F || {F, _} <- Exports, not lists:member(F, ?EXCLUDED_FUNS)].

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
    application:start(elvis),
    Config.

-spec end_per_suite(config()) -> config().
end_per_suite(Config) ->
    application:stop(elvis),
    Config.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Test Cases
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%
%%% Rocking

-spec rock_with_empty_config(config()) -> any().
rock_with_empty_config(_Config) ->
    ok = try
             elvis:rock(#{}),
             fail
         catch
             throw:{invalid_config, _} -> ok
         end.

-spec rock_with_incomplete_config(config()) -> any().
rock_with_incomplete_config(_Config) ->
    ElvisConfig = #{src_dirs => ["src"]},
    ok = try
             elvis:rock(ElvisConfig),
             fail
         catch
             throw:{invalid_config, _} -> ok
         end.

-spec rock_with_file_config(config()) -> ok.
rock_with_file_config(_Config) ->
    Fun = fun() -> elvis:rock() end,
    Expected = "# \\.\\./\\.\\./test/examples/.*\\.erl \\[FAIL\\]\n",
    check_first_line_output(Fun, Expected, fun matches_regex/2),
    ok.

%%%%%%%%%%%%%%%
%%% Webhook

-spec run_webhook(config()) -> any().
run_webhook(_Config) ->
    Headers = #{<<"x-github-event">> => <<"pull_request">>},
    Path = "../../test/examples/pull_request.js",
    {ok, Body} = file:read_file(Path),
    Request = #{headers => Headers, body => Body},

    try
        elvis:start(),

        meck:new(elvis_github, [passthrough]),
        FakeFun = fun(_, _, _) -> {ok, []} end,
        meck:expect(elvis_github, pull_req_files, FakeFun),
        meck:expect(elvis_github, pull_req_comments, FakeFun),

        ok = elvis:webhook(Request)
    after
        meck:unload(elvis_github)
    end.

%%%%%%%%%%%%%%%
%%% Utils

-spec throw_configuration(config()) -> any().
throw_configuration(_Config) ->
    Filename = "./elvis.config",
    ok = file:write_file(Filename, <<"-">>),
    ok = try
             elvis_config:default(),
             fail
         catch
             throw:_ -> ok
         after
             file:delete(Filename)
         end.

-spec find_file_and_check_src(config()) -> any().
find_file_and_check_src(_Config) ->
    Dirs = ["../../test/examples"],

    [] = elvis_utils:find_files(Dirs, "doesnt_exist.erl"),
    [File] = elvis_utils:find_files(Dirs, "small.erl"),

    {<<"-module(small).\n">>, _} = elvis_utils:src(File),
    {error, enoent} = elvis_utils:src(#{path => "doesnt_exist.erl"}).

-spec invalid_file(config()) -> any().
invalid_file(_Config) ->
    ok = try
             elvis_utils:src(#{}),
             fail
         catch
             throw:{invalid_file, #{}} -> ok
         end.

-spec to_string(config()) -> any().
to_string(_Config) ->
    "1" = elvis_utils:to_str(1),
    "hello" = elvis_utils:to_str(<<"hello">>),
    "atom" = elvis_utils:to_str(atom).

%%%%%%%%%%%%%%%
%%% Main & Commands

-spec main_help(config()) -> any().
main_help(_Config) ->
    Expected = "Usage: elvis",

    ShortOptFun = fun() -> elvis:main("-h") end,
    check_first_line_output(ShortOptFun, Expected, fun starts_with/2),

    LongOptFun = fun() -> elvis:main("--help") end,
    check_first_line_output(LongOptFun, Expected, fun starts_with/2),

    EmptyFun = fun() -> elvis:main("") end,
    check_first_line_output(EmptyFun, Expected, fun starts_with/2),

    CmdFun = fun() -> elvis:main("help") end,
    check_first_line_output(CmdFun, Expected, fun starts_with/2),

    ok.

-spec main_commands(config()) -> any().
main_commands(_Config) ->
    Expected = "Elvis will do the following things",

    OptFun = fun() -> elvis:main("--commands") end,
    check_first_line_output(OptFun, Expected, fun starts_with/2),

    ok.

-spec main_config(config()) -> any().
main_config(_Config) ->
    Expected = "Error: missing_option_arg config",

    OptFun = fun() -> elvis:main("-c") end,
    check_first_line_output(OptFun, Expected, fun starts_with/2),

    EnoentExpected = "Error: enoent.\n",
    OptEnoentFun = fun() -> elvis:main("-c missing") end,
    check_first_line_output(OptEnoentFun, EnoentExpected),

    ConfigFileFun = fun() -> elvis:main("-c ../../config/elvis.config") end,
    check_first_line_output(ConfigFileFun, ""),

    ok.

-spec main_rock(config()) -> any().
main_rock(_Config) ->
    ExpectedFail = "# \\.\\./\\.\\./test/examples/.*\\.erl \\[FAIL\\]\n",

    NoConfigArgs = "rock",
    NoConfigFun = fun() -> elvis:main(NoConfigArgs) end,
    check_first_line_output(NoConfigFun, ExpectedFail, fun matches_regex/2),

    Expected = "# ../../src/elvis.erl [OK]",

    ConfigArgs = "rock -c ../../config/elvis-test.config",
    ConfigFun = fun() -> elvis:main(ConfigArgs) end,
    check_first_line_output(ConfigFun, Expected, fun starts_with/2),

    ok.

-spec main_git_hook_fail(config()) -> any().
main_git_hook_fail(_Config) ->
    try
        meck:new(elvis_utils, [passthrough]),
        meck:expect(elvis_utils, erlang_halt, fun(Code) -> Code end),

        meck:new(elvis_git, [passthrough]),
        LongLine = <<"Loooooooooooooooooooooooooooooooooooooooooooooooooooong ",
                     "Liiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiine">>,
        Files = [
                 #{path => "fake_long_line.erl",
                   content => LongLine}
                ],
        FakeStagedFiles = fun() -> Files end,
        meck:expect(elvis_git, staged_files, FakeStagedFiles),

        Expected = "# fake_long_line.erl [FAIL]",

        ConfigArgs = "git-hook -c ../../config/elvis-test.config",
        ConfigFun = fun() -> elvis:main(ConfigArgs) end,
        check_first_line_output(ConfigFun, Expected, fun starts_with/2),

        meck:expect(elvis_git, staged_files, fun() -> [] end),
        check_first_line_output(ConfigFun, [])
    after
        catch
            meck:unload(elvis_utils),
            meck:unload(elvis_git)
    end.

-spec main_git_hook_ok(config()) -> any().
main_git_hook_ok(_Config) ->
    try
        meck:new(elvis_git, [passthrough]),
        meck:expect(elvis_git, staged_files, fun() -> [] end),

        ConfigArgs = "git-hook -c ../../config/elvis-test.config",
        ConfigFun = fun() -> elvis:main(ConfigArgs) end,
        check_first_line_output(ConfigFun, [])
    after
        catch meck:unload(elvis_git)
    end.

-spec main_default_config(config()) -> any().
main_default_config(_Config) ->
    Src = "../../config/elvis-test.config",
    Dest = "./elvis.config",
    file:copy(Src, Dest),

    Expected = "# ../../src/elvis.erl [OK]",
    RockFun = fun() -> elvis:main("rock") end,
    check_first_line_output(RockFun, Expected, fun starts_with/2),

    file:delete(Dest),

    ok.

-spec main_unexistent(config()) -> any().
main_unexistent(_Config) ->
    Expected = "Error: unrecognized_or_unimplemened_command.\n",

    UnexistentFun = fun() -> elvis:main("aaarrrghh") end,
    check_first_line_output(UnexistentFun, Expected),

    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Private
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

check_first_line_output(Fun, Expected) ->
    Equals = fun(Result, Exp) ->
                 Result = Exp
             end,
    check_first_line_output(Fun, Expected, Equals).

check_first_line_output(Fun, Expected, CheckFun) ->
    ct:capture_start(),
    Fun(),
    ct:capture_stop(),
    Result = case ct:capture_get([]) of
                 [] -> "";
                 [Head | _] -> Head
             end,

    CheckFun(Result, Expected).

starts_with(Result, Expected) ->
    case string:str(Result, Expected) of
        1 -> ok;
        _ ->  {Expected, Expected}= {Result, Expected}
    end.

matches_regex(Result, Regex) ->
    case re:run(Result, Regex) of
        {match, _} -> true;
        nomatch -> false
    end.
