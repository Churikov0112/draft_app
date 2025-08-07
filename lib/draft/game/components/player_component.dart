import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';

class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  final int number;
  final int team;
  double radius = 14.0;
  double maxSpeed = 100.0;
  Vector2 velocity = Vector2.zero();
  BallComponent? ball;

  double _lastStealTime = 0;
  static const double stealCooldown = 1.0;

  double _lastPassTime = 0;
  static const double passCooldown = 1.5;

  PlayerComponent({required this.number, required this.team, Vector2? position})
    : super(position: position ?? Vector2.zero(), size: Vector2.all(28));

  void assignBallRef(BallComponent b) => ball = b;

  @override
  void update(double dt) {
    super.update(dt);
    if (ball == null) return;

    _applySeparation(dt);

    final dirToBall = ball!.position - position;
    final distToBall = dirToBall.length;

    final hasBall = ball!.owner == this;
    final time = gameRef.elapsedTime;

    if (hasBall) {
      // === Пытаемся найти открытого тиммейта для паса ===
      final canPass = (time - _lastPassTime) > passCooldown;
      if (canPass) {
        final teammate = _findOpenTeammate();
        if (teammate != null) {
          final target = teammate.position + (teammate.velocity * 0.3); // на ход
          ball!.kickTowards(target, 120, time, this);
          _lastPassTime = time;
          return;
        }
      }

      // === Ведем мяч к чужим воротам (с лёгким шумом) ===
      final goal = (team == 0) ? gameRef.rightGoal : gameRef.leftGoal;
      final goalPos = goal.position;

      // Добавим немного случайности
      final angleNoise = (Random().nextDouble() - 0.5) * 0.3;
      final dir = rotated(angleNoise: angleNoise, goalPos: goalPos, position: position);
      // final dir =  (goalPos - position).normalized().rotated(angleNoise);
      velocity = dir * maxSpeed * 0.9;
      position += velocity * dt;

      // Если близко к воротам — удар
      if ((goalPos - position).length < 60) {
        ball!.kickTowards(goalPos, 1000, time, this);
      } else {
        // Держим мяч рядом
        ball!.position = position + dir * (radius + ball!.radius + 1);
        ball!.velocity = Vector2.zero();
      }
    } else {
      // === Боремся за мяч или пытаемся отобрать ===
      if (ball!.owner == null || (ball!.owner?.team != team)) {
        // Если рядом и можно отобрать
        if (distToBall < radius + ball!.radius + 2) {
          if ((time - _lastStealTime) > stealCooldown) {
            ball!.takeOwnership(this);
            _lastStealTime = time;
          }
        } else {
          // Двигаемся к мячу
          final moveDir = dirToBall.normalized();
          velocity = moveDir * maxSpeed;
          position += velocity * dt;
        }
      } else {
        // Мяч у тиммейта — открываемся
        final teammate = ball!.owner!;
        final offset = Vector2((Random().nextDouble() - 0.5) * 100, (Random().nextDouble() - 0.5) * 100);
        final target = teammate.position + offset;
        final moveDir = (target - position).normalized();
        velocity = moveDir * maxSpeed * 0.8;
        position += velocity * dt;
      }
    }

    // Ограничение позиции
    position.x = position.x.clamp(radius, gameRef.size.x - radius);
    position.y = position.y.clamp(radius, gameRef.size.y - radius);
  }

  PlayerComponent? _findOpenTeammate() {
    final teammates = gameRef.players.where((p) => p.team == team && p != this);
    PlayerComponent? best;
    double maxDistance = 0;

    for (final t in teammates) {
      final d = (t.position - position).length;
      if (d > 60 && d < 300 && d > maxDistance) {
        maxDistance = d;
        best = t;
      }
    }
    return best;
  }

  void _applySeparation(double dt) {
    const double minSeparation = 28.0;

    for (final c in gameRef.players) {
      if (c == this) continue;
      final diff = position - c.position;
      final dist = diff.length;
      if (dist < 1e-6) {
        position += Vector2((Random().nextDouble() - 0.5) * 4, (Random().nextDouble() - 0.5) * 4);
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
        text: number.toString(),
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

Vector2 rotated({required double angleNoise, required Vector2 goalPos, required NotifyingVector2 position}) {
  final angle = angleNoise;
  final cosA = cos(angle);
  final sinA = sin(angle);

  final dir = (goalPos - position).normalized();
  final rotated = Vector2(dir.x * cosA - dir.y * sinA, dir.x * sinA + dir.y * cosA);
  return rotated;
}
