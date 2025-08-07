import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';

enum PlayerRole { forward, midfielder, defender }

class PlayerStats {
  /// 0 - 100
  final double maxSpeed;

  /// 0 - 100
  final double lowPass;

  /// 0 - 100
  final double shoots;

  /// 0 - 100
  final double defence;

  PlayerStats({required this.maxSpeed, required this.lowPass, required this.shoots, required this.defence});
}

class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  final int number;
  final int team;
  double radius = 14.0;

  Vector2 velocity = Vector2.zero();
  BallComponent? ball;
  final PlayerRole role;
  final PlayerStats stats;

  double _lastStealTime = 0;
  static const double stealCooldown = 1.0;

  double _lastPassTime = 0;
  static const double passCooldown = 2.0;

  PlayerComponent({
    required this.team,
    required this.number,
    required this.role,
    required this.stats,
    Vector2? position,
  }) : super(position: position ?? Vector2.zero(), size: Vector2.all(28));

  void assignBallRef(BallComponent b) => ball = b;

  @override
  void update(double dt) {
    super.update(dt);
    if (ball == null) return;

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
    final goal = (team == 0) ? gameRef.rightGoal : gameRef.leftGoal;
    final goalPos = goal.position;
    final dirToGoal = (goalPos - position).normalized();
    final distToGoal = (goalPos - position).length;

    final enemies = gameRef.players.where((p) => p.team != team);
    final threatDetected = enemies.any((enemy) {
      final toEnemy = enemy.position - position;
      final projection = toEnemy.dot(dirToGoal);
      final perpendicularDist = (toEnemy - dirToGoal * projection).length;
      return projection > 0 && projection < 150 && perpendicularDist < 25;
    });

    final canPass = (time - _lastPassTime) > passCooldown;
    if (threatDetected && canPass) {
      final teammate = _findOpenTeammate();
      if (teammate != null) {
        final passSkill = stats.lowPass / 100;
        final leadFactor = 0.2 + 0.5 * passSkill;
        final target = teammate.position + (teammate.velocity * leadFactor);

        final toTeammate = teammate.position - position;
        if (_isPassSafe(position, target, tolerance: 25 + 20 * (1 - passSkill))) {
          final basePower = toTeammate.length * 3.0;
          final passPower = basePower * (0.9 + 0.2 * passSkill);
          ball!.kickTowards(target, passPower.clamp(200, 800), time, this);
          _lastPassTime = time;
          print("player $number passed to ${teammate.number}");
          return;
        }
      }
    }

    if (threatDetected) {
      final perpendicular = Vector2(-dirToGoal.y, dirToGoal.x);
      final dir = (dirToGoal + perpendicular * 0.7).normalized();
      velocity = dir * stats.maxSpeed * 0.9;
      position += velocity * dt;
      ball!.position = position + dir * (radius + ball!.radius + 1);
    } else {
      final dir = dirToGoal;
      velocity = dir * stats.maxSpeed * 0.8;
      position += velocity * dt;
      ball!.position = position + dir * (radius + ball!.radius + 1);
    }

    // 🟢 Удар в воротах — в одном месте
    if (distToGoal < 100) {
      final shootSkill = stats.shoots / 100;
      final goalHeight = 60.0;
      final verticalSpread = goalHeight * 0.5 * (1 - shootSkill);
      final dy = (gameRef.random.nextDouble() - 0.5) * 2 * verticalSpread;

      final target = goalPos + Vector2(0, dy); // только смещение по Y
      final power = 600 + 400 * shootSkill;

      ball!.kickTowards(target, power, time, this);
      print("player $number shoots at goal!");
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

    final sameTeam = gameRef.players.where((p) => p.team == team).toList();
    final sortedByDist = sameTeam
      ..sort((a, b) => (a.position - ball!.position).length.compareTo((b.position - ball!.position).length));
    final isDesignatedPresser = identical(this, sortedByDist.first);

    if (isBallFree || isOpponentOwner) {
      if (isDesignatedPresser) {
        final moveDir = dirToBall.normalized();
        velocity = moveDir * stats.maxSpeed;
        position += velocity * dt;

        // final nearBall = distToBall < radius + ball!.radius + 2;
        // final notInCooldown = (time - _lastStealTime) > stealCooldown;

        final defenceSkill = stats.defence / 100;
        final cooldown = stealCooldown * (1.0 - 0.5 * defenceSkill);
        final extendedReach = radius + ball!.radius + 2 + 10 * defenceSkill;

        final nearBall = distToBall < extendedReach;
        final notInCooldown = (time - _lastStealTime) > cooldown;

        if (nearBall && notInCooldown) {
          ball!.takeOwnership(this);
          _lastStealTime = time;
        }
      } else {
        _moveToOpenSpace(dt);
      }
    } else {
      _moveToOpenSpace(dt);
    }
  }

  void _moveToOpenSpace(double dt) {
    final closestEnemy = gameRef.players
        .where((p) => p.team != team)
        .reduce((a, b) => (a.position - position).length < (b.position - position).length ? a : b);

    final awayFromEnemy = (position - closestEnemy.position).normalized();
    final desiredPos = getHomePosition() + awayFromEnemy * 30;

    final toDesired = desiredPos - position;
    if (toDesired.length > 4) {
      velocity = toDesired.normalized() * stats.maxSpeed * 0.4;
      position += velocity * dt;
    } else {
      velocity = Vector2.zero();
    }
  }

  PlayerComponent? _findOpenTeammate() {
    final teammates = gameRef.players.where((p) => p.team == team && p != this);
    PlayerComponent? best;
    double bestScore = -1;

    final goalPos = (team == 0 ? gameRef.rightGoal.position : gameRef.leftGoal.position);
    final goalDistNow = (goalPos - position).length;

    for (final t in teammates) {
      final toTeammate = t.position - position;
      final dist = toTeammate.length;
      final goalDistThen = (goalPos - t.position).length;

      final goalDir = goalPos - position;
      final angle = goalDir.angleTo(toTeammate).abs();

      final distScore = 1 - (dist - 150).abs() / 150;
      final angleScore = 1 - angle / (pi / 2);
      final progressScore = goalDistThen < goalDistNow ? 1.0 : 0.0;

      final totalScore = distScore * 0.4 + angleScore * 0.3 + progressScore * 0.3;

      if (dist > 80 && dist < 350 && totalScore > bestScore) {
        bestScore = totalScore;
        best = t;
      }
    }
    return best;
  }

  bool _isPassSafe(Vector2 from, Vector2 to, {double tolerance = 25}) {
    final enemies = gameRef.players.where((p) => p.team != team);
    for (final enemy in enemies) {
      final toEnemy = enemy.position - from;
      final toTarget = to - from;
      final proj = toEnemy.dot(toTarget.normalized());
      if (proj < 0 || proj > toTarget.length) continue;

      final perpendicular = toEnemy - toTarget.normalized() * proj;
      if (perpendicular.length < tolerance) return false;
    }
    return true;
  }

  void _clampPosition() {
    position.x = position.x.clamp(radius, gameRef.size.x - radius);
    position.y = position.y.clamp(radius, gameRef.size.y - radius);
  }

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

    final spacing = fieldSize.y / 6;
    final y = spacing * (number % 6 + 0.5);

    return Vector2(xZone, y);
  }

  @override
  void render(Canvas canvas) {
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(Offset(2, 3), radius * 0.95, shadowPaint);

    final outlinePaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset.zero, radius + 2.0, outlinePaint);

    final fillPaint = Paint()..color = (team == 0 ? Colors.blue : Colors.yellow);
    canvas.drawCircle(Offset.zero, radius, fillPaint);

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
