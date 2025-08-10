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
import 'components/player/player_component.dart';
import 'components/score_component.dart';
import 'components/time_component.dart';

// Добавим в начало класса MatchGame
final Map<PlayerPosition, Vector2> _initialPositions = {
  PlayerPosition.gk: Vector2(0.05, 0.5),
  PlayerPosition.cb: Vector2(0.15, 0.5),
  PlayerPosition.rb: Vector2(0.15, 0.7),
  PlayerPosition.lb: Vector2(0.15, 0.3),
  PlayerPosition.dm: Vector2(0.25, 0.5),
  PlayerPosition.cm: Vector2(0.35, 0.5),
  PlayerPosition.am: Vector2(0.45, 0.5),
  PlayerPosition.lm: Vector2(0.35, 0.3),
  PlayerPosition.rm: Vector2(0.35, 0.7),
  PlayerPosition.lw: Vector2(0.55, 0.3),
  PlayerPosition.rw: Vector2(0.55, 0.7),
  PlayerPosition.cf: Vector2(0.55, 0.5),
  PlayerPosition.ss: Vector2(0.55, 0.45),
  PlayerPosition.st: Vector2(0.55, 0.55),
};

enum GameState { firstHalf, halftime, secondHalf, finished }

class MatchGame extends FlameGame {
  // Constants
  static const double halftimeDuration = 45;
  final Vector2 fieldSize = Vector2(1000, 600);

  // Game components
  late BallComponent ball;
  late GoalComponent leftGoal;
  late GoalComponent rightGoal;

  // Game state
  final Random random = Random();
  double elapsedTime = 0;
  GameState gameState = GameState.firstHalf;

  // Teams
  final List<PlayerComponent> players = [];
  late TeamModel teamA; // left in first half
  late TeamModel teamB; // right in first half
  int teamAscore = 0;
  int teamBscore = 0;

  @override
  Vector2 get size => fieldSize;

  @override
  Future<void> onLoad() async {
    _initializeGameComponents();
    _setupCamera();
    await super.onLoad();
  }

  // Initialization methods
  void _initializeGameComponents() {
    _setupField();
    _setupGoals();
    _setupBall();
    _setupTeams();
  }

  void _setupField() {
    world.add(RectangleComponent(size: fieldSize, paint: Paint()..color = const Color(0xFF1E8B3A)));
  }

  void _setupGoals() {
    leftGoal = GoalComponent(position: Vector2(0, size.y / 2 - 30));
    rightGoal = GoalComponent(position: Vector2(size.x - 10, size.y / 2 - 30));
    world.addAll([leftGoal, rightGoal]);
  }

  void _setupBall() {
    ball = BallComponent(position: size / 2);
    world.add(ball);
  }

  void _setupTeams() {
    _createTeams();
    _positionTeams();
    _linkPlayersToBall();
    _setInitialBallOwner();
  }

  void _setupCamera() {
    camera.smoothFollow(ball, stiffness: 0.85);
    camera.viewport.add(ScoreComponent(getScore: () => '${teamA.name}  |$teamAscore : $teamBscore|  ${teamB.name}'));
    camera.viewport.add(TimeComponent(getTime: () => "${elapsedTime.toStringAsFixed(0)}'"));
  }

  // Team management methods
  void _createTeams() {
    teamA = _createTeamA();
    teamB = _createTeamB();

    players.addAll([
      ...teamA.startingPlayers.map((pit) => PlayerComponent(pit: pit)),
      ...teamB.startingPlayers.map((pit) => PlayerComponent(pit: pit)),
    ]);

    world.addAll(players);
  }

  TeamModel _createTeamA() {
    const teamId = "team_a_id";
    return TeamModel(
      id: teamId,
      name: "Red",
      color: Colors.red,
      startingPlayers: [
        _createPlayer(teamId, 1, PlayerPosition.gk, 60, 60, 60, 60, 60, 100),
        _createPlayer(teamId, 2, PlayerPosition.cb, 70, 70, 70, 85, 65, 40),
        _createPlayer(teamId, 3, PlayerPosition.cb, 70, 70, 70, 85, 65, 40),
        _createPlayer(teamId, 4, PlayerPosition.rb, 80, 70, 70, 75, 80, 40),
        _createPlayer(teamId, 5, PlayerPosition.lb, 80, 70, 70, 75, 80, 40),
        _createPlayer(teamId, 6, PlayerPosition.dm, 75, 80, 70, 80, 70, 40),
        _createPlayer(teamId, 7, PlayerPosition.cm, 75, 80, 75, 75, 75, 40),
        _createPlayer(teamId, 8, PlayerPosition.cm, 75, 80, 75, 75, 75, 40),
        _createPlayer(teamId, 9, PlayerPosition.rw, 90, 75, 80, 60, 85, 40),
        _createPlayer(teamId, 10, PlayerPosition.lw, 90, 75, 80, 60, 85, 40),
        _createPlayer(teamId, 11, PlayerPosition.st, 95, 75, 85, 60, 80, 40),
      ],
    );
  }

