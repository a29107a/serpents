-module(spts_events_SUITE).

-include_lib("mixer/include/mixer.hrl").
-mixin([
        {spts_test_utils,
         [ init_per_suite/1
         , end_per_suite/1
         ]}
       ]).

-export([ all/0
        , init_per_testcase/2
        , end_per_testcase/2
        ]).
-export([ player_joined/1
        , game_started/1
        , game_finished/1
        , game_updated/1
        , collision_detected/1
        , game_countdown/1
        ]).

-spec all() -> [atom()].
all() -> spts_test_utils:all(?MODULE).

-spec init_per_testcase(atom(), spts_test_utils:config()) ->
  spts_test_utils:config().
init_per_testcase(Test, Config) ->
  Countdown =
    case Test of
      game_countdown -> 5;
      Test -> 0
    end,
  GameId =
    spts_games:id(
      spts_core:create_game(
        #{cols => 5, rows => 5, ticktime => 1000000, countdown => Countdown})),
  Player1Id = spts_players:id(spts_core:register_player(<<"1">>)),
  Player2Id = spts_players:id(spts_core:register_player(<<"2">>)),
  Player3Id = spts_players:id(spts_core:register_player(<<"3">>)),
  [ {player1, Player1Id}
  , {player2, Player2Id}
  , {player3, Player3Id}
  , {game, GameId}
  | Config].

-spec end_per_testcase(atom(), spts_test_utils:config()) ->
  spts_test_utils:config().
end_per_testcase(_Test, Config) ->
  {game, GameId} = lists:keyfind(game, 1, Config),
  ok = spts_test_handler:unsubscribe(GameId, self()),
  ok = spts_core:stop_game(GameId),
  lists:filter(
    fun ({K, _}) -> not lists:member(K, [game, player1, player2, player3]) end,
    Config).

-spec player_joined(spts_test_utils:config()) -> {comment, []}.
player_joined(Config) ->
  {game, GameId} = lists:keyfind(game, 1, Config),
  {player1, Player1Id} = lists:keyfind(player1, 1, Config),
  {player2, Player2Id} = lists:keyfind(player2, 1, Config),

  ok = spts_test_handler:subscribe(GameId, self()),
  ct:comment("A player joins, we receive an event"),
  {Position1, _} = spts_core:join_game(GameId, Player1Id),
  ok = spts_test_handler:wait_for({player_joined, Player1Id, Position1}, []),

  ct:comment("Another player joins, we receive another event"),
  {Position2, _} = spts_core:join_game(GameId, Player2Id),
  ok = spts_test_handler:wait_for({player_joined, Player2Id, Position2}, []),

  {comment, ""}.

-spec game_started(spts_test_utils:config()) -> {comment, []}.
game_started(Config) ->
  {game, GameId} = lists:keyfind(game, 1, Config),
  {player1, Player1Id} = lists:keyfind(player1, 1, Config),

  ct:comment("A player joins"),
  {_, _} = spts_core:join_game(GameId, Player1Id),

  ok = spts_test_handler:subscribe(GameId, self()),
  ct:comment("The Game starts, we receive an event"),
  ok = spts_core:start_game(GameId),
  Game = spts_core:fetch_game(GameId),
  ok = spts_test_handler:wait_for({game_started, Game}),

  ct:comment("The Game doesn't start again, we don't receive an event"),
  ok = spts_core:start_game(GameId),
  ok = spts_test_handler:no_events(),

  {comment, ""}.

-spec game_finished(spts_test_utils:config()) -> {comment, []}.
game_finished(Config) ->
  {game, GameId} = lists:keyfind(game, 1, Config),
  {player1, Player1Id} = lists:keyfind(player1, 1, Config),
  {_, _} = spts_core:join_game(GameId, Player1Id),
  ok = spts_core:start_game(GameId),

  ok = spts_test_handler:subscribe(GameId, self()),
  tested =
    lists:foldl(
      fun (_, started) ->
            ct:comment("Game is on course, we keep moving"),
            ok = spts_test_handler:flush(),
            spts_games:process_name(GameId) ! tick,
            spts_games:state(spts_core:fetch_game(GameId));
          (_, finished) ->
            ct:comment("Game ended, we should get an event"),
            Game = spts_core:fetch_game(GameId),
            ok = spts_test_handler:wait_for({game_finished, Game}),
            tested;
          (_, tested) ->
            tested
      end, started, lists:seq(1, 7)),

  {comment, ""}.

-spec game_updated(spts_test_utils:config()) -> {comment, []}.
game_updated(Config) ->
  {game, GameId} = lists:keyfind(game, 1, Config),
  {player1, Player1Id} = lists:keyfind(player1, 1, Config),
  {_, _} = spts_core:join_game(GameId, Player1Id),
  ok = spts_core:start_game(GameId),

  ok = spts_test_handler:subscribe(GameId, self()),
  spts_games:process_name(GameId) ! tick,
  FinishedGame =
    lists:foldl(
      fun(_, Game) ->
        case spts_games:state(Game) of
          started ->
            ct:comment("Game is on course, we receive an update"),
            ok = spts_test_handler:wait_for({game_updated, Game}),
            spts_games:process_name(GameId) ! tick,
            spts_core:fetch_game(GameId);
          finished ->
            Game
        end
      end, spts_core:fetch_game(GameId), lists:seq(1, 6)),
  finished = spts_games:state(FinishedGame),

  {comment, ""}.

-spec collision_detected(spts_test_utils:config()) -> {comment, []}.
collision_detected(Config) ->
  {game, GameId} = lists:keyfind(game, 1, Config),
  {player1, Player1Id} = lists:keyfind(player1, 1, Config),
  {player2, Player2Id} = lists:keyfind(player2, 1, Config),
  {player3, Player3Id} = lists:keyfind(player3, 1, Config),
  {_, _} = spts_core:join_game(GameId, Player1Id),
  {_, _} = spts_core:join_game(GameId, Player2Id),
  {_, _} = spts_core:join_game(GameId, Player3Id),
  ok = spts_core:start_game(GameId),

  ReceiveCollision =
    fun(Serpent) ->
      receive
        {event, {collision_detected, Serpent}} -> ok;
        {info, Info} -> ct:fail("Unexpected Info: ~p", [Info])
      after 1000 ->
        ct:fail("Collision not detected")
      end
    end,

  ok = spts_test_handler:subscribe(GameId, self()),
  [_, _, _] =
    lists:foldl(
      fun(_, DeadSerpents) ->
        spts_games:process_name(GameId) ! tick,
        NewDeadSerpents =
          [S || S <- spts_games:serpents(spts_core:fetch_game(GameId))
              , spts_serpents:status(S) == dead
              , not lists:member(S, DeadSerpents)],
        ct:comment("Should detect collisions for ~p", [NewDeadSerpents]),
        lists:foreach(ReceiveCollision, NewDeadSerpents),
        NewDeadSerpents ++ DeadSerpents
      end, [], lists:seq(1, 7)),

  {comment, ""}.

-spec game_countdown(spts_test_utils:config()) -> {comment, []}.
game_countdown(Config) ->
  {game, GameId} = lists:keyfind(game, 1, Config),
  {player1, Player1Id} = lists:keyfind(player1, 1, Config),
  {_, _} = spts_core:join_game(GameId, Player1Id),

  ok = spts_test_handler:subscribe(GameId, self()),
  ok = spts_core:start_game(GameId),

  lists:foreach(
    fun(Round) ->
      ct:comment("Still missing ~p rounds of countdown...", [Round]),
      ok = spts_test_handler:wait_for({game_countdown, Round, Round * 1000000}),
      spts_games:process_name(GameId) ! tick
    end, lists:seq(5, 1, -1)),

  ct:comment("After the last countdown, the game should start normally"),
  ok = spts_test_handler:wait_for({game_started, spts_core:fetch_game(GameId)}),

  {comment, ""}.