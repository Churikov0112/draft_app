import 'dart:math';

import 'package:draft_app/draft/game/models/player.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';
import 'goal_component.dart';

enum TeamState { attack, defence, counter, neutral }

final Map<PlayerPosition, Offset> basePositions = {
  PlayerPosition.gk: Offset(0.05, 0.5),
  PlayerPosition.cb: Offset(0.25, 0.5),
  PlayerPosition.rb: Offset(0.25, 0.8),
  PlayerPosition.lb: Offset(0.25, 0.2),
  PlayerPosition.dm: Offset(0.35, 0.5),
  PlayerPosition.cm: Offset(0.45, 0.5),
  PlayerPosition.am: Offset(0.55, 0.5),
  PlayerPosition.lm: Offset(0.45, 0.2),
  PlayerPosition.rm: Offset(0.45, 0.8),
  PlayerPosition.lw: Offset(0.65, 0.2),
  PlayerPosition.rw: Offset(0.65, 0.8),
  PlayerPosition.cf: Offset(0.75, 0.5),
  PlayerPosition.ss: Offset(0.75, 0.45),
  PlayerPosition.st: Offset(0.75, 0.55),
};

class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  // Constants
  final double radius = 14.0;
  final double stealCooldown = 2.0;
  final double passCooldown = 2.0;

  // Player properties
  final PlayerInTeamModel pit;
  Vector2 velocity = Vector2.zero();
  BallComponent? ball;

  // Timers
  double _lastStealTime = 0;
  double _lastPassTime = 0;
  double _dt = 0;

  // Positioning
  Vector2 desiredPosition = Vector2.zero();
  double positionUpdateTimer = 0.0;
  double positionUpdateInterval = 3.0;

  // State
  double fatigue = 0.0;
  TeamState teamState = TeamState.neutral;
  double microMoveTimer = 0.0;

  PlayerComponent({required this.pit}) {
    desiredPosition = Vector2.zero();
    position = Vector2.zero();
    size = Vector2.all(radius * 2);
  }

  // Core methods
  @override
  void update(double dt) {
    super.update(dt);
    if (gameRef.gameState == GameState.finished) {
      velocity = Vector2.zero();
      return;
    }

    _dt = dt;
    if (ball == null) return;

    _updateTeamState();
    _updatePositioning(dt);
    _handleBallInteraction();
    _clampPosition();
  }

  @override
  void render(Canvas canvas) {
    _renderShadow(canvas);
    _renderPlayerOutline(canvas);
    _renderPlayerFill(canvas);
    _renderPlayerNumber(canvas);
  }

  // Ball control methods
  void assignBallRef(BallComponent b) => ball = b;

  bool _isAttackingTeam() => ball?.owner?.pit.teamId == pit.teamId;
  bool _isOnOwnHalf() => gameRef.isOwnHalf(pit.teamId, position);

  // State management
  void _updateTeamState() {
    final ballOwnerTeam = ball?.owner?.pit.teamId;
    if (ballOwnerTeam == pit.teamId) {
      teamState = TeamState.attack;
    } else if (ballOwnerTeam == null) {
      teamState = TeamState.neutral;
    } else {
      teamState = _isCounterAttackOpportunity() ? TeamState.counter : TeamState.defence;
    }
  }

  bool _isCounterAttackOpportunity() {
    final ballPos = ball?.position ?? Vector2.zero();
    final isInMiddle = ballPos.x > gameRef.size.x * 0.3 && ballPos.x < gameRef.size.x * 0.7;
    final hasFastPlayers = pit.data.stats.maxSpeed > 70;
    return isInMiddle && hasFastPlayers;
  }

  // Positioning logic
  void _updatePositioning(double dt) {
    positionUpdateTimer -= dt;
    if (positionUpdateTimer <= 0) {
      _updateDesiredPosition();
      positionUpdateTimer = positionUpdateInterval + gameRef.random.nextDouble() * 2.0;
    }
    _applyMicroAdjustments(dt);
  }

  void _updateDesiredPosition() {
    final attacking = _isAttackingTeam();
    final distToBall = (ball!.position - position).length;
    final secondsAhead = (0.5 + (distToBall / gameRef.size.x).clamp(0.0, 1.0)) * (attacking ? 1.0 : 0.6);
    final predictedBallPos = predictBallPosition(secondsAhead);
    final basePos = getHomePosition();
    final attackShift = _calculateTacticalShift(predictedBallPos, attacking);
    final randomShift = _calculateRandomPositionShift(attacking);
    desiredPosition = basePos + attackShift + randomShift;
    desiredPosition = _avoidNearbyOpponents(desiredPosition);
  }

  Vector2 predictBallPosition(double secondsAhead) {
    if (ball == null) return Vector2.zero();
    return ball!.owner != null
        ? ball!.position + ball!.owner!.velocity * secondsAhead
        : ball!.position + ball!.velocity * secondsAhead;
  }

  void _applyMicroAdjustments(double dt) {
    microMoveTimer -= dt;
    if (microMoveTimer <= 0) {
      final offset = Vector2((gameRef.random.nextDouble() - 0.5) * 4, (gameRef.random.nextDouble() - 0.5) * 4);
      desiredPosition += offset;
      microMoveTimer = 0.3 + gameRef.random.nextDouble() * 0.8;
    }
  }

  // Ball interaction logic
  void _handleBallInteraction() {
    final dirToBall = ball!.position - position;
    final distToBall = dirToBall.length;
    final hasBall = ball!.owner == this;
    final time = gameRef.elapsedTime;

    if (hasBall) {
      _handleBallPossession(time: time);
    } else {
      _handleBallChasing(time: time, distToBall: distToBall, dirToBall: dirToBall);
    }
  }

  void _handleBallPossession({required double time}) {
    final goal = _getOpponentGoal();
    final goalPos = goal.center;
    final distToGoal = (goalPos - position).length;
    final fieldZone = _getFieldZone(position, goalPos, gameRef.size.x);

    if (distToGoal < 30 && !_isThreatened(goal)) {
      _shootAtGoal(goalPos, time);
      return;
    }

    final passScore = _calculatePassScore(time, goal, fieldZone);
    final dribbleScore = _calculateDribbleScore(goal, fieldZone);
    final shootScore = _calculateShootScore(distToGoal, fieldZone);

    final bestAction = _selectBestAction(passScore, dribbleScore, shootScore, goal);

    if (bestAction == 'pass' && !_randomSkipPassDecision()) {
      if (_attemptPass(time)) return;
    }

    if (bestAction == 'shoot') {
      _shootAtGoal(goalPos, time);
      return;
    }

    if (distToGoal < 10) {
      _shootAtGoal(goalPos, time);
      return;
    }

    _moveWithBall((goalPos - position).normalized());
  }

  void _handleBallChasing({required double time, required double distToBall, required Vector2 dirToBall}) {
    final isBallFree = ball!.owner == null;
    final isOpponentOwner = ball!.owner != null && ball!.owner!.pit.teamId != pit.teamId;

    if (isBallFree || isOpponentOwner) {
      if (_isDesignatedPresser() || _isSupportPresser(distToBall)) {
        _pressBall(time, distToBall, dirToBall);
      } else {
        _moveToOpenSpace();
      }
    } else {
      _moveToOpenSpace();
    }
  }

  // Action decision methods
  String _selectBestAction(double passScore, double dribbleScore, double shootScore, GoalComponent goal) {
    final randomFactor = gameRef.random.nextDouble();
    if (randomFactor < 0.02) {
      final actions = _isOnOwnHalf() ? ['pass', 'dribble'] : ['pass', 'dribble', 'shoot'];
      return actions[gameRef.random.nextInt(actions.length)];
    }

    final teammate = _findBestTeammate();
    if (teammate != null) {
      final goalDistNow = (goal.center - position).length;
      final goalDistThen = (goal.center - teammate.position).length;
      if (goalDistThen < goalDistNow && passScore >= 0) passScore += 0.2;
    }

    if (passScore >= dribbleScore && passScore >= shootScore) return 'pass';
    if (shootScore >= passScore && shootScore >= dribbleScore) return 'shoot';
    return 'dribble';
  }

  // Pass related methods
  bool _attemptPass(double time) {
    final teammate = _findBestTeammate();
    if (teammate == null) return false;

    final passTarget = _calculatePassTarget(teammate);
    if (!_isPassSafe(position, passTarget)) return false;

    final inaccuracy = (1 - (pit.data.stats.lowPass / 100)) * (1 + fatigue);
    final noisyTarget =
        passTarget +
        Vector2(
          (gameRef.random.nextDouble() - 0.5) * 20 * inaccuracy,
          (gameRef.random.nextDouble() - 0.5) * 20 * inaccuracy,
        );

    _executePass(time, teammate, noisyTarget);
    return true;
  }

  void _executePass(double time, PlayerComponent teammate, Vector2 target) {
    final passPower = _calculatePassPower(teammate.position);
    ball!.kickTowards(target, passPower, time, this);
    _lastPassTime = time;
  }

  Vector2 _calculatePassTarget(PlayerComponent teammate) {
    final leadFactor = 0.2 + 0.5 * (pit.data.stats.lowPass / 100);
    Vector2 predictedPos = teammate.position + (teammate.velocity * leadFactor);
    return _findFreeZoneNear(predictedPos);
  }

  Vector2 _findFreeZoneNear(Vector2 pos, {double radius = 50, int attempts = 10}) {
    final random = gameRef.random;
    for (int i = 0; i < attempts; i++) {
      final offset =
          Vector2(random.nextDouble() * 2 - 1, random.nextDouble() * 2 - 1).normalized() * random.nextDouble() * radius;
      final testPos = pos + offset;
      final safe = !gameRef.players.any((p) => p.pit.teamId != pit.teamId && (p.position - testPos).length < 30);
      if (safe) return testPos;
    }
    return pos;
  }

  double _calculatePassPower(Vector2 target) {
    final basePower = (target - position).length * 3.0;
    final passSkill = pit.data.stats.lowPass / 100;
    return (basePower * (0.9 + 0.2 * passSkill)).clamp(200.0, 800.0);
  }

  // Shoot related methods
  void _shootAtGoal(Vector2 goalPos, double time) {
    final distToGoal = (goalPos - position).length;
    final shootSkill = pit.data.stats.shoots / 100;
    final goalHeight = 60.0;
    final verticalSpread = goalHeight * 0.5 * (1 - shootSkill);
    final fatigueFactor = 1.0 + fatigue * 0.5;
    final dy = (gameRef.random.nextDouble() - 0.5) * 2 * verticalSpread * fatigueFactor;
    final noisyGoal = goalPos + Vector2(0, dy);

    final minPower = 400.0;
    final maxPower = 1000.0;
    final distFactor = (distToGoal / 500).clamp(0.0, 1.0);
    final power = minPower + (maxPower - minPower) * distFactor * (0.7 + 0.3 * shootSkill);

    if (!_isShotSafe(position, noisyGoal, ballSpeed: power)) return;

    ball!.kickTowards(noisyGoal, power, time, this);
  }

  // Movement methods
  void _moveWithBall(Vector2 dirToGoal, {double? speedFactor}) {
    if (gameRef.gameState == GameState.finished) {
      velocity = Vector2.zero();
      return;
    }

    final isThreatened = _isThreatened(_getOpponentGoal());
    final dribblingSkill = pit.data.stats.dribbling / 100;
    final speedPenalty = isThreatened ? 0.2 : 0.1;
    final baseSpeedFactor = speedFactor ?? (1.0 - speedPenalty * (1.0 - dribblingSkill));
    final moveDir = isThreatened ? _getEvadeDirection(dirToGoal) : dirToGoal;
    velocity = moveDir * pit.data.stats.maxSpeed * baseSpeedFactor;
    position += velocity * _dt;
    ball!.position = position + moveDir * (radius + ball!.radius + 1);
  }

  Vector2 _getEvadeDirection(Vector2 dirToGoal) {
    final dribblingSkill = pit.data.stats.dribbling / 100;
    final evadeStrength = 0.5 + 0.5 * dribblingSkill;
    final perpendicular = Vector2(-dirToGoal.y, dirToGoal.x);
    return (dirToGoal + perpendicular * evadeStrength).normalized();
  }

  void _pressBall(double time, double distToBall, Vector2 dirToBall) {
    if (gameRef.gameState == GameState.finished) {
      velocity = Vector2.zero();
      return;
    }

    final moveDir = dirToBall.normalized();
    velocity = moveDir * pit.data.stats.maxSpeed;
    position += velocity * _dt;

    final defenceSkill = pit.data.stats.defence / 100;
    final cooldown = stealCooldown * (1.0 - 0.5 * defenceSkill);
    final extendedReach = radius + ball!.radius + 2 + 10 * defenceSkill;
    final ballOwner = ball!.owner;
    final dribblingSkill = (ballOwner?.pit.data.stats.dribbling ?? 0) / 100;
    final possessionDuration = time - ball!.lastOwnershipTime;
    final timePenalty = possessionDuration > 5 ? 0.2 * (possessionDuration / 5) : 0;
    final stealChance = (defenceSkill - dribblingSkill + 1.0) / 2.0 + timePenalty;

    if (distToBall < extendedReach && (time - _lastStealTime) > cooldown) {
      final success = gameRef.random.nextDouble() < stealChance;
      if (success) {
        ball!.takeOwnership(this);
        _lastStealTime = time;
      }
    }
  }

  void _moveToOpenSpace() {
    if (gameRef.gameState == GameState.finished) {
      velocity = Vector2.zero();
      return;
    }

    final toTarget = desiredPosition - position;
    if (toTarget.length > 4) {
      final speed = _isAttackingTeam() ? pit.data.stats.maxSpeed * 0.6 : pit.data.stats.maxSpeed * 0.4;
      velocity = toTarget.normalized() * speed;
      position += velocity * _dt;

      final nearbyTeammates = gameRef.players.where(
        (p) => p.pit.teamId == pit.teamId && p != this && (p.position - position).length < 30,
      );
      for (final t in nearbyTeammates) {
        final away = (position - t.position).normalized() * 10;
        position += away * _dt;
      }
    } else {
      velocity = Vector2.zero();
    }
  }

  // Helper methods
  String _getFieldZone(Vector2 position, Vector2 goalPos, double fieldLength) {
    final distToGoal = (goalPos - position).length;
    final attackingZoneThreshold = fieldLength * 0.3;
    final defensiveZoneThreshold = fieldLength * 0.7;

    if (distToGoal < attackingZoneThreshold) return 'attacking';
    if (distToGoal > defensiveZoneThreshold) return 'defensive';
    return 'middle';
  }

  bool _isThreatened(GoalComponent goal) {
    final dirToGoal = (goal.center - position).normalized();
    return gameRef.players.any((enemy) => enemy.pit.teamId != pit.teamId && _isInThreatZone(enemy, dirToGoal));
  }

  bool _isInThreatZone(PlayerComponent enemy, Vector2 dirToGoal) {
    final toEnemy = enemy.position - position;
    final projection = toEnemy.dot(dirToGoal);
    final perpendicularDist = (toEnemy - dirToGoal * projection).length;
    return projection > 0 && projection < 150 && perpendicularDist < 25;
  }

  bool _isShotSafe(Vector2 from, Vector2 to, {required double ballSpeed}) {
    const double baseTolerance = 18.0;
    return !gameRef.players.any(
      (enemy) =>
          enemy.pit.teamId != pit.teamId && _isInInterceptionZone(enemy, from, to, baseTolerance, ballSpeed: ballSpeed),
    );
  }

  bool _isPassSafe(Vector2 from, Vector2 to) {
    final passSkill = pit.data.stats.lowPass / 100;
    final adjustedTolerance = 15 + 10 * (1 - passSkill);
    final hasTeammate = gameRef.players.any((p) => p.pit.teamId == pit.teamId && (p.position - to).length < 100);
    if (!hasTeammate) return false;
    return !gameRef.players.any(
      (enemy) => enemy.pit.teamId != pit.teamId && _isInInterceptionZone(enemy, from, to, adjustedTolerance),
    );
  }

  bool _isInInterceptionZone(
    PlayerComponent enemy,
    Vector2 from,
    Vector2 to,
    double tolerance, {
    double ballSpeed = 400,
  }) {
    final toEnemy = enemy.position - from;
    final toTarget = to - from;
    final proj = toEnemy.dot(toTarget.normalized());
    if (proj < 0 || proj > toTarget.length) return false;
    final perpendicular = toEnemy - toTarget.normalized() * proj;
    final speedFactor = (1 / (ballSpeed / 400)).clamp(0.3, 1.0);
    final dynamicTolerance = tolerance * speedFactor;
    return perpendicular.length < dynamicTolerance;
  }

  // Position calculation methods
  Vector2 _calculateTacticalShift(Vector2 ballPos, bool attacking) {
    final fieldLength = gameRef.size.x;
    final fieldWidth = gameRef.size.y;
    final attackBiasX = ((ballPos.x - position.x) / fieldLength) * 120;
    final sideBiasY = ((ballPos.y - position.y) / fieldWidth) * 60;
    final nearbyEnemies = gameRef.players
        .where((p) => p.pit.teamId != pit.teamId && (p.position - ballPos).length < 50)
        .length;
    final crowdFactor = nearbyEnemies > 3 ? 0.5 : 1.0;
    final multiplier = attacking ? (teamState == TeamState.counter ? 1.4 : 1.0) : 0.3;
    return Vector2(attackBiasX * multiplier * crowdFactor, sideBiasY * multiplier * crowdFactor);
  }

  Vector2 _calculateRandomPositionShift(bool attacking) {
    final random = gameRef.random;
    double xShift = 0;
    double yShift = 0;

    final shiftChance = random.nextDouble();
    final shiftThreshold = _getPositionShiftThreshold();

    if (shiftChance < shiftThreshold) {
      final isTeamOnLeft = gameRef.isTeamOnLeftSide(pit.teamId);
      xShift = attacking ? (isTeamOnLeft ? 100 : -100) : (isTeamOnLeft ? -100 : 100);

      final isWidePlayer = [
        PlayerPosition.rb,
        PlayerPosition.lb,
        PlayerPosition.lm,
        PlayerPosition.rm,
        PlayerPosition.lw,
        PlayerPosition.rw,
      ].contains(pit.position);

      final yRange = isWidePlayer ? 80 : 40;
      yShift = (random.nextDouble() - 0.5) * yRange;
      xShift *= _getPositionShiftMultiplier();
    }

    return Vector2(xShift, yShift);
  }

  double _getPositionShiftThreshold() {
    switch (pit.position) {
      case PlayerPosition.cb:
        return 0.2;
      case PlayerPosition.rb:
      case PlayerPosition.lb:
        return 0.3;
      case PlayerPosition.dm:
        return 0.35;
      case PlayerPosition.cm:
      case PlayerPosition.am:
        return 0.4;
      case PlayerPosition.lm:
      case PlayerPosition.rm:
        return 0.45;
      case PlayerPosition.lw:
      case PlayerPosition.rw:
        return 0.35;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.cf:
        return 0.15;
      default:
        return 0.3;
    }
  }

  double _getPositionShiftMultiplier() {
    switch (pit.position) {
      case PlayerPosition.st:
      case PlayerPosition.cf:
      case PlayerPosition.ss:
        return 1.5;
      case PlayerPosition.lw:
      case PlayerPosition.rw:
        return 1.2;
      case PlayerPosition.am:
      case PlayerPosition.cm:
        return 1.0;
      case PlayerPosition.dm:
      case PlayerPosition.cb:
        return 0.8;
      default:
        return 1.0;
    }
  }

  Vector2 _avoidNearbyOpponents(Vector2 target) {
    final nearbyEnemies = gameRef.players.where((p) => p.pit.teamId != pit.teamId && (p.position - target).length < 60);
    Vector2 avoidance = Vector2.zero();
    double crowdFactor = nearbyEnemies.length > 2 ? 1.5 : 1.0;
    for (final enemy in nearbyEnemies) {
      final away = (target - enemy.position).normalized();
      avoidance += away * 30 * crowdFactor;
    }
    return target + avoidance;
  }

  // Teammate selection methods
  PlayerComponent? _findBestTeammate() {
    final teammates = gameRef.players.where((p) => p.pit.teamId == pit.teamId && p != this);
    PlayerComponent? best;
    double bestScore = -1;

    final goalPos = _getOpponentGoal().center;
    final goalDistNow = (goalPos - position).length;

    for (final t in teammates) {
      final score = _calculateTeammateScore(t, goalPos, goalDistNow);
      if (score > bestScore && score > 0.5) {
        bestScore = score;
        best = t;
      }
    }
    return best;
  }

  double _calculateTeammateScore(PlayerComponent t, Vector2 goalPos, double goalDistNow) {
    final toTeammate = t.position - position;
    final dist = toTeammate.length;
    final goalDistThen = (goalPos - t.position).length;
    final goalDir = goalPos - position;
    final angle = goalDir.angleTo(toTeammate).abs();
    final distScore = 1 - (dist - 150).abs() / 150;
    final angleScore = 1 - angle / (pi / 2);
    final progressScore = goalDistThen < goalDistNow ? 1.0 : 0.0;
    final nearestOpponentDist = _getNearestOpponentTo(t.position).length;
    final safetyScore = nearestOpponentDist > 50 ? 1.0 : 0.5;
    return distScore * 0.3 + angleScore * 0.3 + progressScore * 0.2 + safetyScore * 0.2;
  }

  Vector2 _getNearestOpponentTo(Vector2 pos) {
    final opponents = gameRef.players.where((p) => p.pit.teamId != pit.teamId);
    Vector2 nearest = Vector2.zero();
    double minDist = double.infinity;
    for (final o in opponents) {
      final dist = (o.position - pos).length;
      if (dist < minDist) {
        minDist = dist;
        nearest = o.position;
      }
    }
    return nearest;
  }

  // Pressing logic
  bool _isDesignatedPresser() {
    final sameTeam = gameRef.players.where((p) => p.pit.teamId == pit.teamId).toList();
    sameTeam.sort((a, b) => (a.position - ball!.position).length.compareTo((b.position - ball!.position).length));
    for (final p in sameTeam) {
      if (p._canPress()) return identical(this, p);
    }
    return false;
  }

  bool _isSupportPresser(double distToBall) {
    final nearbyAllies = gameRef.players
        .where((p) => p.pit.teamId == pit.teamId && (p.position - position).length < 50)
        .length;
    return distToBall < 50 && nearbyAllies > 1;
  }

  bool _canPress() {
    final ballPos = ball?.position ?? Vector2.zero();
    final dist = (position - ballPos).length;
    final isOwnHalf = gameRef.isOwnHalf(pit.teamId, position);
    final randomChance = gameRef.random.nextDouble();

    final pressThreshold = _getPressThreshold();
    if (randomChance < pressThreshold) return true;

    return _shouldPressBasedOnPosition(dist, isOwnHalf);
  }

  double _getPressThreshold() {
    switch (pit.position) {
      case PlayerPosition.cb:
        return 0.5;
      case PlayerPosition.rb:
      case PlayerPosition.lb:
        return 0.4;
      case PlayerPosition.dm:
        return 0.4;
      case PlayerPosition.cm:
      case PlayerPosition.am:
        return 0.3;
      case PlayerPosition.lm:
      case PlayerPosition.rm:
        return 0.25;
      case PlayerPosition.lw:
      case PlayerPosition.rw:
        return 0.15;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.cf:
        return 0.1;
      default:
        return 0.3;
    }
  }

  bool _shouldPressBasedOnPosition(double dist, bool isOwnHalf) {
    switch (pit.position) {
      case PlayerPosition.cb:
      case PlayerPosition.rb:
      case PlayerPosition.lb:
        return true;
      case PlayerPosition.dm:
      case PlayerPosition.cm:
      case PlayerPosition.am:
        return isOwnHalf || dist < 200;
      case PlayerPosition.lm:
      case PlayerPosition.rm:
        return isOwnHalf || dist < 180;
      case PlayerPosition.lw:
      case PlayerPosition.rw:
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.cf:
        return dist < 150;
      default:
        return false;
    }
  }

  // Score calculation methods
  double _calculatePassScore(double time, GoalComponent goal, String fieldZone) {
    if (!_shouldPass(time)) return -1.0;
    final teammate = _findBestTeammate();
    if (teammate == null) return -1.0;

    final passTarget = _calculatePassTarget(teammate);
    if (!_isPassSafe(position, passTarget)) return -1.0;

    final zoneWeight = _getZoneWeight(fieldZone);
    final roleModifier = _getRoleModifier();
    final isThreatened = _isThreatened(goal);
    final threatFactor = isThreatened ? 1.2 : 1.0;
    final passSkill = pit.data.stats.lowPass / 100;
    final goalDistNow = (goal.center - position).length;
    final goalDistThen = (goal.center - teammate.position).length;
    final progressScore = goalDistThen < goalDistNow ? 1.0 : 0.5;

    return zoneWeight * roleModifier * (0.4 * passSkill + 0.3 * progressScore + 0.3 * threatFactor);
  }

  double _calculateDribbleScore(GoalComponent goal, String fieldZone) {
    final isThreatened = _isThreatened(goal);
    final dribblingSkill = pit.data.stats.dribbling / 100;
    final zoneWeight = _getZoneWeight(fieldZone);
    final roleModifier = _getDribbleRoleModifier();
    final threatFactor = isThreatened ? 0.7 : 1.0;
    return zoneWeight * roleModifier * (0.6 * dribblingSkill + 0.4 * threatFactor);
  }

  double _calculateShootScore(double distToGoal, String fieldZone) {
    final shootThreshold = 200.0;
    if (_isOnOwnHalf() || distToGoal > shootThreshold) return -1.0;

    final zoneWeight = _getShootZoneWeight(fieldZone, distToGoal);
    final roleModifier = _getShootRoleModifier();
    final shootSkill = pit.data.stats.shoots / 100;
    final distanceFactor = pow(1.0 - (distToGoal / shootThreshold), 2);
    final threatFactor = _isThreatened(_getOpponentGoal()) ? 0.8 : 1.5;

    return zoneWeight * roleModifier * (0.5 * shootSkill + 0.3 * distanceFactor + 0.2 * threatFactor);
  }

  double _getZoneWeight(String fieldZone) {
    switch (fieldZone) {
      case 'defensive':
        return 0.95;
      case 'middle':
        return 0.75;
      case 'attacking':
        return 0.4;
      default:
        return 0.5;
    }
  }

  double _getShootZoneWeight(String fieldZone, double distToGoal) {
    switch (fieldZone) {
      case 'defensive':
        return 0.0;
      case 'middle':
        return 0.05;
      case 'attacking':
        return distToGoal < 50 ? 1.2 : 0.9;
      default:
        return 0.5;
    }
  }

  double _getRoleModifier() {
    switch (pit.position) {
      case PlayerPosition.cb:
      case PlayerPosition.lb:
      case PlayerPosition.rb:
        return 1.2;
      case PlayerPosition.dm:
      case PlayerPosition.cm:
      case PlayerPosition.am:
      case PlayerPosition.lm:
      case PlayerPosition.rm:
        return 1.0;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.lw:
      case PlayerPosition.rw:
      case PlayerPosition.cf:
        return 0.8;
      default:
        return 1.0;
    }
  }

  double _getDribbleRoleModifier() {
    switch (pit.position) {
      case PlayerPosition.cb:
        return 0.6;
      case PlayerPosition.lb:
      case PlayerPosition.rb:
        return 0.8;
      case PlayerPosition.dm:
      case PlayerPosition.cm:
      case PlayerPosition.am:
        return 1.0;
      case PlayerPosition.lm:
      case PlayerPosition.rm:
      case PlayerPosition.lw:
      case PlayerPosition.rw:
        return 1.4;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.cf:
        return 1.2;
      default:
        return 1.0;
    }
  }

  double _getShootRoleModifier() {
    switch (pit.position) {
      case PlayerPosition.cb:
        return 0.4;
      case PlayerPosition.rb:
      case PlayerPosition.lb:
        return 0.5;
      case PlayerPosition.cm:
      case PlayerPosition.dm:
      case PlayerPosition.am:
        return 0.9;
      case PlayerPosition.lw:
      case PlayerPosition.rw:
      case PlayerPosition.rm:
      case PlayerPosition.lm:
        return 1.1;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.cf:
        return 1.3;
      default:
        return 1.0;
    }
  }

  bool _shouldPass(double time) {
    return (time - _lastPassTime) > passCooldown && _isThreatened(_getOpponentGoal());
  }

  bool _randomSkipPassDecision() {
    return gameRef.random.nextDouble() < 0.1;
  }

  // Position methods
  Vector2 getHomePosition() {
    final fieldSize = gameRef.size;
    final isLeft = gameRef.isTeamOnLeftSide(pit.teamId);
    final base = basePositions[pit.position] ?? const Offset(0.5, 0.5);
    double xZone = isLeft ? fieldSize.x * base.dx : fieldSize.x * (1 - base.dx);
    double yZone = fieldSize.y * base.dy;

    final samePositionPlayers = gameRef.players
        .where((p) => p.pit.teamId == pit.teamId && p.pit.position == pit.position)
        .toList();

    if (samePositionPlayers.length > 1) {
      final index = samePositionPlayers.indexOf(this);
      final offsetStep = 100.0;
      xZone += (index - (samePositionPlayers.length - 1) / 2) * offsetStep;
      yZone += (index - (samePositionPlayers.length - 1) / 2) * offsetStep;
    }

    final random = gameRef.random;
    xZone += (random.nextDouble() - 0.5) * 10;
    yZone += (random.nextDouble() - 0.5) * 10;

    return Vector2(xZone, yZone);
  }

  void _clampPosition() {
    position.x = position.x.clamp(radius, gameRef.size.x - radius);
    position.y = position.y.clamp(radius, gameRef.size.y - radius);
  }

  // Goal methods
  GoalComponent _getOpponentGoal() {
    final isTeamOnLeft = gameRef.isTeamOnLeftSide(pit.teamId);
    return isTeamOnLeft ? gameRef.rightGoal : gameRef.leftGoal;
  }

  // Rendering methods
  void _renderShadow(Canvas canvas) {
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(Offset(2, 3), radius * 0.95, shadowPaint);
  }

  void _renderPlayerOutline(Canvas canvas) {
    final outlinePaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset.zero, radius + 2.0, outlinePaint);
  }

  void _renderPlayerFill(Canvas canvas) {
    final fillPaint = Paint()..color = pit.teamId == gameRef.teamA.id ? gameRef.teamA.color : gameRef.teamB.color;
    canvas.drawCircle(Offset.zero, radius, fillPaint);
  }

  void _renderPlayerNumber(Canvas canvas) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: pit.number.toString(),
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -radius - textPainter.height - 4));
  }
}
