import 'dart:math';

import 'package:draft_app/draft/game/models/player.dart';
import 'package:draft_app/draft/game/models/team.dart';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flame_camera_tools/flame_camera_tools.dart';
import 'package:flutter/material.dart';

import 'components/ball_component.dart';
import 'components/goal_component.dart';
import 'components/player_component.dart';
import 'components/score_component.dart';
import 'components/time_component.dart';

enum GameState { firstHalf, halftime, secondHalf, finished }

class MatchGame extends FlameGame {
  final fieldSize = Vector2(1000, 600); // Настоящее поле
  late BallComponent ball;
  late GoalComponent leftGoal;
  late GoalComponent rightGoal;

  final Random random = Random();

  double elapsedTime = 0;
  double halftimeDuration = 45;
  GameState gameState = GameState.firstHalf;

  final List<PlayerComponent> players = [];

  late TeamModel teamA; // left in first half
  late TeamModel teamB; // right in first half
  int teamAscore = 0;
  int teamBscore = 0;

  Vector2 getGoalPositionForTeam(String teamId) {
    final isLeftSide = isTeamOnLeftSide(teamId);
    return isLeftSide ? rightGoal.center : leftGoal.center;
  }

  bool isTeamOnLeftSide(String teamId) {
    final isFirstHalf = gameState == GameState.firstHalf;
    final isTeamALeft = isFirstHalf;
    return teamId == teamA.id ? isTeamALeft : !isTeamALeft;
  }

  bool isOwnHalf(String teamId, Vector2 position) {
    final fieldMiddle = size.x / 2;
    final isFirstHalf = gameState == GameState.firstHalf;
    final isTeamAOnLeft = isFirstHalf;
    final isOnLeftSide = position.x < fieldMiddle;

    if (teamId == teamA.id) {
      return isTeamAOnLeft == isOnLeftSide;
    } else {
      return isTeamAOnLeft != isOnLeftSide;
    }
  }

  // Переопределим size getter для компонента
  @override
  Vector2 get size => fieldSize;

  @override
  Future<void> onLoad() async {
    _setupField();
    _setupGoals();
    _setupBall();
    _setupPlayers();

    // Установите камеру для следования за мячом
    camera.smoothFollow(ball, stiffness: 0.85);
    camera.viewport.add(ScoreComponent(getScore: () => '${teamA.name}  |$teamAscore : $teamBscore|  ${teamB.name}'));
    camera.viewport.add(TimeComponent(getTime: () => "${elapsedTime.toStringAsFixed(0)}'"));

    return super.onLoad();
  }

  void _setupField() {
    world.add(RectangleComponent(size: fieldSize, paint: Paint()..color = const Color(0xFF1E8B3A)));
  }

  void _setupGoals() {
    leftGoal = GoalComponent(position: Vector2(0, size.y / 2 - 30));
    rightGoal = GoalComponent(position: Vector2(size.x - 10, size.y / 2 - 30));
    world.addAll([leftGoal, rightGoal]);
  }

  _setupBall() {
    ball = BallComponent(position: size / 2);
    world.add(ball);
  }

  void _setupPlayers() {
    _createTeams();
    _positionTeams();
    _linkPlayersToBall();
    _setInitialBallOwner();
  }

