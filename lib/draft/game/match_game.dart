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

class MatchGame extends FlameGame {
  final fieldSize = Vector2(1000, 600); // Настоящее поле
  late BallComponent ball;
  late GoalComponent leftGoal;
  late GoalComponent rightGoal;

  final Random random = Random();

  double elapsedTime = 0;
  double halftimeDuration = 45;

  final List<PlayerComponent> players = [];

  late TeamModel teamA; // left
  late TeamModel teamB; // right
  int teamAscore = 0;
  int teamBscore = 0;

  Vector2 getGoalPositionForTeam(String teamId) {
    final isLeftSide = isTeamOnLeftSide(teamId);
    return isLeftSide ? rightGoal.center : leftGoal.center;
  }

  bool isTeamOnLeftSide(String teamId) {
    final isFirstHalf = elapsedTime < halftimeDuration;
    final isTeamALeft = isFirstHalf;
    return teamId == teamA.id ? isTeamALeft : !isTeamALeft;
  }

  bool isOwnHalf(String teamId, Vector2 position) {
    final fieldMiddle = size.x / 2;

    // Пример: если team 0 играет влево в первом тайме, вправо — во втором
    final isFirstHalf = elapsedTime < halftimeDuration;
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
      name: "A",
      color: Colors.red,
      startingPlayers: [
        for (int i = 0; i < 11; i++)
          PlayerInTeamModel(
            teamId: aId,
            number: i + 1,
            role: i < 4
                ? PlayerRole.defender
                : i < 8
                ? PlayerRole.midfielder
                : PlayerRole.forward,
            data: PlayerModel(
              id: "$aId-$i",
              name: "$aId-$i-name",
              stats: PlayerStats(
                maxSpeed: i < 4
                    ? 60
                    : i < 8
                    ? 80
                    : 100,
                lowPass: i < 4
                    ? 60
                    : i < 8
                    ? 100
                    : 80,
                shoots: i < 4
                    ? 60
                    : i < 8
                    ? 80
                    : 80,
                defence: i < 4
                    ? 100
                    : i < 8
                    ? 80
                    : 60,
                dribbling: i < 4
                    ? 60
                    : i < 8
                    ? 80
                    : 100,
              ),
            ),
          ),
      ],
    );

    teamB = TeamModel(
      id: bId,
      name: "B",
      color: Colors.blue,
      startingPlayers: [
        for (int i = 0; i < 11; i++)
          PlayerInTeamModel(
            teamId: bId,
            number: i + 1,
            role: i < 4
                ? PlayerRole.defender
                : i < 8
                ? PlayerRole.midfielder
                : PlayerRole.forward,
            data: PlayerModel(
              id: "$bId-$i",
              name: "$bId-$i-name",
              stats: PlayerStats(
                maxSpeed: i < 4
                    ? 60
                    : i < 8
                    ? 80
                    : 100,
                lowPass: i < 4
                    ? 60
                    : i < 8
                    ? 100
                    : 80,
                shoots: i < 4
                    ? 60
                    : i < 8
                    ? 80
                    : 80,
                defence: i < 4
                    ? 100
                    : i < 8
                    ? 80
                    : 60,
                dribbling: i < 4
                    ? 60
                    : i < 8
                    ? 80
                    : 100,
              ),
            ),
          ),
      ],
    );

    players.addAll([
      for (final p in teamA.startingPlayers) PlayerComponent(player: p),
      for (final p in teamB.startingPlayers) PlayerComponent(player: p),
    ]);

    world.addAll(players);
  }

  void _positionTeams() {
    final teamAplayers = players.where((p) => p.player.teamId == teamA.id).toList();
    final teamBplayers = players.where((p) => p.player.teamId == teamB.id).toList();

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
    elapsedTime += dt;

    _checkGoals();
    _clampComponentsToField();
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
    final teamAplayers = players.where((p) => p.player.teamId == teamA.id).toList();
    final teamBplayers = players.where((p) => p.player.teamId == teamB.id).toList();

    if (isTeamOnLeftSide(teamA.id)) {
      _positionTeam(teamAplayers, 100); // Team A слева
      _positionTeam(teamBplayers, size.x - 100); // Team B справа
    } else {
      _positionTeam(teamBplayers, 100); // Team B слева
      _positionTeam(teamAplayers, size.x - 100); // Team A справа
    }
  }

  void _assignNewBallOwner(String scoringTeamId) {
    final opposingTeamPlayers = players.where((p) => p.player.teamId != scoringTeamId).toList();
    final newOwner = opposingTeamPlayers[random.nextInt(opposingTeamPlayers.length)];
    ball.takeOwnership(newOwner);

    final directionToCenter = (size / 2 - newOwner.position).normalized();
    ball.position = newOwner.position + directionToCenter * (newOwner.radius + ball.radius + 1);
  }
}
