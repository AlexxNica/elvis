-module(elvis_style).

-export([
         line_length/3,
         no_tabs/3,
         macro_names/3,
         macro_module_names/3,
         operator_spaces/3,
         nesting_level/3,
         indentation_format/3
        ]).

-define(LINE_LENGTH_MSG, "Line ~p is too long: ~p.").
-define(NO_TABS_MSG, "Line ~p has a tab at column ~p.").
-define(INVALID_MACRO_NAME_MSG,
            "Invalid macro name ~s on line ~p. Use UPPER_CASE.").
-define(MACRO_AS_MODULE_NAME_MSG,
            "Don't use macros (like ~s on line ~p) as module names.").
-define(MACRO_AS_FUNCTION_NAME_MSG,
            "Don't use macros (like ~s on line ~p) as function names.").
-define(OPERATOR_SPACE_MSG, "Missing space ~s ~p on line ~p").
-define(NESTING_LEVEL_MSG,
        "The expression on line ~p and column ~p is nested "
        "beyond the maximum level of ~p.").
-define(INDENTATION_FORMAT_INVALID_MSG,
        "Invalid number of indentation characters on line ~p.").
-define(INDENTATION_FORMAT_MSG,
        "Invalid relative indentation from previous line ~p.").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Rules
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc Target can be either a filename or the
%% name of a module.
-spec line_length(elvis_config:config(), elvis_utils:file(), [term()]) ->
    [elvis_result:item()].
line_length(Config, Target, [Limit]) ->
    {ok, Src} = elvis_utils:src(Config, Target),
    elvis_utils:check_lines(Src, fun check_line_length/3, [Limit]).

-spec no_tabs(elvis_config:config(), elvis_utils:file(), [term()]) ->
    [elvis_result:item()].
no_tabs(Config, Target, []) ->
    {ok, Src} = elvis_utils:src(Config, Target),
    elvis_utils:check_lines(Src, fun check_no_tabs/3, []).

-spec macro_names(elvis_config:config(), elvis_utils:file(), [term()]) ->
    [elvis_result:item()].
macro_names(Config, Target, []) ->
    {ok, Src} = elvis_utils:src(Config, Target),
    elvis_utils:check_lines(Src, fun check_macro_names/3, []).

-spec macro_module_names(elvis_config:config(), elvis_utils:file(), []) ->
    [elvis_result:item_result()].
macro_module_names(Config, Target, []) ->
    {ok, Src} = elvis_utils:src(Config, Target),
    elvis_utils:check_lines(Src, fun check_macro_module_names/3, []).

-spec operator_spaces(elvis_config:config(),
                      elvis_utils:file(),
                      [{right|left, string()}]) ->
    [elvis_result:item_result()].
operator_spaces(Config, Target, Rules) ->
    {ok, Src} = elvis_utils:src(Config, Target),
    elvis_utils:check_lines(Src, fun check_operator_spaces/3, Rules).

-spec nesting_level(elvis_config:config(), elvis_utils:file(), [integer()]) ->
    [elvis_result:item_result()].
nesting_level(Config, Target, [Level]) ->
    {ok, Src} = elvis_utils:src(Config, Target),
    Root = elvis_code:parse_tree(Src),
    elvis_utils:check_nodes(Root, fun check_nesting_level/2, [Level]).

-spec indentation_format(elvis_config:config(),
                         elvis_utils:file(),
                         {char(), integer()}) ->
    [elvis_result:item_result()].
