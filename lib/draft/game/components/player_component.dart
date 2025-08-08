import 'dart:math';

import 'package:draft_app/draft/game/models/player.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';
import 'goal_component.dart';

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

/// Компонент игрока
class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  // Константы
  static const double playerRadius = 14.0; // Радиус игрока
  static const double stealCooldown = 2.0; // Время между попытками отбора
  static const double passCooldown = 2.0; // Время между передачами

  final PlayerInTeamModel pit;

  double radius = playerRadius; // Физический радиус
  Vector2 velocity = Vector2.zero(); // Текущая скорость
  BallComponent? ball; // Ссылка на мяч

  // Таймеры
  double _lastStealTime = 0; // Время последнего отбора
  double _lastPassTime = 0; // Время последней передачи

  double _dt = 0;

  // Добавлены переменные для периодического обновления позиции
  Vector2 desiredPosition = Vector2.zero();
  double positionUpdateTimer = 0.0;
  double positionUpdateInterval = 3.0; // Обновление каждые 3-5 секунд

  PlayerComponent({required this.pit, Vector2? position})
    : super(position: position ?? Vector2.zero(), size: Vector2.all(28)) {
    desiredPosition = Vector2.zero(); // Инициализация желаемой позиции
  }

  /// Установка ссылки на мяч
  void assignBallRef(BallComponent b) => ball = b;

  bool _isAttackingTeam() => ball?.owner?.pit.teamId == pit.teamId;

  /// Проверка, находится ли игрок на своей половине поля
  bool _isOnOwnHalf() => gameRef.isOwnHalf(pit.teamId, position);

  @override
  void update(double dt) {
    super.update(dt);
    _dt = dt;

    if (ball == null) return;

    // Обновление таймера для желаемой позиции
    positionUpdateTimer -= dt;
    if (positionUpdateTimer <= 0) {
      _updateDesiredPosition();
      positionUpdateTimer = positionUpdateInterval + gameRef.random.nextDouble() * 2.0; // 3-5 секунд
    }

    _handleBallInteraction();
    _clampPosition();
  }

  /// Обновление желаемой позиции
  void _updateDesiredPosition() {
    final attacking = _isAttackingTeam();
    final ballPos = ball?.position ?? Vector2.zero();
    final basePos = getHomePosition();
    final attackShift = _calculateTacticalShift(ballPos, attacking);
    final randomShift = _calculateRandomPositionShift(attacking);
    desiredPosition = basePos + attackShift + randomShift;
    desiredPosition = _avoidNearbyOpponents(desiredPosition);
  }

  /// Основная логика взаимодействия с мячом
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

  // ====================== Логика при владении мячом ======================

  /// Определение зоны поля
  String _getFieldZone(Vector2 position, Vector2 goalPos, double fieldLength) {
    final distToGoal = (goalPos - position).length;
    final attackingZoneThreshold = fieldLength * 0.3;
    final defensiveZoneThreshold = fieldLength * 0.7;

    if (distToGoal < attackingZoneThreshold) {
      return 'attacking';
    } else if (distToGoal > defensiveZoneThreshold) {
      return 'defensive';
    } else {
      return 'middle';
    }
  }

  /// Обработка ситуации, когда игрок владеет мячом
  void _handleBallPossession({required double time}) {
    final goal = _getOpponentGoal();
    final goalPos = goal.center;
    final dirToGoal = (goalPos - position).normalized();
    final distToGoal = (goalPos - position).length;
    final fieldZone = _getFieldZone(position, goalPos, gameRef.size.x);

    final passScore = _calculatePassScore(time, goal, fieldZone);
    final dribbleScore = _calculateDribbleScore(goal, fieldZone);
    final shootScore = _calculateShootScore(distToGoal, fieldZone);

    final bestAction = _selectBestAction(passScore, dribbleScore, shootScore);

    if (bestAction == 'pass' && !_randomSkipPassDecision()) {
      if (_attemptPass(time)) {
        return;
      }
    }

    if (bestAction == 'shoot') {
      _shootAtGoal(goalPos, time);
      return;
    }

    _moveWithBall(dirToGoal);
  }

  /// Расчет балла для паса
  double _calculatePassScore(double time, GoalComponent goal, String fieldZone) {
    if (!_shouldPass(time)) return -1.0;

    final teammate = _findBestTeammate();
    if (teammate == null) return -1.0;

    final passTarget = _calculatePassTarget(teammate);
    if (!_isPassSafe(position, passTarget)) return -1.0;

    double zoneWeight;
    switch (fieldZone) {
      case 'defensive':
        zoneWeight = 0.95;
        break;
      case 'middle':
        zoneWeight = 0.75;
        break;
      case 'attacking':
        zoneWeight = 0.4;
        break;
      default:
        zoneWeight = 0.5;
    }

    double roleModifier;
    switch (pit.position) {
      case PlayerPosition.cb:
      case PlayerPosition.lb:
      case PlayerPosition.rb:
        roleModifier = 1.2;
        break;
      case PlayerPosition.dm:
      case PlayerPosition.cm:
      case PlayerPosition.am:
      case PlayerPosition.lm:
      case PlayerPosition.rm:
        roleModifier = 1.0;
        break;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.lw:
      case PlayerPosition.rw:
      case PlayerPosition.cf:
        roleModifier = 0.8;
        break;
      default:
        roleModifier = 1.0;
    }

    final isThreatened = _isThreatened(goal);
    final threatFactor = isThreatened ? 1.2 : 1.0;
    final passSkill = pit.data.stats.lowPass / 100;
    final goalDistNow = (goal.center - position).length;
    final goalDistThen = (goal.center - teammate.position).length;
    final progressScore = goalDistThen < goalDistNow ? 1.0 : 0.5;

    return zoneWeight * roleModifier * (0.4 * passSkill + 0.3 * progressScore + 0.3 * threatFactor);
  }

  /// Расчет балла для дриблинга
  double _calculateDribbleScore(GoalComponent goal, String fieldZone) {
    final isThreatened = _isThreatened(goal);
    final dribblingSkill = pit.data.stats.dribbling / 100;

    double zoneWeight;
    switch (fieldZone) {
      case 'defensive':
        zoneWeight = 0.2;
        break;
      case 'middle':
        zoneWeight = 0.65;
        break;
      case 'attacking':
        zoneWeight = 0.8;
        break;
      default:
        zoneWeight = 0.5;
    }

    double roleModifier;
    switch (pit.position) {
      case PlayerPosition.cb:
        roleModifier = 0.6;
        break;
      case PlayerPosition.lb:
      case PlayerPosition.rb:
        roleModifier = 0.8;
        break;
      case PlayerPosition.dm:
      case PlayerPosition.cm:
      case PlayerPosition.am:
        roleModifier = 1.0;
        break;
      case PlayerPosition.lm:
      case PlayerPosition.rm:
      case PlayerPosition.lw:
      case PlayerPosition.rw:
        roleModifier = 1.4;
        break;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.cf:
        roleModifier = 1.2;
        break;
      default:
        roleModifier = 1.0;
    }

    final threatFactor = isThreatened ? 0.7 : 1.0;

    return zoneWeight * roleModifier * (0.6 * dribblingSkill + 0.4 * threatFactor);
  }

  /// Расчет балла для удара
  double _calculateShootScore(double distToGoal, String fieldZone) {
    if (_isOnOwnHalf()) return -1.0;

    final shootThreshold = 150.0;
    if (distToGoal > shootThreshold) return -1.0;

    double zoneWeight;
    switch (fieldZone) {
      case 'defensive':
        zoneWeight = 0.0;
        break;
      case 'middle':
        zoneWeight = 0.05;
        break;
      case 'attacking':
        zoneWeight = 0.9;
        break;
      default:
        zoneWeight = 0.5;
    }

    double roleModifier;
    switch (pit.position) {
      case PlayerPosition.cb:
        roleModifier = 0.4;
        break;
      case PlayerPosition.rb:
      case PlayerPosition.lb:
        roleModifier = 0.5;
        break;
      case PlayerPosition.cm:
      case PlayerPosition.dm:
      case PlayerPosition.am:
        roleModifier = 0.9;
        break;
      case PlayerPosition.lw:
      case PlayerPosition.rw:
      case PlayerPosition.rm:
      case PlayerPosition.lm:
        roleModifier = 1.1;
        break;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.cf:
        roleModifier = 1.3;
        break;
      default:
        roleModifier = 1.0;
    }

    final shootSkill = pit.data.stats.shoots / 100;
    final distanceFactor = 1.0 - (distToGoal / shootThreshold);

    return zoneWeight * roleModifier * (0.6 * shootSkill + 0.4 * distanceFactor);
  }

  /// Выбор лучшего действия
  String _selectBestAction(double passScore, double dribbleScore, double shootScore) {
    final randomFactor = gameRef.random.nextDouble();
    if (randomFactor < 0.02) {
      final actions = _isOnOwnHalf() ? ['pass', 'dribble'] : ['pass', 'dribble', 'shoot'];
      return actions[gameRef.random.nextInt(actions.length)];
    }

    if (passScore >= dribbleScore && passScore >= shootScore) return 'pass';
    if (shootScore >= passScore && shootScore >= dribbleScore) return 'shoot';
    return 'dribble';
  }

  /// Проверка, нужно ли делать пас
  bool _shouldPass(double time) {
    return (time - _lastPassTime) > passCooldown && _isThreatened(_getOpponentGoal());
  }

  /// Проверка наличия угрозы от соперников
  bool _isThreatened(GoalComponent goal) {
    final dirToGoal = (goal.center - position).normalized();
    return gameRef.players.any((enemy) => enemy.pit.teamId != pit.teamId && _isInThreatZone(enemy, dirToGoal));
  }

  /// Проверка, находится ли соперник в опасной зоне
  bool _isInThreatZone(PlayerComponent enemy, Vector2 dirToGoal) {
    final toEnemy = enemy.position - position;
    final projection = toEnemy.dot(dirToGoal);
    final perpendicularDist = (toEnemy - dirToGoal * projection).length;
    return projection > 0 && projection < 150 && perpendicularDist < 25;
  }

  /// Попытка сделать пас
  bool _attemptPass(double time) {
    final teammate = _findBestTeammate();
    if (teammate == null) return false;

    final passTarget = _calculatePassTarget(teammate);
    if (!_isPassSafe(position, passTarget)) {
      return false;
    }

    _executePass(time, teammate, passTarget);
    return true;
  }

  /// Выполнение паса
  void _executePass(double time, PlayerComponent teammate, Vector2 target) {
    final passPower = _calculatePassPower(teammate.position);
    ball!.kickTowards(target, passPower, time, this);
    _lastPassTime = time;
    print("Player ${pit.number} passed to ${teammate.pit.number}");
  }

  /// Расчет цели для паса с упреждением
  Vector2 _calculatePassTarget(PlayerComponent teammate) {
    final leadFactor = 0.2 + 0.5 * (pit.data.stats.lowPass / 100);
    Vector2 predictedPos = teammate.position + (teammate.velocity * leadFactor);
    final freeSpot = _findFreeZoneNear(predictedPos);
    return freeSpot;
  }

  Vector2 _findFreeZoneNear(Vector2 pos, {double radius = 50, int attempts = 10}) {
    final random = gameRef.random;

    for (int i = 0; i < attempts; i++) {
      final offset =
          Vector2(random.nextDouble() * 2 - 1, random.nextDouble() * 2 - 1).normalized() * random.nextDouble() * radius;
      final testPos = pos + offset;
      final safe = !gameRef.players.any((p) => p.pit.teamId != pit.teamId && (p.position - testPos).length < 30);
      if (safe) {
        return testPos;
      }
    }
    return pos;
  }

  /// Расчет силы паса
  double _calculatePassPower(Vector2 target) {
    final basePower = (target - position).length * 3.0;
    final passSkill = pit.data.stats.lowPass / 100;
    return (basePower * (0.9 + 0.2 * passSkill)).clamp(200, 800);
  }

  /// Перемещение с мячом
  void _moveWithBall(Vector2 dirToGoal, {double? speedFactor}) {
    final isThreatened = _isThreatened(_getOpponentGoal());
    final dribblingSkill = pit.data.stats.dribbling / 100;
    final speedPenalty = isThreatened ? 0.2 : 0.1;
    final baseSpeedFactor = speedFactor ?? (1.0 - speedPenalty * (1.0 - dribblingSkill));
    final moveDir = isThreatened ? _getEvadeDirection(dirToGoal) : dirToGoal;
    velocity = moveDir * pit.data.stats.maxSpeed * baseSpeedFactor;
    position += velocity * _dt;
    ball!.position = position + moveDir * (radius + ball!.radius + 1);
  }

  /// Расчет направления для уклонения
  Vector2 _getEvadeDirection(Vector2 dirToGoal) {
    final dribblingSkill = pit.data.stats.dribbling / 100;
    final evadeStrength = 0.5 + 0.5 * dribblingSkill;
    final perpendicular = Vector2(-dirToGoal.y, dirToGoal.x);
    return (dirToGoal + perpendicular * evadeStrength).normalized();
  }

  /// Удар по воротам
  void _shootAtGoal(Vector2 goalPos, double time) {
    final distToGoal = (goalPos - position).length;
    final fieldZone = _getFieldZone(position, goalPos, gameRef.size.x);
    print(
      "Player ${pit.number} (team ${pit.teamId}, role ${pit.position.toString().split('.').last}) shoots from position (${position.x.toStringAsFixed(1)}, ${position.y.toStringAsFixed(1)}) in zone $fieldZone with distance $distToGoal",
    );

    final shootSkill = pit.data.stats.shoots / 100;
    final goalHeight = 60.0;
    final verticalSpread = goalHeight * 0.5 * (1 - shootSkill);
    final dy = (gameRef.random.nextDouble() - 0.5) * 2 * verticalSpread;
    final target = goalPos + Vector2(0, dy);
    final minPower = 400.0;
    final maxPower = 1000.0;
    final distFactor = (distToGoal / 500).clamp(0.0, 1.0);
    final power = minPower + (maxPower - minPower) * distFactor * (0.7 + 0.3 * shootSkill);

    if (!_isShotSafe(position, target, ballSpeed: power)) {
      return;
    }

    ball!.kickTowards(target, power, time, this);
    print("Player ${pit.number} shoots at goal with power ${power.toStringAsFixed(1)}");
  }

  bool _isShotSafe(Vector2 from, Vector2 to, {required double ballSpeed}) {
    const double baseTolerance = 18.0;
    return !gameRef.players.any(
      (enemy) =>
          enemy.pit.teamId != pit.teamId && _isInInterceptionZone(enemy, from, to, baseTolerance, ballSpeed: ballSpeed),
    );
  }

  // ====================== Логика преследования мяча ======================

  /// Обработка ситуации, когда мяч у соперника или свободен
  void _handleBallChasing({required double time, required double distToBall, required Vector2 dirToBall}) {
    final isBallFree = ball!.owner == null;
    final isOpponentOwner = ball!.owner != null && ball!.owner!.pit.teamId != pit.teamId;

    if (isBallFree || isOpponentOwner) {
      if (_isDesignatedPresser()) {
        _pressBall(time, distToBall, dirToBall);
      } else {
        _moveToOpenSpace();
      }
    } else {
      _moveToOpenSpace();
    }
  }

  /// Проверка, является ли игрок ближайшим к мячу в своей команде
  bool _isDesignatedPresser() {
    final sameTeam = gameRef.players.where((p) => p.pit.teamId == pit.teamId).toList();
    sameTeam.sort((a, b) => (a.position - ball!.position).length.compareTo((b.position - ball!.position).length));

    for (final p in sameTeam) {
      if (p._canPress()) {
        return identical(this, p);
      }
    }
    return false;
  }

  bool _canPress() {
    final ballPos = ball?.position ?? Vector2.zero();
    final dist = (position - ballPos).length;
    final isOwnHalf = gameRef.isOwnHalf(pit.teamId, position);
    final randomChance = gameRef.random.nextDouble();

    double pressThreshold;
    switch (pit.position) {
      case PlayerPosition.cb:
        pressThreshold = 0.5;
        break;
      case PlayerPosition.rb:
      case PlayerPosition.lb:
        pressThreshold = 0.4;
        break;
      case PlayerPosition.dm:
        pressThreshold = 0.4;
        break;
      case PlayerPosition.cm:
      case PlayerPosition.am:
        pressThreshold = 0.3;
        break;
      case PlayerPosition.lm:
      case PlayerPosition.rm:
        pressThreshold = 0.25;
        break;
      case PlayerPosition.lw:
      case PlayerPosition.rw:
        pressThreshold = 0.15;
        break;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.cf:
        pressThreshold = 0.1;
        break;
      default:
        pressThreshold = 0.3;
    }

    if (randomChance < pressThreshold) {
      return true;
    }

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

  /// Прессинг мяча
  void _pressBall(double time, double distToBall, Vector2 dirToBall) {
    final moveDir = dirToBall.normalized();
    velocity = moveDir * pit.data.stats.maxSpeed;
    position += velocity * _dt;

    final defenceSkill = pit.data.stats.defence / 100;
    final cooldown = stealCooldown * (1.0 - 0.5 * defenceSkill);
    final extendedReach = radius + ball!.radius + 2 + 10 * defenceSkill;
    final ballOwner = ball!.owner;
    final dribblingSkill = (ballOwner?.pit.data.stats.dribbling ?? 0) / 100;
    final stealChance = (defenceSkill - dribblingSkill + 1.0) / 2.0;

    if (distToBall < extendedReach && (time - _lastStealTime) > cooldown) {
      final success = gameRef.random.nextDouble() < stealChance;
      if (success) {
        ball!.takeOwnership(this);
        _lastStealTime = time;
      }
    }
  }

  /// Перемещение на свободную позицию
  void _moveToOpenSpace() {
    final toTarget = desiredPosition - position;
    if (toTarget.length > 4) {
      final speed = _isAttackingTeam() ? pit.data.stats.maxSpeed * 0.6 : pit.data.stats.maxSpeed * 0.4;
      velocity = toTarget.normalized() * speed;
      position += velocity * _dt;
    } else {
      velocity = Vector2.zero();
    }
  }

  Vector2 _calculateTacticalShift(Vector2 ballPos, bool attacking) {
    final fieldLength = gameRef.size.x;
    final fieldWidth = gameRef.size.y;

    // Увеличены коэффициенты для большего смещения к мячу
    final attackBiasX = ((ballPos.x - position.x) / fieldLength) * 120; // Было 80
    final sideBiasY = ((ballPos.y - position.y) / fieldWidth) * 60; // Было 40

    final multiplier = attacking ? 1.0 : 0.3;

    return Vector2(attackBiasX * multiplier, sideBiasY * multiplier);
  }

  Vector2 _calculateRandomPositionShift(bool attacking) {
    final random = gameRef.random;
    double xShift = 0;
    double yShift = 0;

    final shiftChance = random.nextDouble();
    double shiftThreshold;

    switch (pit.position) {
      case PlayerPosition.cb:
        shiftThreshold = 0.2;
        break;
      case PlayerPosition.rb:
      case PlayerPosition.lb:
        shiftThreshold = 0.3;
        break;
      case PlayerPosition.dm:
        shiftThreshold = 0.35;
        break;
      case PlayerPosition.cm:
      case PlayerPosition.am:
        shiftThreshold = 0.4;
        break;
      case PlayerPosition.lm:
      case PlayerPosition.rm:
        shiftThreshold = 0.45;
        break;
      case PlayerPosition.lw:
      case PlayerPosition.rw:
        shiftThreshold = 0.35;
        break;
      case PlayerPosition.ss:
      case PlayerPosition.st:
      case PlayerPosition.cf:
        shiftThreshold = 0.15;
        break;
      default:
        shiftThreshold = 0.3;
    }

    if (shiftChance < shiftThreshold) {
      final isTeamOnLeft = gameRef.isTeamOnLeftSide(pit.teamId);

      // Увеличено смещение по X
      if (attacking) {
        xShift = isTeamOnLeft ? 100 : -100; // Было 50
      } else {
        xShift = isTeamOnLeft ? -100 : 100; // Было 50
      }

      final isWidePlayer = [
        PlayerPosition.rb,
        PlayerPosition.lb,
        PlayerPosition.lm,
        PlayerPosition.rm,
        PlayerPosition.lw,
        PlayerPosition.rw,
      ].contains(pit.position);

      // Увеличен диапазон по Y
      final yRange = isWidePlayer ? 80 : 40; // Было 40 и 20
      yShift = (random.nextDouble() - 0.5) * yRange;

      // Опционально: усиление смещения по ролям
      double xShiftMultiplier;
      switch (pit.position) {
        case PlayerPosition.st:
        case PlayerPosition.cf:
        case PlayerPosition.ss:
          xShiftMultiplier = 1.5;
          break;
        case PlayerPosition.lw:
        case PlayerPosition.rw:
          xShiftMultiplier = 1.2;
          break;
        case PlayerPosition.am:
        case PlayerPosition.cm:
          xShiftMultiplier = 1.0;
          break;
        case PlayerPosition.dm:
        case PlayerPosition.cb:
          xShiftMultiplier = 0.8;
          break;
        default:
          xShiftMultiplier = 1.0;
      }
      xShift *= xShiftMultiplier;
    }

    return Vector2(xShift, yShift);
  }

  Vector2 _avoidNearbyOpponents(Vector2 target) {
    final nearbyEnemies = gameRef.players.where((p) => p.pit.teamId != pit.teamId && (p.position - target).length < 40);
    Vector2 avoidance = Vector2.zero();
    for (final enemy in nearbyEnemies) {
      final away = (target - enemy.position).normalized();
      avoidance += away * 20;
    }
    return target + avoidance;
  }

  // ====================== Вспомогательные методы ======================

  /// Поиск лучшего партнера для паса
  PlayerComponent? _findBestTeammate() {
    final teammates = gameRef.players.where((p) => p.pit.teamId == pit.teamId && p != this);
    PlayerComponent? best;
    double bestScore = -1;

    final goalPos = _getOpponentGoal().position;
    final goalDistNow = (goalPos - position).length;

    for (final t in teammates) {
      final score = _calculateTeammateScore(t, goalPos, goalDistNow);
      if (score > bestScore) {
        bestScore = score;
        best = t;
      }
    }
    return best;
  }

  /// Расчет "полезности" партнера для паса
  double _calculateTeammateScore(PlayerComponent t, Vector2 goalPos, double goalDistNow) {
    final toTeammate = t.position - position;
    final dist = toTeammate.length;
    final goalDistThen = (goalPos - t.position).length;
    final goalDir = goalPos - position;
    final angle = goalDir.angleTo(toTeammate).abs();
    final distScore = 1 - (dist - 150).abs() / 150;
    final angleScore = 1 - angle / (pi / 2);
    final progressScore = goalDistThen < goalDistNow ? 1.0 : 0.0;
    return distScore * 0.4 + angleScore * 0.3 + progressScore * 0.3;
  }

  /// Проверка безопасности паса
  bool _isPassSafe(Vector2 from, Vector2 to) {
    final passSkill = pit.data.stats.lowPass / 100;
    final adjustedTolerance = 25 + 20 * (1 - passSkill);
    return !gameRef.players.any(
      (enemy) => enemy.pit.teamId != pit.teamId && _isInInterceptionZone(enemy, from, to, adjustedTolerance),
    );
  }

  /// Проверка зоны перехвата паса/удара
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

  /// Получение координат ворот противника
  GoalComponent _getOpponentGoal() {
    final isTeamOnLeft = gameRef.isTeamOnLeftSide(pit.teamId);
    return isTeamOnLeft ? gameRef.rightGoal : gameRef.leftGoal;
  }

  /// Ограничение позиции в пределах поля
  void _clampPosition() {
    position.x = position.x.clamp(radius, gameRef.size.x - radius);
    position.y = position.y.clamp(radius, gameRef.size.y - radius);
  }

  /// Расчет домашней позиции игрока в зависимости от роли
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

  bool _randomSkipPassDecision() {
    return gameRef.random.nextDouble() < 0.1;
  }

  // ====================== Отрисовка игрока ======================

  @override
  void render(Canvas canvas) {
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(Offset(2, 3), radius * 0.95, shadowPaint);

    final outlinePaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset.zero, radius + 2.0, outlinePaint);

    final fillPaint = Paint()..color = pit.teamId == gameRef.teamA.id ? gameRef.teamA.color : gameRef.teamB.color;
    canvas.drawCircle(Offset.zero, radius, fillPaint);

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
