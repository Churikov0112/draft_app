import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'components/ball_component.dart';
import 'components/goal_component.dart';
import 'components/player_component.dart';

class MatchGame extends FlameGame {
  late BallComponent ball;
  late GoalComponent leftGoal;
  late GoalComponent rightGoal;

  final Random random = Random();
  int team0score = 0;
  int team1score = 0;
  final List<PlayerComponent> players = [];

  double elapsedTime = 0;

  Vector2 getGoalPositionForTeam(int team) => team == 0 ? rightGoal.position : leftGoal.position;

  @override
  Future<void> onLoad() async {
    _setupField();
    _setupGoals();
    _setupBall();
    _setupPlayers();
  }

  void _setupField() {
    add(RectangleComponent(size: size, paint: Paint()..color = const Color(0xFF1E8B3A)));
  }

  void _setupGoals() {
    leftGoal = GoalComponent(team: 0, position: Vector2(0, size.y / 2 - 30));
    rightGoal = GoalComponent(team: 1, position: Vector2(size.x - 10, size.y / 2 - 30));
    addAll([leftGoal, rightGoal]);
  }

  void _setupBall() {
    ball = BallComponent(position: size / 2);
    add(ball);
  }

  void _setupPlayers() {
    _createTeams();
    _positionTeams();
    _linkPlayersToBall();
    _setInitialBallOwner();
  }

  void _createTeams() {
    players.addAll([
      // Team 0
      PlayerComponent(
        team: 0,
        number: 2,
        role: PlayerRole.defender,
        stats: PlayerStats(maxSpeed: 60, lowPass: 70, shoots: 60, defence: 90),
      ),
      PlayerComponent(
        team: 0,
        number: 4,
        role: PlayerRole.defender,
        stats: PlayerStats(maxSpeed: 65, lowPass: 65, shoots: 70, defence: 77),
      ),
      PlayerComponent(
        team: 0,
        number: 6,
        role: PlayerRole.midfielder,
        stats: PlayerStats(maxSpeed: 80, lowPass: 85, shoots: 75, defence: 75),
      ),
      PlayerComponent(
        team: 0,
        number: 8,
        role: PlayerRole.midfielder,
        stats: PlayerStats(maxSpeed: 80, lowPass: 90, shoots: 85, defence: 60),
      ),
      PlayerComponent(
        team: 0,
        number: 9,
        role: PlayerRole.forward,
        stats: PlayerStats(maxSpeed: 92, lowPass: 70, shoots: 95, defence: 50),
      ),
      PlayerComponent(
        team: 0,
        number: 11,
        role: PlayerRole.forward,
        stats: PlayerStats(maxSpeed: 100, lowPass: 100, shoots: 100, defence: 100),
      ),
      // ! -----------------------------------------------------------------
      PlayerComponent(
        team: 1,
        number: 2,
        role: PlayerRole.defender,
        stats: PlayerStats(maxSpeed: 60, lowPass: 65, shoots: 60, defence: 90),
      ),
      PlayerComponent(
        team: 1,
        number: 4,
        role: PlayerRole.defender,
        stats: PlayerStats(maxSpeed: 65, lowPass: 65, shoots: 65, defence: 80),
      ),
      PlayerComponent(
        team: 1,
        number: 6,
        role: PlayerRole.midfielder,
        stats: PlayerStats(maxSpeed: 75, lowPass: 85, shoots: 80, defence: 70),
      ),
      PlayerComponent(
        team: 1,
        number: 8,
        role: PlayerRole.midfielder,
        stats: PlayerStats(maxSpeed: 80, lowPass: 90, shoots: 90, defence: 60),
      ),
      PlayerComponent(
        team: 1,
        number: 9,
        role: PlayerRole.forward,
        stats: PlayerStats(maxSpeed: 88, lowPass: 70, shoots: 95, defence: 50),
      ),
      PlayerComponent(
        team: 1,
        number: 11,
        role: PlayerRole.forward,
        stats: PlayerStats(maxSpeed: 98, lowPass: 65, shoots: 80, defence: 58),
      ),
    ]);

    addAll(players);
  }

  void _positionTeams() {
    final team0 = players.where((p) => p.team == 0).toList();
    final team1 = players.where((p) => p.team == 1).toList();

    _positionTeam(team0, 100);
    _positionTeam(team1, size.x - 100);
  }

  void _positionTeam(List<PlayerComponent> team, double xPos) {
    const spacingY = 80.0;
    for (int i = 0; i < team.length; i++) {
      team[i].position = Vector2(xPos, size.y / 2 + (i - 0.5) * spacingY);
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
    if (leftGoal.isGoal(ball.position)) {
      _handleGoal(1);
    } else if (rightGoal.isGoal(ball.position)) {
      _handleGoal(0);
    }
  }

  void _handleGoal(int scoringTeam) {
    print('⚽️ GOAL for Team $scoringTeam!');
    if (scoringTeam == 1) {
      team1score++;
    } else {
      team0score++;
    }
    resetAfterGoal(scoringTeam: scoringTeam);
  }

  void _clampComponentsToField() {
    for (final c in children.whereType<PositionComponent>()) {
      c.position.x = c.position.x.clamp(0.0, size.x);
      c.position.y = c.position.y.clamp(0.0, size.y);
    }
  }

  void resetAfterGoal({required int scoringTeam}) {
    _resetPlayersPositions();
    _assignNewBallOwner(scoringTeam);
  }

  void _resetPlayersPositions() {
    final team0 = players.where((p) => p.team == 0).toList();
    final team1 = players.where((p) => p.team == 1).toList();

    _positionTeam(team0, 100);
    _positionTeam(team1, size.x - 100);
  }

  void _assignNewBallOwner(int scoringTeam) {
    final opposingTeamPlayers = players.where((p) => p.team != scoringTeam).toList();
    final newOwner = opposingTeamPlayers[random.nextInt(opposingTeamPlayers.length)];
    ball.takeOwnership(newOwner);

    final directionToCenter = (size / 2 - newOwner.position).normalized();
    ball.position = newOwner.position + directionToCenter * (newOwner.radius + ball.radius + 1);
  }
}
