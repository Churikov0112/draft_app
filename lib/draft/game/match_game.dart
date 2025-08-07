import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'components/ball_component.dart';
import 'components/goal_component.dart';
import 'components/player_component.dart';

class MatchGame extends FlameGame {
  late BallComponent ball;
  late GoalComponent leftGoal;
  late GoalComponent rightGoal;

  final List<PlayerComponent> players = [];
  double elapsedTime = 0;

  Vector2 getGoalPositionForTeam(int team) {
    return team == 0 ? rightGoal.position : leftGoal.position;
  }

  @override
  Future<void> onLoad() async {
    // Поле (фон)
    add(RectangleComponent(size: size, paint: Paint()..color = const Color(0xFF1E8B3A)));

    // Ворота
    leftGoal = GoalComponent(team: 0, position: Vector2(0, size.y / 2 - 30));
    rightGoal = GoalComponent(team: 1, position: Vector2(size.x - 10, size.y / 2 - 30));
    add(leftGoal);
    add(rightGoal);

    // Мяч
    ball = BallComponent(position: size / 2);
    add(ball);

    _createPlayers();

    // // Игроки команды 0 (слева)
    // final playerA1 = PlayerComponent(number: 7, team: 0, position: Vector2(100, size.y / 2 - 50));
    // final playerA2 = PlayerComponent(number: 8, team: 0, position: Vector2(100, size.y / 2 + 50));

    // // Игроки команды 1 (справа)
    // final playerB1 = PlayerComponent(number: 9, team: 1, position: Vector2(size.x - 100, size.y / 2 - 50));
    // final playerB2 = PlayerComponent(number: 10, team: 1, position: Vector2(size.x - 100, size.y / 2 + 50));

    // Добавляем игроков и связываем с мячом
    for (final p in players) {
      p.assignBallRef(ball);
    }

    ball.assignPlayers(players);

    // Случайный выбор владельца мяча
    final firstOwner = players.first;
    ball.takeOwnership(firstOwner);

    // Поставить мяч чуть перед игроком
    final directionToCenter = (size / 2 - firstOwner.position).normalized();
    ball.position = firstOwner.position + directionToCenter * (firstOwner.radius + ball.radius + 1);
    ball.velocity = Vector2.zero();
  }

  void _createPlayers() {
    players.clear();

    // Команда 0
    for (int i = 0; i < 6; i++) {
      final role = (i < 2)
          ? PlayerRole.defender
          : (i < 4)
          ? PlayerRole.midfielder
          : PlayerRole.forward;
      final player = PlayerComponent(number: i + 1, team: 0, role: role);
      add(player);
      players.add(player);
    }

    // Команда 1
    for (int i = 0; i < 6; i++) {
      final role = (i < 2)
          ? PlayerRole.defender
          : (i < 4)
          ? PlayerRole.midfielder
          : PlayerRole.forward;
      final player = PlayerComponent(number: i + 7, team: 1, role: role);
      add(player);
      players.add(player);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    elapsedTime += dt;

    if (leftGoal.isGoal(ball.position)) {
      print('⚽️ GOAL for Team 1!');
      resetAfterGoal(scoringTeam: 1);
    } else if (rightGoal.isGoal(ball.position)) {
      print('⚽️ GOAL for Team 0!');
      resetAfterGoal(scoringTeam: 0);
    }

    // Ограничение всех компонентов в пределах поля
    for (final c in children) {
      if (c is PositionComponent) {
        c.position.x = c.position.x.clamp(0.0, size.x);
        c.position.y = c.position.y.clamp(0.0, size.y);
      }
    }
  }

  void resetAfterGoal({required int scoringTeam}) {
    ball.position = size / 2;
    ball.velocity = Vector2.zero();
    ball.owner = null;

    final spacingY = 80.0;

    // Переразмещаем игроков
    final team0 = players.where((p) => p.team == 0).toList();
    final team1 = players.where((p) => p.team == 1).toList();

    for (int i = 0; i < team0.length; i++) {
      team0[i].position = Vector2(100, size.y / 2 + (i - 0.5) * spacingY);
    }
    for (int i = 0; i < team1.length; i++) {
      team1[i].position = Vector2(size.x - 100, size.y / 2 + (i - 0.5) * spacingY);
    }

    // Новый случайный владелец из команды, которая не забила
    final opposingTeamPlayers = players.where((p) => p.team != scoringTeam).toList();
    final newOwner = opposingTeamPlayers[Random().nextInt(opposingTeamPlayers.length)];
    ball.takeOwnership(newOwner);

    final directionToCenter = (size / 2 - newOwner.position).normalized();
    ball.position = newOwner.position + directionToCenter * (newOwner.radius + ball.radius + 1);
  }
}
