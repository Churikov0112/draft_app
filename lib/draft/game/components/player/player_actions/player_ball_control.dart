// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'package:flame/components.dart';

import '../../../match_game.dart';
import '../../../models/player.dart';
import '../../goal_component.dart';
import '../player_component.dart';
import '../player_utils.dart';
import 'player_decision_making.dart';
import 'player_movement.dart';
import 'player_skills.dart';

extension PlayerBallControl on PlayerComponent {
  void handleBallInteraction() {
    final hasBall = ball!.owner == this;
    final time = gameRef.elapsedTime;

    if (hasBall) {
      handleBallPossession(time: time);
    } else {
      final dirToBall = ball!.position - position;
      final distToBall = dirToBall.length;
      handleBallChasing(time: time, distToBall: distToBall, dirToBall: dirToBall);
    }
  }

  void handleBallPossession({required double time}) {
    final goal = getOpponentGoal();
    final goalPos = goal.center;
    final distToGoal = (goalPos - position).length;
    final fieldZone = getFieldZone(position, goalPos, gameRef.size.x);

    if (distToGoal < 30 && !isThreatened(goal)) {
      shootAtGoal(goalPos, time);
      return;
    }

    final passScore = calculatePassScore(time, goal, fieldZone);
    final dribbleScore = calculateDribbleScore(goal, fieldZone);
    final shootScore = calculateShootScore(distToGoal, fieldZone);

    final bestAction = selectBestAction(passScore, dribbleScore, shootScore, goal);

    if (bestAction == PlayerAction.pass && !randomSkipPassDecision()) {
      if (attemptPass(time)) return;
    }

    if (bestAction == PlayerAction.shoot || distToGoal < 10) {
      shootAtGoal(goalPos, time);
      return;
    }

    moveWithBall((goalPos - position).normalized());
  }

  void handleBallChasing({required double time, required double distToBall, required Vector2 dirToBall}) {
    final isBallFree = ball!.owner == null;
    final isOpponentOwner = ball!.owner != null && ball!.owner!.pit.teamId != pit.teamId;

    if (isBallFree || isOpponentOwner) {
      if (isDesignatedPresser() || isSupportPresser(distToBall)) {
        pressBall(time, distToBall, dirToBall);
      } else {
        moveToOpenSpace();
      }
    } else {
      moveToOpenSpace();
    }
  }

  bool isDesignatedPresser() {
    final sameTeam = gameRef.players.where((p) => p.pit.teamId == pit.teamId).toList();
    sameTeam.sort((a, b) => (a.position - ball!.position).length.compareTo((b.position - ball!.position).length));
    for (final p in sameTeam) {
      if (p._canPress()) return identical(this, p);
    }
    return false;
  }