  void _createTeams() {
    final aId = "team_a_id";
    final bId = "team_b_id";

    teamA = TeamModel(
      id: aId,
      name: "Red",
      color: Colors.red,
      startingPlayers: [
        PlayerInTeamModel(
          teamId: aId,
          number: 1,
          position: PlayerPosition.gk,
          data: PlayerModel(
            id: "$aId-1",
            name: "1",
            usualPosition: PlayerPosition.gk,
            stats: PlayerStats(maxSpeed: 60, lowPass: 60, shoots: 60, defence: 60, dribbling: 60, goalkeeper: 100),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 2,
          position: PlayerPosition.cb,
          data: PlayerModel(
            id: "$aId-2",
            name: "2",
            usualPosition: PlayerPosition.cb,
            stats: PlayerStats(maxSpeed: 70, lowPass: 70, shoots: 70, defence: 85, dribbling: 65, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 3,
          position: PlayerPosition.cb,
          data: PlayerModel(
            id: "$aId-3",
            name: "3",
            usualPosition: PlayerPosition.cb,
            stats: PlayerStats(maxSpeed: 70, lowPass: 70, shoots: 70, defence: 85, dribbling: 65, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 4,
          position: PlayerPosition.rb,
          data: PlayerModel(
            id: "$aId-4",
            name: "4",
            usualPosition: PlayerPosition.rb,
            stats: PlayerStats(maxSpeed: 80, lowPass: 70, shoots: 70, defence: 75, dribbling: 80, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 5,
          position: PlayerPosition.lb,
          data: PlayerModel(
            id: "$aId-5",
            name: "5",
            usualPosition: PlayerPosition.lb,
            stats: PlayerStats(maxSpeed: 80, lowPass: 70, shoots: 70, defence: 75, dribbling: 80, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 6,
          position: PlayerPosition.dm,
          data: PlayerModel(
            id: "$aId-6",
            name: "6",
            usualPosition: PlayerPosition.dm,
            stats: PlayerStats(maxSpeed: 75, lowPass: 80, shoots: 70, defence: 80, dribbling: 70, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 7,
          position: PlayerPosition.cm,
          data: PlayerModel(
            id: "$aId-7",
            name: "7",
            usualPosition: PlayerPosition.cm,
            stats: PlayerStats(maxSpeed: 75, lowPass: 80, shoots: 75, defence: 75, dribbling: 75, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 8,
          position: PlayerPosition.cm,
          data: PlayerModel(
            id: "$aId-8",
            name: "8",
            usualPosition: PlayerPosition.cm,
            stats: PlayerStats(maxSpeed: 75, lowPass: 80, shoots: 75, defence: 75, dribbling: 75, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 9,
          position: PlayerPosition.rw,
          data: PlayerModel(
            id: "$aId-9",
            name: "9",
            usualPosition: PlayerPosition.rw,
            stats: PlayerStats(maxSpeed: 90, lowPass: 75, shoots: 80, defence: 60, dribbling: 85, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 10,
          position: PlayerPosition.lw,
          data: PlayerModel(
            id: "$aId-10",
            name: "10",
            usualPosition: PlayerPosition.lw,
            stats: PlayerStats(maxSpeed: 90, lowPass: 75, shoots: 80, defence: 60, dribbling: 85, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: aId,
          number: 11,
          position: PlayerPosition.st,
          data: PlayerModel(
            id: "$aId-11",
            name: "11",
            usualPosition: PlayerPosition.st,
            stats: PlayerStats(maxSpeed: 95, lowPass: 75, shoots: 85, defence: 60, dribbling: 80, goalkeeper: 40),
          ),
        ),
      ],
    );

    teamB = TeamModel(
      id: bId,
      name: "Blue",
      color: Colors.blue,
      startingPlayers: [
        PlayerInTeamModel(
          teamId: bId,
          number: 1,
          position: PlayerPosition.gk,
          data: PlayerModel(
            id: "$bId-1",
            name: "1",
            usualPosition: PlayerPosition.gk,
            stats: PlayerStats(maxSpeed: 60, lowPass: 60, shoots: 60, defence: 60, dribbling: 60, goalkeeper: 100),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 2,
          position: PlayerPosition.cb,
          data: PlayerModel(
            id: "$bId-2",
            name: "2",
            usualPosition: PlayerPosition.cb,
            stats: PlayerStats(maxSpeed: 70, lowPass: 70, shoots: 70, defence: 85, dribbling: 65, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 3,
          position: PlayerPosition.cb,
          data: PlayerModel(
            id: "$bId-3",
            name: "3",
            usualPosition: PlayerPosition.cb,
            stats: PlayerStats(maxSpeed: 70, lowPass: 70, shoots: 70, defence: 85, dribbling: 65, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 4,
          position: PlayerPosition.rb,
          data: PlayerModel(
            id: "$bId-4",
            name: "4",
            usualPosition: PlayerPosition.rb,
            stats: PlayerStats(maxSpeed: 80, lowPass: 70, shoots: 70, defence: 75, dribbling: 80, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 5,
          position: PlayerPosition.lb,
          data: PlayerModel(
            id: "$bId-5",
            name: "5",
            usualPosition: PlayerPosition.lb,
            stats: PlayerStats(maxSpeed: 80, lowPass: 70, shoots: 70, defence: 75, dribbling: 80, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 6,
          position: PlayerPosition.dm,
          data: PlayerModel(
            id: "$bId-6",
            name: "6",
            usualPosition: PlayerPosition.dm,
            stats: PlayerStats(maxSpeed: 75, lowPass: 80, shoots: 70, defence: 80, dribbling: 70, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 7,
          position: PlayerPosition.cm,
          data: PlayerModel(
            id: "$bId-7",
            name: "7",
            usualPosition: PlayerPosition.cm,
            stats: PlayerStats(maxSpeed: 75, lowPass: 80, shoots: 75, defence: 75, dribbling: 75, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 8,
          position: PlayerPosition.cm,
          data: PlayerModel(
            id: "$bId-8",
            name: "8",
            usualPosition: PlayerPosition.cm,
            stats: PlayerStats(maxSpeed: 75, lowPass: 80, shoots: 75, defence: 75, dribbling: 75, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 9,
          position: PlayerPosition.rw,
          data: PlayerModel(
            id: "$bId-9",
            name: "9",
            usualPosition: PlayerPosition.rw,
            stats: PlayerStats(maxSpeed: 90, lowPass: 75, shoots: 80, defence: 60, dribbling: 85, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 10,
          position: PlayerPosition.lw,
          data: PlayerModel(
            id: "$bId-10",
            name: "10",
            usualPosition: PlayerPosition.lw,
            stats: PlayerStats(maxSpeed: 90, lowPass: 75, shoots: 80, defence: 60, dribbling: 85, goalkeeper: 40),
          ),
        ),
        PlayerInTeamModel(
          teamId: bId,
          number: 11,
          position: PlayerPosition.st,
          data: PlayerModel(
            id: "$bId-11",
            name: "11",
            usualPosition: PlayerPosition.st,
            stats: PlayerStats(maxSpeed: 95, lowPass: 75, shoots: 85, defence: 60, dribbling: 80, goalkeeper: 40),
          ),
        ),
      ],
    );

    players.addAll([
      for (final pit in teamA.startingPlayers) PlayerComponent(pit: pit),
      for (final pit in teamB.startingPlayers) PlayerComponent(pit: pit),
    ]);

    world.addAll(players);
  }

  void _positionTeams() {
    final teamAplayers = players.where((p) => p.pit.teamId == teamA.id).toList();
    final teamBplayers = players.where((p) => p.pit.teamId == teamB.id).toList();

    if (isTeamOnLeftSide(teamA.id)) {
      _positionTeam(teamAplayers, 100); // Team A слева
      _positionTeam(teamBplayers, size.x - 100); // Team B справа
    } else {
      _positionTeam(teamBplayers, 100); // Team B слева
      _positionTeam(teamAplayers, size.x - 100); // Team A справа
    }
  }

  void _positionTeam(List<PlayerComponent> team, double xPos) {
    final spacingY = fieldSize.y / (team.length + 1);
    for (int i = 0; i < team.length; i++) {
      team[i].position = Vector2(xPos, spacingY * (i + 1));
    }
  }

  void _linkPlayersToBall() {
    for (final p in players) {
      p.assignBallRef(ball);
    }
    ball.assignPlayers(players);
  }

  void _setInitialBallOwner() {
    final firstOwner = players.random(random);
    ball.takeOwnership(firstOwner);
    final directionToCenter = (size / 2 - firstOwner.position).normalized();
    ball.position = firstOwner.position + directionToCenter * (firstOwner.radius + ball.radius + 1);
    ball.velocity = Vector2.zero();
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (gameState == GameState.finished) {
      return; // Полная остановка обновлений при завершении игры
    } // В MatchGame.update заменить проверку окончания
    else if (gameState == GameState.secondHalf && elapsedTime >= 2 * halftimeDuration) {
      finishGame(); // Используем новый метод вместо прямого изменения состояния
      return;
    }

    elapsedTime += dt;

    // Check for halftime transition
    if (gameState == GameState.firstHalf && elapsedTime >= halftimeDuration) {
      gameState = GameState.halftime;
      _handleHalftime();
    }
    // Check for second half end
    else if (gameState == GameState.secondHalf && elapsedTime >= 2 * halftimeDuration) {
      gameState = GameState.finished;
      print('🏁 Match finished! Final score: ${teamA.name} $teamAscore : $teamBscore ${teamB.name}');
      return;
    }

    // Only update game logic during active halves
    if (gameState == GameState.firstHalf || gameState == GameState.secondHalf) {
      _checkGoals();
      _clampComponentsToField();
    }
  }

  void _handleHalftime() {
    print('🕒 Halftime! Teams will swap sides.');
    // Reset positions and ball for second half
    _resetForSecondHalf();
  }

  void _resetForSecondHalf() {
    gameState = GameState.secondHalf;
    // Reset ball to center
    ball.position = size / 2;
    ball.velocity = Vector2.zero();

    // Clear ball ownership
    // ball.takeOwnership(null);

    // Reposition teams on opposite sides
    _resetPlayersPositions();
    // Assign new ball owner randomly
    final firstOwner = players.random(random);
    ball.takeOwnership(firstOwner);
    final directionToCenter = (size / 2 - firstOwner.position).normalized();
    ball.position = firstOwner.position + directionToCenter * (firstOwner.radius + ball.radius + 1);
  }

  void _checkGoals() {
    // Мяч в левом голе
    if (leftGoal.isGoal(ball.position)) {
      final scoringTeam = isTeamOnLeftSide(teamA.id) ? teamB : teamA;
      _handleGoal(scoringTeam.id);
    }
    // Мяч в правом голе
    else if (rightGoal.isGoal(ball.position)) {
      final scoringTeam = isTeamOnLeftSide(teamA.id) ? teamA : teamB;
      _handleGoal(scoringTeam.id);
    }
  }

  void _handleGoal(String scoringTeamId) {
    print('⚽️ GOAL for Team $scoringTeamId!');
    if (scoringTeamId == teamA.id) {
      teamAscore++;
    } else {
      teamBscore++;
    }
    resetAfterGoal(scoringTeamId: scoringTeamId);
  }

  void _clampComponentsToField() {
    for (final c in children.whereType<PositionComponent>()) {
      c.position.x = c.position.x.clamp(0.0, size.x);
      c.position.y = c.position.y.clamp(0.0, size.y);
    }
  }

  void resetAfterGoal({required String scoringTeamId}) {
    _resetPlayersPositions();
    _assignNewBallOwner(scoringTeamId);
  }

  void _resetPlayersPositions() {
    final teamAplayers = players.where((p) => p.pit.teamId == teamA.id).toList();
    final teamBplayers = players.where((p) => p.pit.teamId == teamB.id).toList();

    if (isTeamOnLeftSide(teamA.id)) {
      _positionTeam(teamAplayers, 100); // Team A слева
      _positionTeam(teamBplayers, size.x - 100); // Team B справа
    } else {
      _positionTeam(teamBplayers, 100); // Team B слева
      _positionTeam(teamAplayers, size.x - 100); // Team A справа
    }
  }

  void _assignNewBallOwner(String scoringTeamId) {
    final opposingTeamPlayers = players.where((p) => p.pit.teamId != scoringTeamId).toList();
    final newOwner = opposingTeamPlayers[random.nextInt(opposingTeamPlayers.length)];
    ball.takeOwnership(newOwner);

    final directionToCenter = (size / 2 - newOwner.position).normalized();
    ball.position = newOwner.position + directionToCenter * (newOwner.radius + ball.radius + 1);
  }

  void finishGame() {
    gameState = GameState.finished;
    // Остановить мяч
    ball.velocity = Vector2.zero();
    // Остановить всех игроков
    for (final player in players) {
      player.velocity = Vector2.zero();
    }
    print('Матч завершен! Финальный счет: ${teamA.name} $teamAscore : $teamBscore ${teamB.name}');
  }
}
