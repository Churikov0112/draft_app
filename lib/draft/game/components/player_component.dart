import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';

class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  final int id;
  final int team;
  double radius = 14.0;
  double maxSpeed = 60.0;
  Vector2 velocity = Vector2.zero();
  BallComponent? ball;

  Vector2? dribbleTarget;
  double nextDribbleTargetTime = 0;

  PlayerComponent({required this.id, required this.team, Vector2? position})
    : super(position: position ?? Vector2.zero(), size: Vector2.all(28));

  void assignBallRef(BallComponent b) => ball = b;

  double distanceToBall() {
    if (ball == null) return double.infinity;
    return (ball!.position - position).length;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (ball == null) return;

    _applySeparation(dt);

    final opponent = (ball!.owner != null && ball!.owner != this) ? ball!.owner : null;

    if (ball!.owner == this) {
      // === ДРИБЛИНГ ===

      final goalX = (team == 0) ? gameRef.rightGoal.position.x : gameRef.leftGoal.position.x;
      final goalY = gameRef.size.y / 2;
      final goal = Vector2(goalX, goalY);

      // Обновляем дрибблинг-цель каждые 1.5 сек или если дошли до неё
      if (dribbleTarget == null ||
          (position - dribbleTarget!).length < 20 ||
          gameRef.elapsedTime > nextDribbleTargetTime) {
        final offsetX = (Random().nextDouble() - 0.5) * 100;
        final offsetY = (Random().nextDouble() - 0.5) * 100;
        dribbleTarget = goal + Vector2(offsetX, offsetY);
        nextDribbleTargetTime = gameRef.elapsedTime + 1.5;
      }

      final moveDir = (dribbleTarget! - position).normalized();
      velocity = moveDir * maxSpeed * 0.8;
      position += velocity * dt;

      // Держим мяч у ноги
      ball!.position = position + moveDir * (radius + ball!.radius + 1);
      ball!.velocity = Vector2.zero();

      // Удар по воротам, если близко
      if ((goal - position).length < 50 && ball!.canBeKickedBy(this, gameRef.elapsedTime)) {
        ball!.kickTowards(goal, 120, gameRef.elapsedTime, this);
      }
    } else if (opponent != null) {
      // === ПРЕССИНГ И ПОПЫТКА ОТБОРА ===

      final toOpponent = opponent.position - position;

      // Попытка отбора мяча
      if ((position - ball!.position).length < radius * 1.6 &&
          ball!.owner == opponent &&
          ball!.canBeKickedBy(this, gameRef.elapsedTime)) {
        ball!.takeOwnership(this);
        ball!.lastKickTime = gameRef.elapsedTime;
        dribbleTarget = null;
      } else {
        // Двигаемся к противнику с небольшим смещением, чтобы не врезаться лоб в лоб
        final dodgeOffset = Vector2(-toOpponent.y, toOpponent.x).normalized() * 5.0;
        final pressTarget = opponent.position + dodgeOffset;
        velocity = (pressTarget - position).normalized() * maxSpeed;
        position += velocity * dt;
      }
    } else {
      // === БЕЖИМ К СВОБОДНОМУ МЯЧУ ===

      final dir = (ball!.position - position);
      if (dir.length > radius + ball!.radius) {
        velocity = dir.normalized() * maxSpeed;
        position += velocity * dt;
      } else {
        // Берём мяч под контроль
        ball!.takeOwnership(this);
        dribbleTarget = null;
      }
    }

    // Ограничиваем по полю
    position.x = position.x.clamp(radius, gameRef.size.x - radius);
    position.y = position.y.clamp(radius, gameRef.size.y - radius);
  }

  /// Раздвигает близко стоящих игроков, чтобы они не "сливались".
  void _applySeparation(double dt) {
    final parent = this.parent;
    if (parent == null) return;

    // минимальное расстояние между центрами (немного больше суммы радиусов)
    final double minSeparation = radius * 2.1;

    for (final c in parent.children) {
      if (c is PlayerComponent && c != this) {
        final other = c;
        final diff = position - other.position;
        final dist = diff.length;
        if (dist < 1e-6) {
          // если совсем совпали (на случай инициализации), немного рандомно сдвинуть
          final jitter = Vector2((Random().nextDouble() - 0.5) * 8, (Random().nextDouble() - 0.5) * 8);
          position += jitter;
          other.position -= jitter;
          continue;
        }
        if (dist < minSeparation) {
          // сколько нужно сдвинуть, чтобы достичь minSeparation
          final overlap = minSeparation - dist;
          // сдвигаем половину на каждую сторону (чтобы не "толкать" только одного)
          final correction = diff.normalized() * (overlap * 0.5 + 0.1);
          // APPLY: сдвигаем плавно (чтобы не телепортировать)
          // коэффициент можно подбирать: здесь небольшая плавность
          final smoothFactor = 1.0; // 1.0 — мгновенно, <1 — плавнее
          position += correction * smoothFactor;
          other.position -= correction * smoothFactor;
        }
      }
    }
  }

  @override
  void render(Canvas canvas) {
    // рисуем тень
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(Offset(2, 3), radius * 0.95, shadowPaint);

    // рисуем обводку (чёрный контур), затем заливку — чтобы было видно при перекрытии
    final outlinePaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset.zero, radius + 2.0, outlinePaint);

    final fillPaint = Paint()..color = (team == 0 ? Colors.blue : Colors.yellow);
    canvas.drawCircle(Offset.zero, radius, fillPaint);

    // номер — рисуем чуть выше центра и с белым фоном для читаемости
    final tp = TextPainter(
      text: TextSpan(
        text: id.toString(),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();

    // фон для номера (полупрозрачная чёрная полоска)
    final rectW = tp.width + 8;
    final rectH = tp.height + 4;
    final rectOffset = Offset(-rectW / 2, -radius - rectH - 2);
    final rectPaint = Paint()..color = Colors.black.withOpacity(0.6);
    final r = Rect.fromLTWH(rectOffset.dx, rectOffset.dy, rectW, rectH);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4.0)), rectPaint);

    tp.paint(canvas, Offset(-tp.width / 2, -radius - tp.height - 4));
  }
}
