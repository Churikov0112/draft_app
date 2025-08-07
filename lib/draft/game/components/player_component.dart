import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';

class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  final int team;
  final int number;
  final double radius = 12;
  final double maxSpeed = 80;

  Vector2 velocity = Vector2.zero();
  BallComponent? ball;

  PlayerComponent({required this.team, required this.number, required Vector2 position})
    : super(position: position, size: Vector2.all(24), anchor: Anchor.center);

  void assignBallRef(BallComponent ballRef) {
    ball = ballRef;
  }

  List<PlayerComponent> get teammates => gameRef.players.where((p) => p != this && p.team == team).toList();

  List<PlayerComponent> get opponents => gameRef.players.where((p) => p.team != team).toList();

  @override
  void update(double dt) {
    super.update(dt);
    if (ball == null) return;

    final teammates = gameRef.players.where((p) => p.team == team && p != this).toList();
    final opponents = gameRef.players.where((p) => p.team != team).toList();

    final isOwner = ball!.owner == this;
    final isBallOwned = ball!.owner != null;

    _applySeparation(dt);

    if (isOwner) {
      // Дриблинг или пас
      final openMate = teammates.firstWhereOrNull((p) {
        final toMate = p.position - position;
        final dist = toMate.length;
        final noOpponentClose = opponents.every((o) => (o.position - p.position).length > 100);
        return dist < 300 && noOpponentClose;
      });

      if (openMate != null) {
        // Пасуем открытому
        ball!.kickTowards(openMate.position, 120, gameRef.elapsedTime, this);
        return;
      } else {
        // Дриблинг — уходим вбок или вперёд
        final dir = ((gameRef.getGoalPositionForTeam(team) - position)..rotate(pi / 12 * (Random().nextDouble() - 0.5)))
            .normalized();
        velocity = dir * maxSpeed * 0.8;
        position += velocity * dt;

        // Ведение мяча
        ball!.position = position + dir * (radius + ball!.radius + 1);
        ball!.velocity = Vector2.zero();
      }
    } else if (ball!.owner != null && ball!.owner!.team == team) {
      // Тиммейт с мячом → открываемся
      final offset = Vector2(80 + Random().nextDouble() * 40, 50 - Random().nextDouble() * 100);
      if (team == 1) offset.x *= -1;
      final target = ball!.owner!.position + offset;
      final dir = (target - position);
      if (dir.length > 10) {
        velocity = dir.normalized() * maxSpeed * 0.6;
        position += velocity * dt;
      }
    } else if (ball!.owner != null && ball!.owner!.team != team) {
      // Соперник с мячом → идём в отбор
      final dir = (ball!.position - position);
      if (dir.length > radius + ball!.radius) {
        velocity = dir.normalized() * maxSpeed;
        position += velocity * dt;
      } else {
        // попытка отобрать
        if (ball!.canBeKickedBy(this, gameRef.elapsedTime)) {
          ball!.takeOwnership(this);
        }
      }
    } else {
      // Мяч свободен
      final dir = (ball!.position - position);
      if (dir.length > radius + ball!.radius) {
        velocity = dir.normalized() * maxSpeed;
        position += velocity * dt;
      } else {
        ball!.takeOwnership(this);
      }
    }

    // Границы поля
    position.x = position.x.clamp(radius, gameRef.size.x - radius);
    position.y = position.y.clamp(radius, gameRef.size.y - radius);
  }

  void _applySeparation(double dt) {
    const separationDistance = 30.0;
    const separationForce = 100.0;

    for (final other in gameRef.players) {
      if (other == this) continue;

      final toOther = other.position - position;
      final distance = toOther.length;
      if (distance < separationDistance && distance > 0) {
        final pushDir = -toOther.normalized();
        position += pushDir * (separationForce * dt) / distance;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final bodyPaint = Paint()..color = team == 0 ? Colors.red : Colors.white;
    canvas.drawCircle(Offset.zero, radius, bodyPaint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: '$number',
        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
  }
}