  bool isSupportPresser(double distToBall) {
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

  void pressBall(double time, double distToBall, Vector2 dirToBall) {
    if (gameRef.gameState == GameState.finished) {
      velocity = Vector2.zero();
      return;
    }

    final moveDir = dirToBall.normalized();
    velocity = moveDir * pit.data.stats.maxSpeed;
    position += velocity * deltaTime;

    final defenceSkill = pit.data.stats.defence / 100;
    final cooldown = stealCooldown * (1.0 - 0.5 * defenceSkill);
    final extendedReach = radius + ball!.radius + 2 + 10 * defenceSkill;
    final ballOwner = ball!.owner;
    final dribblingSkill = (ballOwner?.pit.data.stats.dribbling ?? 0) / 100;
    final possessionDuration = time - ball!.lastOwnershipTime;
    final timePenalty = possessionDuration > 5 ? 0.2 * (possessionDuration / 5) : 0;
    final stealChance = (defenceSkill - dribblingSkill + 1.0) / 2.0 + timePenalty;

    if (distToBall < extendedReach && (time - lastStealTime) > cooldown) {
      final success = gameRef.random.nextDouble() < stealChance;
      if (success) {
        ball!.takeOwnership(this);
        lastStealTime = time;
      }
    }
  }

  void moveWithBall(Vector2 dirToGoal, {double? speedFactor}) {
    if (gameRef.gameState == GameState.finished) {
      velocity = Vector2.zero();
      return;
    }

    final _isThreatened = isThreatened(getOpponentGoal());
    final dribblingSkill = pit.data.stats.dribbling / 100;
    final speedPenalty = _isThreatened ? 0.2 : 0.1;
    final baseSpeedFactor = speedFactor ?? (1.0 - speedPenalty * (1.0 - dribblingSkill));
    final moveDir = _isThreatened ? getEvadeDirection(dirToGoal) : dirToGoal;
    velocity = moveDir * pit.data.stats.maxSpeed * baseSpeedFactor;
    position += velocity * deltaTime;
    ball!.position = position + moveDir * (radius + ball!.radius + 1);
  }

  Vector2 getEvadeDirection(Vector2 dirToGoal) {
    final dribblingSkill = pit.data.stats.dribbling / 100;
    final evadeStrength = 0.5 + 0.5 * dribblingSkill;
    final perpendicular = Vector2(-dirToGoal.y, dirToGoal.x);
    return (dirToGoal + perpendicular * evadeStrength).normalized();
  }

  bool attemptPass(double time) {
    final teammate = findBestTeammate();
    if (teammate == null) return false;

    final passTarget = calculatePassTarget(teammate);
    if (!isPassSafe(position, passTarget)) return false;

    final inaccuracy = (1 - (pit.data.stats.lowPass / 100)) * (1 + fatigue);
    final noisyTarget =
        passTarget +
        Vector2(
          (gameRef.random.nextDouble() - 0.5) * 20 * inaccuracy,
          (gameRef.random.nextDouble() - 0.5) * 20 * inaccuracy,
        );

    executePass(time, teammate, noisyTarget);
    return true;
  }

  void executePass(double time, PlayerComponent teammate, Vector2 target) {
    final passPower = calculatePassPower(teammate.position);
    ball!.kickTowards(target, passPower, time, this);
    lastPassTime = time;
  }

  Vector2 calculatePassTarget(PlayerComponent teammate) {
    final leadFactor = 0.2 + 0.5 * (pit.data.stats.lowPass / 100);
    Vector2 predictedPos = teammate.position + (teammate.velocity * leadFactor);
    return findFreeZoneNear(predictedPos);
  }

  Vector2 findFreeZoneNear(Vector2 pos, {double radius = 50, int attempts = 10}) {
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

  double calculatePassPower(Vector2 target) {
    final basePower = (target - position).length * 3.0;
    final passSkill = pit.data.stats.lowPass / 100;
    return (basePower * (0.9 + 0.2 * passSkill)).clamp(200.0, 800.0);
  }

  void shootAtGoal(Vector2 goalPos, double time) {
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

    if (!isShotSafe(position, noisyGoal, ballSpeed: power)) return;

    ball!.kickTowards(noisyGoal, power, time, this);
  }

  bool isShotSafe(Vector2 from, Vector2 to, {required double ballSpeed}) {
    const double baseTolerance = 18.0;
    return !gameRef.players.any(
      (enemy) =>
          enemy.pit.teamId != pit.teamId && isInInterceptionZone(enemy, from, to, baseTolerance, ballSpeed: ballSpeed),
    );
  }

  bool isPassSafe(Vector2 from, Vector2 to) {
    final passSkill = pit.data.stats.lowPass / 100;
    final adjustedTolerance = 15 + 10 * (1 - passSkill);
    final hasTeammate = gameRef.players.any((p) => p.pit.teamId == pit.teamId && (p.position - to).length < 100);
    if (!hasTeammate) return false;
    return !gameRef.players.any(
      (enemy) => enemy.pit.teamId != pit.teamId && isInInterceptionZone(enemy, from, to, adjustedTolerance),
    );
  }

  bool isInInterceptionZone(
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

  bool isThreatened(GoalComponent goal) {
    final dirToGoal = (goal.center - position).normalized();
    return gameRef.players.any((enemy) => enemy.pit.teamId != pit.teamId && isInThreatZone(enemy, dirToGoal));
  }

  bool isInThreatZone(PlayerComponent enemy, Vector2 dirToGoal) {
    final toEnemy = enemy.position - position;
    final projection = toEnemy.dot(dirToGoal);
    final perpendicularDist = (toEnemy - dirToGoal * projection).length;
    return projection > 0 && projection < 150 && perpendicularDist < 25;
  }

  bool shouldPass(double time) {
    return (time - lastPassTime) > passCooldown && isThreatened(getOpponentGoal());
  }

  bool randomSkipPassDecision() {
    return gameRef.random.nextDouble() < 0.1;
  }
}
