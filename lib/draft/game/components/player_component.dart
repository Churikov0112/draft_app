import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';

class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  final int id;
  final int team; // 0 или 1
  double radius = 14.0;
  double maxSpeed = 60.0;
  Vector2 velocity = Vector2.zero();
  BallComponent? ball;

  Vector2? targetPosition;
  double nextTargetUpdateTime = 0;

  PlayerComponent({required this.id, required this.team, required Vector2 position})
    : super(position: position, size: Vector2.all(28));

  void assignBallRef(BallComponent b) => ball = b;

  bool get hasBall => ball?.owner == this;

  @override
  void update(double dt) {
    super.update(dt);
    if (ball == null) return;

    _applySeparation(dt);

    final teammates = gameRef.players.where((p) => p.team == team && p != this).toList();
    final opponents = gameRef.players.where((p) => p.team != team).toList();

    if (hasBall) {
      // ==== Дриблинг ====

      // Периодически меняем цель дриблинга
      if (targetPosition == null ||
          (position - targetPosition!).length < 20 ||
          gameRef.elapsedTime > nextTargetUpdateTime) {
        final goalX = team == 0 ? gameRef.rightGoal.position.x : gameRef.leftGoal.position.x;
        final goalY = gameRef.size.y / 2;
        final offset = Vector2((Random().nextDouble() - 0.5) * 100, (Random().nextDouble() - 0.5) * 100);
        targetPosition = Vector2(goalX, goalY) + offset;
        nextTargetUpdateTime = gameRef.elapsedTime + 1.5;
      }

      // ПАС союзнику, если он свободен
      for (final mate in teammates) {
        if ((mate.position - position).length < 120 && (mate.position - position).angleTo(Vector2(1, 0)) < pi / 3) {
          final defendersNear = opponents.where((o) => (o.position - mate.position).length < 40);
          if (defendersNear.isEmpty) {
            ball!.kickTowards(mate.position, 120, gameRef.elapsedTime, this);
            return;
          }
        }
      }

      // Движение к цели
      final dir = (targetPosition! - position).normalized();
      velocity = dir * maxSpeed * 0.8;
      position += velocity * dt;

      // Мяч у ноги
      ball!.position = position + dir * (radius + ball!.radius + 1);
      ball!.velocity = Vector2.zero();

      // Удар по воротам
      final goalCenter = Vector2(
        team == 0 ? gameRef.rightGoal.position.x : gameRef.leftGoal.position.x,
        gameRef.size.y / 2,
      );
      if ((goalCenter - position).length < 50) {
        ball!.kickTowards(goalCenter, 130, gameRef.elapsedTime, this);
      }
    } else if (ball!.owner?.team == team && ball!.owner != null) {
      // === Поддержка владения: открываемся под пас ===
      final owner = ball!.owner!;
      final offset = Vector2((Random().nextDouble() - 0.5) * 60, (Random().nextDouble() - 0.5) * 60);
      targetPosition = owner.position + offset;
      _moveToTarget(dt);
    } else if (ball!.owner?.team != team && ball!.owner != null) {
      // === Прессинг ===
      final toOpponent = ball!.owner!.position - position;
      if (toOpponent.length < radius * 1.8) {
        ball!.takeOwnership(this);
        targetPosition = null;
      } else {
        velocity = toOpponent.normalized() * maxSpeed;
        position += velocity * dt;
      }
    } else {
      // === Свободный мяч ===
      final dir = (ball!.position - position);
      if (dir.length > radius + ball!.radius) {
        velocity = dir.normalized() * maxSpeed;
        position += velocity * dt;
      } else {
        ball!.takeOwnership(this);
        targetPosition = null;
      }
    }

    // Ограничение поля
    position.x = position.x.clamp(radius, gameRef.size.x - radius);
    position.y = position.y.clamp(radius, gameRef.size.y - radius);
  }

  void _moveToTarget(double dt) {
    if (targetPosition == null) return;
    final dir = (targetPosition! - position);
    if (dir.length > 5) {
      velocity = dir.normalized() * maxSpeed * 0.7;
      position += velocity * dt;
    } else {
      velocity = Vector2.zero();
    }
  }

  void _applySeparation(double dt) {
    final parent = this.parent;
    if (parent == null) return;

    final double minSeparation = radius * 2.1;

    for (final c in parent.children) {
      if (c is PlayerComponent && c != this) {
        final diff = position - c.position;
        final dist = diff.length;
        if (dist < 1e-6) {
          final jitter = Vector2((Random().nextDouble() - 0.5) * 8, (Random().nextDouble() - 0.5) * 8);
          position += jitter;
          c.position -= jitter;
          continue;
        }
        if (dist < minSeparation) {
          final overlap = minSeparation - dist;
          final correction = diff.normalized() * (overlap * 0.5);
          position += correction;
          c.position -= correction;
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(Offset(2, 3), radius * 0.95, shadowPaint);

    final outlinePaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset.zero, radius + 2.0, outlinePaint);

    final fillPaint = Paint()..color = (team == 0 ? Colors.blue : Colors.yellow);
    canvas.drawCircle(Offset.zero, radius, fillPaint);

    final tp = TextPainter(
      text: TextSpan(
        text: id.toString(),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    final rectW = tp.width + 8;
    final rectH = tp.height + 4;
    final rectOffset = Offset(-rectW / 2, -radius - rectH - 2);
    final rectPaint = Paint()..color = Colors.black.withOpacity(0.6);
    final r = Rect.fromLTWH(rectOffset.dx, rectOffset.dy, rectW, rectH);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4.0)), rectPaint);

    tp.paint(canvas, Offset(-tp.width / 2, -radius - tp.height - 4));
  }
}
