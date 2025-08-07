import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';

enum PlayerRole { forward, midfielder, defender }

class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  final int number;
  final int team;
  double radius = 14.0;
  double maxSpeed = 100.0;
  Vector2 velocity = Vector2.zero();
  BallComponent? ball;
  final PlayerRole role;

  double _lastStealTime = 0;
  static const double stealCooldown = 1.0;

  double _lastPassTime = 0;
  static const double passCooldown = 2.0;

  PlayerComponent({required this.number, required this.team, required this.role, Vector2? position})
    : super(position: position ?? Vector2.zero(), size: Vector2.all(28));

  void assignBallRef(BallComponent b) => ball = b;

  @override
  void update(double dt) {
    super.update(dt);
    if (ball == null) return;

    // _applySeparation(dt);
    final dirToBall = ball!.position - position;
    final distToBall = dirToBall.length;
    final hasBall = ball!.owner == this;
    final time = gameRef.elapsedTime;

    if (hasBall) {
      _handleBallPossession(time: time, dt: dt);
    } else {
      _handleBallChasing(time: time, distToBall: distToBall, dirToBall: dirToBall, dt: dt);
    }

    _clampPosition();
  }

  void _handleBallPossession({required double time, required double dt}) {
    // Пытаемся сделать пас
    final canPass = (time - _lastPassTime) > passCooldown;
    if (canPass) {
      final teammate = _findOpenTeammate();
      if (teammate != null) {
        final target = teammate.position + (teammate.velocity * 0.3);
        ball!.kickTowards(target, 500, time, this);
        print("player $number passed ${teammate.number}");
        _lastPassTime = time;

        // Убрали return, чтобы игрок продолжал двигаться!
      }
    }

    // Движение к воротам
    final goal = (team == 0) ? gameRef.rightGoal : gameRef.leftGoal;
    final goalPos = goal.position;
    final angleNoise = (Random().nextDouble() - 0.5) * 0.3;
    final dir = (goalPos - position).normalized().rotated(angleNoise);

    velocity = dir * maxSpeed * 0.9;
    position += velocity * dt;

    // Удар по воротам при приближении
    if ((goalPos - position).length < 200) {
      ball!.kickTowards(goalPos, 1000, time, this);
      print("player $number kicks target");
    } else {
      // Удерживаем мяч рядом
      ball!.position = position + dir * (radius + ball!.radius + 1);
      // ball!.velocity = Vector2.zero();
    }
  }

  void _handleBallChasing({
    required double time,
    required double distToBall,
    required Vector2 dirToBall,
    required double dt,
  }) {
    final isBallFree = ball!.owner == null;
    final isOpponentOwner = ball!.owner != null && ball!.owner!.team != team;

    final allPlayers = gameRef.players;
    final sameTeam = allPlayers.where((p) => p.team == team).toList();

    // Определяем ближайшего к мячу игрока нашей команды
    final sortedByDist = sameTeam.toList()
      ..sort((a, b) => (a.position - ball!.position).length.compareTo((b.position - ball!.position).length));

    final isDesignatedPresser = identical(this, sortedByDist.first);

    if (isBallFree || isOpponentOwner) {
      // Только один игрок активно атакует
      if (isDesignatedPresser) {
        final moveDir = dirToBall.normalized();
        velocity = moveDir * maxSpeed;
        position += velocity * dt;

        // Пытаемся отобрать мяч
        if (distToBall < radius + ball!.radius + 2 && (time - _lastStealTime) > stealCooldown) {
          ball!.takeOwnership(this);
          _lastStealTime = time;
        }
      } else {
        // Остальные остаются рядом, но не сближаются
        final desiredPos = getHomePosition();
        final toHome = desiredPos - position;
        final dist = toHome.length;
        if (dist > 4) {
          final moveDir = toHome.normalized();
          velocity = moveDir * maxSpeed * 0.4;
          position += velocity * dt;
        } else {
          velocity = Vector2.zero();
        }
      }
    } else {
      // Наша команда с мячом — возвращаемся в зону
      final home = getHomePosition();
      final toHome = home - position;
      if (toHome.length > 5) {
        final moveDir = toHome.normalized();
        velocity = moveDir * maxSpeed * 0.5;
        position += velocity * dt;
      } else {
        velocity = Vector2.zero();
      }
    }
  }

  PlayerComponent? _findOpenTeammate() {
    final teammates = gameRef.players.where((p) => p.team == team && p != this);
    PlayerComponent? best;
    double bestScore = -1;

    for (final t in teammates) {
      final toTeammate = t.position - position;
      final dist = toTeammate.length;

      // Учитываем:
      // 1. Дистанцию (предпочитаем среднюю дистанцию)
      // 2. Угол относительно направления к воротам
      // 3. Свободное пространство вокруг

      final goalDir = (team == 0 ? gameRef.rightGoal.position : gameRef.leftGoal.position) - position;

      final angle = goalDir.angleTo(toTeammate).abs();

      // Чем больше угол (до 90 градусов) и оптимальнее дистанция, тем лучше
      final distScore = 1 - (dist - 150).abs() / 150; // Оптимально 150 пикселей
      final angleScore = 1 - angle / (pi / 2);

      final totalScore = distScore * 0.6 + angleScore * 0.4;

      if (dist > 80 && dist < 350 && totalScore > bestScore) {
        bestScore = totalScore;
        best = t;
      }
    }
    return best;
  }

  void _clampPosition() {
    position.x = position.x.clamp(radius, gameRef.size.x - radius);
    position.y = position.y.clamp(radius, gameRef.size.y - radius);
  }

  // void _applySeparation(double dt) {
  //   const double minSeparation = 28.0;

  //   for (final c in gameRef.players) {
  //     if (c == this) continue;
  //     final diff = position - c.position;
  //     final dist = diff.length;
  //     if (dist < 1e-6) {
  //       position += Vector2((Random().nextDouble() - 0.5) * 4, (Random().nextDouble() - 0.5) * 4);
  //       continue;
  //     }
  //     if (dist < minSeparation) {
  //       final overlap = minSeparation - dist;
  //       final correction = diff.normalized() * (overlap * 0.5);
  //       position += correction;
  //       c.position -= correction;
  //     }
  //   }
  // }

  Vector2 getHomePosition() {
    final fieldSize = gameRef.size;

    double xZone;
    switch (role) {
      case PlayerRole.defender:
        xZone = (team == 0) ? fieldSize.x * 0.2 : fieldSize.x * 0.8;
        break;
      case PlayerRole.midfielder:
        xZone = (team == 0) ? fieldSize.x * 0.4 : fieldSize.x * 0.6;
        break;
      case PlayerRole.forward:
        xZone = (team == 0) ? fieldSize.x * 0.65 : fieldSize.x * 0.35;
        break;
    }

    // Разброс по вертикали (по номеру)
    final spacing = fieldSize.y / 6;
    final y = spacing * (number % 6 + 0.5);

    return Vector2(xZone, y);
  }

  @override
  void render(Canvas canvas) {
    // Тень
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(Offset(2, 3), radius * 0.95, shadowPaint);

    // Тело игрока
    final outlinePaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset.zero, radius + 2.0, outlinePaint);

    final fillPaint = Paint()..color = (team == 0 ? Colors.blue : Colors.yellow);
    canvas.drawCircle(Offset.zero, radius, fillPaint);

    // Номер
    final textPainter = TextPainter(
      text: TextSpan(
        text: number.toString(),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -radius - textPainter.height - 4));
  }
}

extension Vector2Rotation on Vector2 {
  Vector2 rotated(double angle) {
    final cosA = cos(angle);
    final sinA = sin(angle);
    return Vector2(x * cosA - y * sinA, x * sinA + y * cosA);
  }
}
