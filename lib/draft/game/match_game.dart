import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'components/ball_component.dart';
import 'components/goal_component.dart';
import 'components/player_component.dart';

class MatchGame extends FlameGame {
  late PlayerComponent playerA;
  late PlayerComponent playerB;
  late BallComponent ball;
  late GoalComponent leftGoal;
  late GoalComponent rightGoal;

  double elapsedTime = 0;

  @override
  void update(double dt) {
    super.update(dt);
    elapsedTime += dt;

    if (leftGoal.isGoal(ball.position)) {
      print('GOAL for Team 1! 🎯');
      resetAfterGoal();
    } else if (rightGoal.isGoal(ball.position)) {
      print('GOAL for Team 0! 🎯');
      resetAfterGoal();
    }

    // Ограничение позиции
    for (final c in children) {
      if (c is PositionComponent) {
        final minX = 0.0;
        final minY = 0.0;
        final maxX = size.x;
        final maxY = size.y;
        c.position.x = c.position.x.clamp(minX, maxX);
        c.position.y = c.position.y.clamp(minY, maxY);
      }
    }
  }

  void resetAfterGoal() {
    ball.position = size / 2;
    ball.velocity = Vector2.zero();
    playerA.position = Vector2(100, size.y / 2);
    playerB.position = Vector2(size.x - 100, size.y / 2);
    ball.owner = null;
  }

  @override
  Future<void> onLoad() async {
    add(RectangleComponent(size: Vector2(size.x, size.y), paint: Paint()..color = const Color(0xFF1E8B3A)));

    ball = BallComponent(position: Vector2(size.x / 2, size.y / 2));
    add(ball);

    playerA = PlayerComponent(id: 7, team: 0, position: Vector2(100, size.y / 2));
    playerB = PlayerComponent(id: 9, team: 1, position: Vector2(size.x - 100, size.y / 2));
    add(playerA);
    add(playerB);

    playerA.assignBallRef(ball);
    playerB.assignBallRef(ball);
    ball.assignPlayers(playerA, playerB);

    // Ворота
    leftGoal = GoalComponent(team: 0, position: Vector2(0, size.y / 2 - 30));
    rightGoal = GoalComponent(team: 1, position: Vector2(size.x - 10, size.y / 2 - 30));
    add(leftGoal);
    add(rightGoal);

    // ball.assignPlayers(playerA, playerB);
    ball.assignPlayers(playerA, playerB);

    // Случайный выбор владельца мяча
    final firstOwner = (Random().nextBool()) ? playerA : playerB;
    ball.takeOwnership(firstOwner);

    // Разместим мяч чуть перед ним (по направлению к центру)
    final directionToCenter = (size / 2 - firstOwner.position).normalized();
    ball.position = firstOwner.position + directionToCenter * (firstOwner.radius + ball.radius + 1);
    ball.velocity = Vector2.zero();
  }
}