  TeamModel _createTeamB() {
    const teamId = "team_b_id";
    return TeamModel(
      id: teamId,
      name: "Blue",
      color: Colors.blue,
      startingPlayers: [
        _createPlayer(teamId, 1, PlayerPosition.gk, 60, 60, 60, 60, 60, 100),
        _createPlayer(teamId, 2, PlayerPosition.cb, 70, 70, 70, 85, 65, 40),
        _createPlayer(teamId, 3, PlayerPosition.cb, 70, 70, 70, 85, 65, 40),
        _createPlayer(teamId, 4, PlayerPosition.rb, 80, 70, 70, 75, 80, 40),
        _createPlayer(teamId, 5, PlayerPosition.lb, 80, 70, 70, 75, 80, 40),
        _createPlayer(teamId, 6, PlayerPosition.dm, 75, 80, 70, 80, 70, 40),
        _createPlayer(teamId, 7, PlayerPosition.cm, 75, 80, 75, 75, 75, 40),
        _createPlayer(teamId, 8, PlayerPosition.cm, 75, 80, 75, 75, 75, 40),
        _createPlayer(teamId, 9, PlayerPosition.rw, 90, 75, 80, 60, 85, 40),
        _createPlayer(teamId, 10, PlayerPosition.lw, 90, 75, 80, 60, 85, 40),
        _createPlayer(teamId, 11, PlayerPosition.st, 95, 75, 85, 60, 80, 40),
      ],
    );
  }

  PlayerInTeamModel _createPlayer(
    String teamId,
    int number,
    PlayerPosition position,
    double maxSpeed,
    double lowPass,
    double shoots,
    double defence,
    double dribbling,
    double goalkeeper,
  ) {
    return PlayerInTeamModel(
      teamId: teamId,
      number: number,
      position: position,
      data: PlayerModel(
        id: "$teamId-$number",
        name: "$number",
        usualPosition: position,
        stats: PlayerStats(
          maxSpeed: maxSpeed,
          lowPass: lowPass,
          shoots: shoots,
          defence: defence,
          dribbling: dribbling,
          goalkeeper: goalkeeper,
        ),
      ),
    );
  }

  void _positionTeams() {
    final teamAplayers = players.where((p) => p.pit.teamId == teamA.id).toList();
    final teamBplayers = players.where((p) => p.pit.teamId == teamB.id).toList();

    if (isTeamOnLeftSide(teamA.id)) {
      _positionTeam(teamAplayers, 100); // Team A on left
      _positionTeam(teamBplayers, size.x - 100); // Team B on right
    } else {
      _positionTeam(teamBplayers, 100); // Team B on left
      _positionTeam(teamAplayers, size.x - 100); // Team A on right
    }
  }

  void _positionTeam(List<PlayerComponent> team, double baseX) {
    final isLeftTeam = baseX < size.x / 2;

    for (final player in team) {
      final relativePos = _initialPositions[player.pit.position] ?? Vector2(0.5, 0.5);

      // Рассчитываем абсолютные координаты с учетом стороны поля
      final xPos = isLeftTeam ? baseX + relativePos.x * size.x * 0.5 : baseX - (1.0 - relativePos.x) * size.x * 0.5;

      final yPos = relativePos.y * size.y;

      // Добавляем случайный разброс
      final randomOffset = Vector2((random.nextDouble() - 0.5) * 10, (random.nextDouble() - 0.5) * 10);

      player.position = Vector2(xPos, yPos) + randomOffset;
    }
  }