indentation_format(Config, Target, Opts) ->
    {ok, Src} = elvis_utils:src(Config, Target),
    Fun = fun check_indentation_format/3,
    elvis_utils:check_lines_with_context(Src, Fun, Opts, {1, 0}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Private
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec check_line_length(binary(), integer(), [term()]) ->
    no_result | {ok, elvis_result:item()}.
check_line_length(Line, Num, [Limit]) ->
    case byte_size(Line) of
        Large when Large > Limit ->
            Msg = ?LINE_LENGTH_MSG,
            Info = [Num, binary_to_list(Line)],
            Result = elvis_result:new(item, Msg, Info, Num),
            {ok, Result};
        _ ->
            no_result
    end.

-spec check_no_tabs(binary(), integer(), [term()]) ->
    no_result | {ok, elvis_result:item()}.
check_no_tabs(Line, Num, _Args) ->
    case binary:match(Line, <<"\t">>) of
        nomatch ->
            no_result;
        {Index, _} ->
            Msg = ?NO_TABS_MSG,
            Info = [Num, Index],
            Result = elvis_result:new(item, Msg, Info, Num),
            {ok, Result}
    end.

-spec check_macro_names(binary(), integer(), [term()]) ->
    no_result | {ok, elvis_result:item()}.
check_macro_names(Line, Num, _Args) ->
    {ok, Regex} = re:compile("^ *[-]define *[(]([^,]+)"),
    case re:run(Line, Regex, [{capture, all_but_first, list}]) of
        nomatch ->
            no_result;
        {match, [MacroName]} ->
            case string:to_upper(MacroName) of
                MacroName ->
                    no_result;
                _ ->
                    Msg = ?INVALID_MACRO_NAME_MSG,
                    Info = [MacroName, Num],
                    Result = elvis_result:new(item, Msg, Info, Num),
                    {ok, Result}
            end
    end.

-spec check_macro_module_names(binary(), integer(), [term()]) ->
    no_result | {ok, elvis_result:item_result()}.
check_macro_module_names(Line, Num, _Args) ->
    {ok, ModNameRegex} = re:compile("[?]([A-z0-9_]+)[:]"),
    {ok, FunNameRegex} = re:compile("[:][?]([A-z0-9_]+)"),
    case re:run(Line, ModNameRegex, [{capture, all_but_first, list}]) of
        nomatch ->
            case re:run(Line, FunNameRegex, [{capture, all_but_first, list}]) of
                nomatch ->
                    no_result;
                {match, [MacroName]} ->
                    Msg = ?MACRO_AS_FUNCTION_NAME_MSG,
                    Info = [MacroName, Num],
                    Result = elvis_result:new(item, Msg, Info, Num),
                    {ok, Result}
            end;
        {match, [MacroName]} ->
            Msg = ?MACRO_AS_MODULE_NAME_MSG,
            Info = [MacroName, Num],
            Result = elvis_result:new(item, Msg, Info, Num),
            {ok, Result}
    end.

-spec check_operator_spaces(binary(), integer(), [{right|left, string()}]) ->
    no_result | {ok, elvis_result:item_result()}.
check_operator_spaces(Line, Num, Rules) ->
    AllResults =
        [check_operator_spaces_rule(Line, Num, Rule) || Rule <- Rules],
    case [Result || {ok, Result} <- AllResults] of
        [] -> no_result;
        [Result|_] -> {ok, Result}
    end.
check_operator_spaces_rule(Line, Num, {right, Operator}) ->
    Escaped = [[$[, Char, $]] || Char <- Operator],
    {ok, Regex} = re:compile(Escaped ++ "[^ ]"),
    case re:run(<<Line/binary, " ">>, Regex) of
        nomatch ->
            no_result;
        {match, _} ->
            Msg = ?OPERATOR_SPACE_MSG,
            Info = ["after", Operator, Num],
            Result = elvis_result:new(item, Msg, Info, Num),
            {ok, Result}
    end;
check_operator_spaces_rule(Line, Num, {left, Operator}) ->
    Escaped = [[$[, Char, $]] || Char <- Operator],
    {ok, Regex} = re:compile("[^ ]" ++ Escaped),
    case re:run(<<" ", Line/binary>>, Regex) of
        nomatch ->
            no_result;
        {match, _} ->
            Msg = ?OPERATOR_SPACE_MSG,
            Info = ["before", Operator, Num],
            Result = elvis_result:new(item, Msg, Info, Num),
            {ok, Result}
    end.

-spec check_nesting_level(elvis_code:tree_node(), [integer()]) ->
    [elvis_result:item_result()].
check_nesting_level(ParentNode, [MaxLevel]) ->
    case elvis_code:past_nesting_limit(ParentNode, MaxLevel) of
        [] -> [];
        NestedNodes ->
            Msg = ?NESTING_LEVEL_MSG,

            Fun = fun(Node) ->
                {Line, Col} = elvis_code:attr(location, Node),
                Info = [Line, Col, MaxLevel],
                elvis_result:new(item, Msg, Info, Line)
            end,

            lists:map(Fun, NestedNodes)
    end.

-spec check_indentation_format([binary()], integer(), {char(), integer()}) ->
    no_result | {ok, elvis_result:item_result()}.
check_indentation_format({Line, [], []}, Num, {Char, Count}) ->
    check_indentation_format({Line, [""], []}, Num, {Char, Count});
check_indentation_format({Line, [Prev], []}, Num, {Char, Count}) ->
    IndentPrev = elvis_utils:indentation(Prev, Char, Count),
    IndentLine = elvis_utils:indentation(Line, Char, Count),
    case {IndentPrev, IndentLine} of
        {_, invalid} ->
            Msg = ?INDENTATION_FORMAT_INVALID_MSG,
            Info = [Num],
            Result = elvis_result:new(item, Msg, Info, Num),
            {ok, Result};
        {invalid, _} ->
            no_result;
        {_, _} when abs(IndentPrev - IndentLine) > 4 ->
            Msg = ?INDENTATION_FORMAT_MSG,
            Info = [Num],
            Result = elvis_result:new(item, Msg, Info, Num),
            {ok, Result};
        _Any ->
            no_result
    end.
