import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'ball_component.dart';
import 'goal_component.dart';

/// Роли игроков на поле
enum PlayerRole { forward, midfielder, defender }

/// Статистика игрока (все значения от 0 до 100)
class PlayerStats {
  final double maxSpeed; // Максимальная скорость
  final double lowPass; // Точность паса
  final double shoots; // Сила и точность ударов
  final double defence; // Навыки защиты
  final double dribbling; //  дриблинг

  PlayerStats({
    required this.maxSpeed,
    required this.lowPass,
    required this.shoots,
    required this.defence,
    required this.dribbling,
  });
}

/// Компонент игрока
class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  // Константы
  static const double playerRadius = 14.0; // Радиус игрока
  static const double stealCooldown = 1.0; // Время между попытками отбора
  static const double passCooldown = 2.0; // Время между передачами

  final int number; // Номер игрока
  final int team; // Команда (0 или 1)
  final PlayerRole role; // Роль на поле
  final PlayerStats stats; // Характеристики

  double radius = playerRadius; // Физический радиус
  Vector2 velocity = Vector2.zero(); // Текущая скорость
  BallComponent? ball; // Ссылка на мяч

  // Таймеры
  double _lastStealTime = 0; // Время последнего отбора
  double _lastPassTime = 0; // Время последней передачи

  double _dt = 0;

  PlayerComponent({
    required this.number,
    required this.team,
    required this.role,
    required this.stats,
    Vector2? position,
  }) : super(position: position ?? Vector2.zero(), size: Vector2.all(28));

  /// Установка ссылки на мяч
  void assignBallRef(BallComponent b) => ball = b;

  bool _isAttackingTeam() => ball?.owner?.team == team;

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

  /// Обработка ситуации, когда игрок владеет мячом
  void _handleBallPossession({required double time}) {
    final goal = _getOpponentGoal();
    final goalPos = goal.position;
    final dirToGoal = (goalPos - position).normalized();
    final distToGoal = (goalPos - position).length;

    // Для защитников чаще делать пас, реже дриблить
    if (role == PlayerRole.defender) {
      // Если можно сделать пас, пытаемся сделать пас
      if (_shouldPass(time) && _attemptPass(time)) {
        return;
      }

      // Если нет возможности паса, то только тогда пытаемся дриблить
      // Но с меньшей скоростью и меньшим приоритетом
      final shootThreshold = 80 + 150 * (stats.shoots / 100); // чуть меньшая дистанция для удара
      if (distToGoal < shootThreshold) {
        _shootAtGoal(goalPos, time);
        return;
      }

      // Защитники двигаются с мячом осторожнее — с меньшей скоростью
      _moveWithBall(dirToGoal);
    } else {
      // Для остальных роль оставляем без изменений

      if (_shouldPass(time) && _attemptPass(time)) {
        return;
      }

      _moveWithBall(dirToGoal);

      final shootThreshold = 100 + 200 * (stats.shoots / 100);
      if (distToGoal < shootThreshold) {
        _shootAtGoal(goalPos, time);
      }
    }
  }

  /// Проверка, нужно ли делать пас
  bool _shouldPass(double time) {
    final cooldown = (role == PlayerRole.defender) ? passCooldown * 0.5 : passCooldown;
    return (time - _lastPassTime) > cooldown && _isThreatened(_getOpponentGoal());
  }

  /// Проверка наличия угрозы от соперников
  bool _isThreatened(GoalComponent goal) {
    final dirToGoal = (goal.position - position).normalized();
    return gameRef.players.any((enemy) => enemy.team != team && _isInThreatZone(enemy, dirToGoal));
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
    print("Player $number passed to ${teammate.number}");
  }

  /// Расчет цели для паса с упреждением
  Vector2 _calculatePassTarget(PlayerComponent teammate) {
    final leadFactor = 0.2 + 0.5 * (stats.lowPass / 100);

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
      final safe = !gameRef.players.any((p) => p.team != team && (p.position - testPos).length < 30);

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
    final passSkill = stats.lowPass / 100;
    return (basePower * (0.9 + 0.2 * passSkill)).clamp(200, 800);
  }

  /// Перемещение с мячом
  void _moveWithBall(Vector2 dirToGoal, {double? speedFactor}) {
    final isThreatened = _isThreatened(_getOpponentGoal());

    final dribblingSkill = stats.dribbling / 100;
    final speedPenalty = isThreatened ? 0.2 : 0.1; // Базовое замедление при ведении
    final baseSpeedFactor = speedFactor ?? (1.0 - speedPenalty * (1.0 - dribblingSkill));

    final moveDir = isThreatened
        ? _getEvadeDirection(dirToGoal) // Уклонение при угрозе
        : dirToGoal; // Движение прямо к воротам

    velocity = moveDir * stats.maxSpeed * baseSpeedFactor;
    position += velocity * _dt;
    ball!.position = position + moveDir * (radius + ball!.radius + 1);
  }

  /// Расчет направления для уклонения
  Vector2 _getEvadeDirection(Vector2 dirToGoal) {
    final dribblingSkill = stats.dribbling / 100;
    final evadeStrength = 0.5 + 0.5 * dribblingSkill; // от 0.5 до 1.0
    final perpendicular = Vector2(-dirToGoal.y, dirToGoal.x);
    return (dirToGoal + perpendicular * evadeStrength).normalized();
  }

  /// Удар по воротам
  void _shootAtGoal(Vector2 goalPos, double time) {
    // final dirToGoal = (goalPos - position).normalized();
    final distToGoal = (goalPos - position).length;

    final shootSkill = stats.shoots / 100;
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

    ball!.kickTowards(target, power, time, this);
    print("player $number shoots at goal with power ${power.toStringAsFixed(1)}");
  }

  // ====================== Логика преследования мяча ======================

  /// Обработка ситуации, когда мяч у соперника или свободен
  void _handleBallChasing({required double time, required double distToBall, required Vector2 dirToBall}) {
    final isBallFree = ball!.owner == null;
    final isOpponentOwner = ball!.owner != null && ball!.owner!.team != team;

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
    final sameTeam = gameRef.players.where((p) => p.team == team).toList();
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
    final isOwnHalf = (team == 0) ? position.x < gameRef.size.x / 2 : position.x > gameRef.size.x / 2;

    switch (role) {
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
    velocity = moveDir * stats.maxSpeed;
    position += velocity * _dt;

    final defenceSkill = stats.defence / 100;
    final cooldown = stealCooldown * (1.0 - 0.5 * defenceSkill);

    final extendedReach = radius + ball!.radius + 2 + 10 * defenceSkill;

    final ballOwner = ball!.owner;
    final dribblingSkill = (ballOwner?.stats.dribbling ?? 0) / 100;

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
    // final fieldSize = gameRef.size;
    final ballPos = ball?.position ?? Vector2.zero();

    // Базовая тактическая позиция (сместим ее в сторону атаки)
    final basePos = getHomePosition();
    final attackShift = _calculateTacticalShift(ballPos, attacking);

    final target = basePos + attackShift;

    // Учитываем ближайших соперников — не стоим вплотную к ним
    final safePos = _avoidNearbyOpponents(target);

    final toTarget = safePos - position;
    if (toTarget.length > 4) {
      final speed = attacking ? stats.maxSpeed * 0.6 : stats.maxSpeed * 0.4;
      velocity = toTarget.normalized() * speed;
      position += velocity * _dt;
    } else {
      velocity = Vector2.zero();
    }
  }

  Vector2 _calculateTacticalShift(Vector2 ballPos, bool attacking) {
    final fieldLength = gameRef.size.x;
    final fieldWidth = gameRef.size.y;

    // Насколько смещаемся к атаке
    final attackBiasX = ((ballPos.x - position.x) / fieldLength) * 80;
    final sideBiasY = ((ballPos.y - position.y) / fieldWidth) * 40;

    // Усиливаем смещение в атаке
    final multiplier = attacking ? 1.0 : 0.3;

    return Vector2(attackBiasX * multiplier, sideBiasY * multiplier);
  }

  Vector2 _avoidNearbyOpponents(Vector2 target) {
    final nearbyEnemies = gameRef.players.where((p) => p.team != team && (p.position - target).length < 40);

    Vector2 avoidance = Vector2.zero();
    for (final enemy in nearbyEnemies) {
      final away = (target - enemy.position).normalized();
      avoidance += away * 20; // отталкиваемся от противников
    }

    return target + avoidance;
  }

  /// Смещение позиции при атаке — для создания глубины и ширины
  Vector2 _getAttackBias() {
    final fieldWidth = gameRef.size.y;
    final fieldLength = gameRef.size.x;

    double xOffset = 0;
    double yOffset = 0;

    switch (role) {
      case PlayerRole.defender:
        xOffset = 20;
        break;
      case PlayerRole.midfielder:
        xOffset = 60;
        yOffset = (number % 2 == 0 ? -1 : 1) * 30; // немного растянуть по ширине
        break;
      case PlayerRole.forward:
        xOffset = 100;
        yOffset = (number % 3 - 1) * 40; // -1, 0, 1 → для разнообразия
        break;
    }

    if (team == 1) xOffset = -xOffset;

    final result = Vector2(xOffset, yOffset);
    result.clamp(Vector2(-fieldLength * 0.1, -fieldWidth * 0.4), Vector2(fieldLength * 0.1, fieldWidth * 0.4));
    return result;
  }

  // ====================== Вспомогательные методы ======================

  /// Поиск ближайшего соперника
  PlayerComponent _findClosestEnemy() {
    return gameRef.players
        .where((p) => p.team != team)
        .reduce((a, b) => (a.position - position).length < (b.position - position).length ? a : b);
  }

  /// Поиск лучшего партнера для паса
  PlayerComponent? _findBestTeammate() {
    final teammates = gameRef.players.where((p) => p.team == team && p != this);
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
    final passSkill = stats.lowPass / 100;
    final adjustedTolerance = 25 + 20 * (1 - passSkill);

    return !gameRef.players.any(
      (enemy) => enemy.team != team && _isInPassInterceptionZone(enemy, from, to, adjustedTolerance),
    );
  }

  /// Проверка зоны перехвата паса
  bool _isInPassInterceptionZone(PlayerComponent enemy, Vector2 from, Vector2 to, double tolerance) {
    final toEnemy = enemy.position - from;
    final toTarget = to - from;
    final proj = toEnemy.dot(toTarget.normalized());
    if (proj < 0 || proj > toTarget.length) return false;

    final perpendicular = toEnemy - toTarget.normalized() * proj;
    return perpendicular.length < tolerance;
  }

  /// Получение координат ворот противника
  GoalComponent _getOpponentGoal() {
    return team == 0 ? gameRef.rightGoal : gameRef.leftGoal;
  }

  /// Ограничение позиции в пределах поля
  void _clampPosition() {
    position.x = position.x.clamp(radius, gameRef.size.x - radius);
    position.y = position.y.clamp(radius, gameRef.size.y - radius);
  }

  /// Расчет домашней позиции игрока в зависимости от роли
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
    final fillPaint = Paint()..color = (team == 0 ? Colors.blue : Colors.yellow);
    canvas.drawCircle(Offset.zero, radius, fillPaint);

    // Номер игрока
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