  void _linkPlayersToBall() {
    for (final player in players) {
      player.assignBallRef(ball);
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

  // Game state management
  @override
  void update(double dt) {
    super.update(dt);

    if (gameState == GameState.finished) return;

    _updateGameTime(dt);
    _checkGamePhaseTransitions();
    _updateActiveGameState();
  }

  void _updateGameTime(double dt) {
    elapsedTime += dt;
  }

  void _checkGamePhaseTransitions() {
    if (gameState == GameState.firstHalf && elapsedTime >= halftimeDuration) {
      _handleHalftime();
    } else if (gameState == GameState.secondHalf && elapsedTime >= 2 * halftimeDuration) {
      _finishGame();
    }
  }

  void _updateActiveGameState() {
    if (gameState == GameState.firstHalf || gameState == GameState.secondHalf) {
      _checkGoals();
      _clampComponentsToField();
    }
  }

  void _handleHalftime() {
    gameState = GameState.halftime;
    print('🕒 Halftime! Teams will swap sides.');
    _resetForSecondHalf();
  }

  void _resetForSecondHalf() {
    gameState = GameState.secondHalf;
    _resetBallPosition();
    _resetPlayersPositions();
    _assignNewBallOwnerAfterHalftime();
  }

  void _resetBallPosition() {
    ball.position = size / 2;
    ball.velocity = Vector2.zero();
  }

  void _assignNewBallOwnerAfterHalftime() {
    final firstOwner = players.random(random);
    ball.takeOwnership(firstOwner);
    final directionToCenter = (size / 2 - firstOwner.position).normalized();
    ball.position = firstOwner.position + directionToCenter * (firstOwner.radius + ball.radius + 1);
  }

  void _finishGame() {
    gameState = GameState.finished;
    _stopAllMovement();
    print('🏁 Match finished! Final score: ${teamA.name} $teamAscore : $teamBscore ${teamB.name}');
  }

  void _stopAllMovement() {
    ball.velocity = Vector2.zero();
    for (final player in players) {
      player.velocity = Vector2.zero();
    }
  }

  // Goal management
  void _checkGoals() {
    if (leftGoal.isGoal(ball.position)) {
      _handleGoal(isTeamOnLeftSide(teamA.id) ? teamB.id : teamA.id);
    } else if (rightGoal.isGoal(ball.position)) {
      _handleGoal(isTeamOnLeftSide(teamA.id) ? teamA.id : teamB.id);
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

  void resetAfterGoal({required String scoringTeamId}) {
    _resetPlayersPositions();
    _assignNewBallOwnerAfterGoal(scoringTeamId);
  }

  void _resetPlayersPositions() {
    final teamAplayers = players.where((p) => p.pit.teamId == teamA.id).toList();
    final teamBplayers = players.where((p) => p.pit.teamId == teamB.id).toList();

    if (isTeamOnLeftSide(teamA.id)) {
      _positionTeam(teamAplayers, size.x * 0.1); // 10% от ширины поля
      _positionTeam(teamBplayers, size.x * 0.7); // 70% от ширины поля
    } else {
      _positionTeam(teamBplayers, size.x * 0.1);
      _positionTeam(teamAplayers, size.x * 0.7);
    }
  }

  void _assignNewBallOwnerAfterGoal(String scoringTeamId) {
    final opposingTeamPlayers = players.where((p) => p.pit.teamId != scoringTeamId).toList();
    final newOwner = opposingTeamPlayers[random.nextInt(opposingTeamPlayers.length)];
    ball.takeOwnership(newOwner);

    final directionToCenter = (size / 2 - newOwner.position).normalized();
    ball.position = newOwner.position + directionToCenter * (newOwner.radius + ball.radius + 1);
  }

  void _clampComponentsToField() {
    for (final component in children.whereType<PositionComponent>()) {
      component.position.x = component.position.x.clamp(0.0, size.x);
      component.position.y = component.position.y.clamp(0.0, size.y);
    }
  }

  // Utility methods
  Vector2 getGoalPositionForTeam(String teamId) {
    return isTeamOnLeftSide(teamId) ? rightGoal.center : leftGoal.center;
  }

  bool isTeamOnLeftSide(String teamId) {
    final isFirstHalf = gameState == GameState.firstHalf;
    return teamId == teamA.id ? isFirstHalf : !isFirstHalf;
  }

  bool isOwnHalf(String teamId, Vector2 position) {
    final fieldMiddle = size.x / 2;
    final isTeamAOnLeft = gameState == GameState.firstHalf;
    final isOnLeftSide = position.x < fieldMiddle;

    return (teamId == teamA.id) ? (isTeamAOnLeft == isOnLeftSide) : (isTeamAOnLeft != isOnLeftSide);
  }
}
