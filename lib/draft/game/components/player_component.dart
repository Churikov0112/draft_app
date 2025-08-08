import 'dart:math';

import 'package:draft_app/draft/game/models/player.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';
import 'goal_component.dart';

/// Компонент игрока
class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  // Константы
  static const double playerRadius = 14.0; // Радиус игрока
  static const double stealCooldown = 1.0; // Время между попытками отбора
  static const double passCooldown = 2.0; // Время между передачами

  final PlayerInTeamModel pit;

  double radius = playerRadius; // Физический радиус
  Vector2 velocity = Vector2.zero(); // Текущая скорость
  BallComponent? ball; // Ссылка на мяч

  // Таймеры
  double _lastStealTime = 0; // Время последнего отбора
  double _lastPassTime = 0; // Время последней передачи

  double _dt = 0;

  PlayerComponent({required this.pit, Vector2? position})
    : super(position: position ?? Vector2.zero(), size: Vector2.all(28));

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

    _handleBallInteraction();
    _clampPosition();
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
    final attackingZoneThreshold = fieldLength * 0.3; // Ближе 30% к воротам соперника
    final defensiveZoneThreshold = fieldLength * 0.7; // Дальше 70% от ворот соперника

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

    // Рассчитываем баллы для каждого действия
    final passScore = _calculatePassScore(time, goal, fieldZone);
    final dribbleScore = _calculateDribbleScore(goal, fieldZone);
    final shootScore = _calculateShootScore(distToGoal, fieldZone);

    // Выбираем действие с наивысшим баллом
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

    // По умолчанию дриблинг
    _moveWithBall(dirToGoal);
  }

  /// Расчет балла для паса
  double _calculatePassScore(double time, GoalComponent goal, String fieldZone) {
    if (!_shouldPass(time)) return -1.0; // Пас невозможен, если не истек кулдаун

    final teammate = _findBestTeammate();
    if (teammate == null) return -1.0; // Нет подходящего партнера

    final passTarget = _calculatePassTarget(teammate);
    if (!_isPassSafe(position, passTarget)) return -1.0; // Пас небезопасен

    // Базовый балл в зависимости от зоны
    double zoneWeight;
    switch (fieldZone) {
      case 'defensive':
        zoneWeight = 0.95; // Пас сильно предпочтителен в защите
        break;
      case 'middle':
        zoneWeight = 0.75; // Пас важен в центре
        break;
      case 'attacking':
        zoneWeight = 0.4; // Пас менее приоритетен в атаке
        break;
      default:
        zoneWeight = 0.5;
    }

    // Модификатор на основе роли
    double roleModifier;
    switch (pit.role) {
      case PlayerRole.defender:
        roleModifier = 1.2; // Защитники склонны к пасам
        break;
      case PlayerRole.midfielder:
        roleModifier = 1.0; // Полузащитники нейтральны
        break;
      case PlayerRole.forward:
        roleModifier = 0.8; // Нападающие менее склонны к пасам
        break;
    }

    // Учитываем угрозу и навыки паса
    final isThreatened = _isThreatened(goal);
    final threatFactor = isThreatened ? 1.2 : 1.0; // Увеличиваем приоритет паса под давлением
    final passSkill = pit.data.stats.lowPass / 100;

    // Учитываем прогресс к воротам
    final goalDistNow = (goal.center - position).length;
    final goalDistThen = (goal.center - teammate.position).length;
    final progressScore = goalDistThen < goalDistNow ? 1.0 : 0.5;

    return zoneWeight * roleModifier * (0.4 * passSkill + 0.3 * progressScore + 0.3 * threatFactor);
  }

  /// Расчет балла для дриблинга
  double _calculateDribbleScore(GoalComponent goal, String fieldZone) {
    final isThreatened = _isThreatened(goal);
    final dribblingSkill = pit.data.stats.dribbling / 100;

    // Базовый балл в зависимости от зоны
    double zoneWeight;
    switch (fieldZone) {
      case 'defensive':
        zoneWeight = 0.2; // Дриблинг опасен в защите
        break;
      case 'middle':
        zoneWeight = 0.65; // Дриблинг полезен в центре
        break;
      case 'attacking':
        zoneWeight = 0.8; // Дриблинг хорош в атаке
        break;
      default:
        zoneWeight = 0.5;
    }

    // Модификатор на основе роли
    double roleModifier;
    switch (pit.role) {
      case PlayerRole.defender:
        roleModifier = 0.8; // Защитники реже дриблят
        break;
      case PlayerRole.midfielder:
        roleModifier = 1.0; // Полузащитники нейтральны
        break;
      case PlayerRole.forward:
        roleModifier = 1.2; // Нападающие склонны к дриблингу
        break;
    }

    // Уменьшаем балл при угрозе
    final threatFactor = isThreatened ? 0.7 : 1.0;

    return zoneWeight * roleModifier * (0.6 * dribblingSkill + 0.4 * threatFactor);
  }

  /// Расчет балла для удара
  double _calculateShootScore(double distToGoal, String fieldZone) {
    // Запрещаем удары со своей половины поля
    if (_isOnOwnHalf()) return -1.0;

    final shootThreshold = 150.0; // Фиксированный порог 150 пикселей
    if (distToGoal > shootThreshold) return -1.0; // Слишком далеко для удара

    // Базовый балл в зависимости от зоны
    double zoneWeight;
    switch (fieldZone) {
      case 'defensive':
        zoneWeight = 0.0; // Удары невозможны в защите
        break;
      case 'middle':
        zoneWeight = 0.05; // Удары крайне редки в центре
        break;
      case 'attacking':
        zoneWeight = 0.9; // Удары предпочтительны в атаке
        break;
      default:
        zoneWeight = 0.5;
    }

    // Модификатор на основе роли
    double roleModifier;
    switch (pit.role) {
      case PlayerRole.defender:
        roleModifier = 0.4; // Защитники редко бьют
        break;
      case PlayerRole.midfielder:
        roleModifier = 0.9; // Полузащитники умеренно бьют
        break;
      case PlayerRole.forward:
        roleModifier = 1.3; // Нападающие склонны к ударам
        break;
    }

    // Учитываем навыки удара и расстояние
    final shootSkill = pit.data.stats.shoots / 100;
    final distanceFactor = 1.0 - (distToGoal / shootThreshold); // Ближе к воротам — выше балл

    return zoneWeight * roleModifier * (0.6 * shootSkill + 0.4 * distanceFactor);
  }

  /// Выбор лучшего действия
  String _selectBestAction(double passScore, double dribbleScore, double shootScore) {
    // Добавляем небольшой случайный шанс для нехарактерных действий
    final randomFactor = gameRef.random.nextDouble();
    if (randomFactor < 0.02) {
      // 2% шанс выбрать случайное действие
      final actions = _isOnOwnHalf() ? ['pass', 'dribble'] : ['pass', 'dribble', 'shoot'];
      return actions[gameRef.random.nextInt(actions.length)];
    }

    if (passScore >= dribbleScore && passScore >= shootScore) return 'pass';
    if (shootScore >= passScore && shootScore >= dribbleScore) return 'shoot';
    return 'dribble';
  }

  /// Проверка, нужно ли делать пас
  bool _shouldPass(double time) {
    final cooldown = passCooldown * (pit.role == PlayerRole.defender ? 0.5 : 1.0);
    return (time - _lastPassTime) > cooldown && _isThreatened(_getOpponentGoal());
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

    // Изначальный пас с упреждением
    Vector2 predictedPos = teammate.position + (teammate.velocity * leadFactor);

    // Попытаемся найти свободную точку рядом с predictedPos
    final freeSpot = _findFreeZoneNear(predictedPos);

    return freeSpot;
  }

  Vector2 _findFreeZoneNear(Vector2 pos, {double radius = 50, int attempts = 10}) {
    final random = gameRef.random;

    for (int i = 0; i < attempts; i++) {
      // Случайное смещение в радиусе
      final offset =
          Vector2(random.nextDouble() * 2 - 1, random.nextDouble() * 2 - 1).normalized() * random.nextDouble() * radius;
      final testPos = pos + offset;

      // Проверяем, нет ли рядом соперников в зоне 30 пикселей
      final safe = !gameRef.players.any((p) => p.pit.teamId != pit.teamId && (p.position - testPos).length < 30);

      if (safe) {
        return testPos;
      }
    }

    // Если не нашли безопасную зону, возвращаем исходную позицию
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
    final speedPenalty = isThreatened ? 0.2 : 0.1; // Базовое замедление при ведении
    final baseSpeedFactor = speedFactor ?? (1.0 - speedPenalty * (1.0 - dribblingSkill));

    final moveDir = isThreatened
        ? _getEvadeDirection(dirToGoal) // Уклонение при угрозе
        : dirToGoal; // Движение прямо к воротам

    velocity = moveDir * pit.data.stats.maxSpeed * baseSpeedFactor;
    position += velocity * _dt;
    ball!.position = position + moveDir * (radius + ball!.radius + 1);
  }

  /// Расчет направления для уклонения
  Vector2 _getEvadeDirection(Vector2 dirToGoal) {
    final dribblingSkill = pit.data.stats.dribbling / 100;
    final evadeStrength = 0.5 + 0.5 * dribblingSkill; // от 0.5 до 1.0
    final perpendicular = Vector2(-dirToGoal.y, dirToGoal.x);
    return (dirToGoal + perpendicular * evadeStrength).normalized();
  }

  /// Удар по воротам
  void _shootAtGoal(Vector2 goalPos, double time) {
    final distToGoal = (goalPos - position).length;
    final fieldZone = _getFieldZone(position, goalPos, gameRef.size.x);
    print(
      "Player ${pit.number} (team ${pit.teamId}, role ${pit.role.toString().split('.').last}) shoots from position (${position.x.toStringAsFixed(1)}, ${position.y.toStringAsFixed(1)}) in zone $fieldZone with distance $distToGoal",
    );

    final shootSkill = pit.data.stats.shoots / 100;
    final goalHeight = 60.0;

    // Вертикальное отклонение (разброс) уменьшается с ростом скилла
    final verticalSpread = goalHeight * 0.5 * (1 - shootSkill);
    final dy = (gameRef.random.nextDouble() - 0.5) * 2 * verticalSpread;
    final target = goalPos + Vector2(0, dy);

    // Сила удара зависит от расстояния и скилла
    final minPower = 400.0;
    final maxPower = 1000.0;
    final distFactor = (distToGoal / 500).clamp(0.0, 1.0); // нормируем в пределах поля

    final power = minPower + (maxPower - minPower) * distFactor * (0.7 + 0.3 * shootSkill);

    if (!_isShotSafe(position, target, ballSpeed: power)) {
      return; // перехват — не бьем
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
        _pressBall(time, distToBall, dirToBall); // Прессинг мяча
      } else {
        _moveToOpenSpace(); // Занимаем свободную позицию
      }
    } else {
      _moveToOpenSpace(); // Возвращаемся на позицию
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

    // Случайный шанс на "внеплановый" прессинг
    final randomChance = gameRef.random.nextDouble();
    final pressThreshold = pit.role == PlayerRole.forward
        ? 0.1
        : pit.role == PlayerRole.midfielder
        ? 0.3
        : 0.5;

    if (randomChance < pressThreshold) {
      return true;
    }

    switch (pit.role) {
      case PlayerRole.defender:
        return true;
      case PlayerRole.midfielder:
        return isOwnHalf || dist < 200;
      case PlayerRole.forward:
        return dist < 150;
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

    // Вероятность успешного отбора зависит от разницы защиты и дриблинга
    final stealChance = (defenceSkill - dribblingSkill + 1.0) / 2.0; // от 0 до 1

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
    final attacking = _isAttackingTeam();
    final ballPos = ball?.position ?? Vector2.zero();

    // Базовая тактическая позиция
    final basePos = getHomePosition();
    final attackShift = _calculateTacticalShift(ballPos, attacking);

    // Добавляем случайное смещение для подключения к атаке или обороне
    final randomShift = _calculateRandomPositionShift(attacking);

    final target = basePos + attackShift + randomShift;

    // Учитываем ближайших соперников — не стоим вплотную к ним
    final safePos = _avoidNearbyOpponents(target);

    final toTarget = safePos - position;
    if (toTarget.length > 4) {
      final speed = attacking ? pit.data.stats.maxSpeed * 0.6 : pit.data.stats.maxSpeed * 0.4;
      velocity = toTarget.normalized() * speed;
      position += velocity * _dt;
    } else {
      velocity = Vector2.zero();
    }
  }

  Vector2 _calculateTacticalShift(Vector2 ballPos, bool attacking) {
    final fieldLength = gameRef.size.x;
    final fieldWidth = gameRef.size.y;

    // Насколько смещаемся к мячу
    final attackBiasX = ((ballPos.x - position.x) / fieldLength) * 80;
    final sideBiasY = ((ballPos.y - position.y) / fieldWidth) * 40;

    // Усиливаем смещение в атаке
    final multiplier = attacking ? 1.0 : 0.3;

    return Vector2(attackBiasX * multiplier, sideBiasY * multiplier);
  }

  Vector2 _calculateRandomPositionShift(bool attacking) {
    final random = gameRef.random;
    double xShift = 0;
    double yShift = 0;

    final shiftChance = random.nextDouble();
    final shiftThreshold = pit.role == PlayerRole.defender
        ? 0.2
        : pit.role == PlayerRole.midfielder
        ? 0.4
        : 0.1;

    if (shiftChance < shiftThreshold) {
      final isTeamOnLeft = gameRef.isTeamOnLeftSide(pit.teamId);

      // Защитники иногда подключаются к атаке, нападающие — отходят назад
      if (attacking) {
        xShift = isTeamOnLeft ? 50 : -50;
      } else {
        xShift = isTeamOnLeft ? -50 : 50;
      }

      yShift = (random.nextDouble() - 0.5) * 20;
    }

    return Vector2(xShift, yShift);
  }

  Vector2 _avoidNearbyOpponents(Vector2 target) {
    final nearbyEnemies = gameRef.players.where((p) => p.pit.teamId != pit.teamId && (p.position - target).length < 40);

    Vector2 avoidance = Vector2.zero();
    for (final enemy in nearbyEnemies) {
      final away = (target - enemy.position).normalized();
      avoidance += away * 20; // отталкиваемся от противников
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

    final distScore = 1 - (dist - 150).abs() / 150; // Оптимальная дистанция - 150px
    final angleScore = 1 - angle / (pi / 2); // Лучше перпендикулярные пасы
    final progressScore = goalDistThen < goalDistNow ? 1.0 : 0.0; // Движение к воротам

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

    // 🎯 Чем выше скорость мяча, тем меньше шанс перехвата (меньше зона)
    final speedFactor = (1 / (ballSpeed / 400)).clamp(0.3, 1.0); // быстро → 0.3, медленно → 1.0
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

    double xZone;

    switch (pit.role) {
      case PlayerRole.defender:
        xZone = isLeft ? fieldSize.x * 0.2 : fieldSize.x * 0.8;
        break;
      case PlayerRole.midfielder:
        xZone = isLeft ? fieldSize.x * 0.4 : fieldSize.x * 0.6;
        break;
      case PlayerRole.forward:
        xZone = isLeft ? fieldSize.x * 0.65 : fieldSize.x * 0.35;
        break;
    }

    final spacing = fieldSize.y / 6;
    double y = spacing * (pit.number % 6 + 0.5);

    // 🎲 Добавляем случайный сдвиг по вертикали ±10
    y += (gameRef.random.nextDouble() - 0.5) * 20;

    return Vector2(xZone, y);
  }

  bool _randomSkipPassDecision() {
    return gameRef.random.nextDouble() < 0.1; // 10% проигнорировать пас
  }

  // ====================== Отрисовка игрока ======================

  @override
  void render(Canvas canvas) {
    // Тень
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(Offset(2, 3), radius * 0.95, shadowPaint);

    // Контур
    final outlinePaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset.zero, radius + 2.0, outlinePaint);

    // Основной цвет (синий/желтый в зависимости от команды)

    final fillPaint = Paint()..color = pit.teamId == gameRef.teamA.id ? gameRef.teamA.color : gameRef.teamB.color;
    canvas.drawCircle(Offset.zero, radius, fillPaint);

    // Номер игрока
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
