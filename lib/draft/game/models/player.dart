enum PlayerPosition {
  gk, // Вратарь
  cb, // Центральный защитник
  lb, // Левый защитник
  rb, // Правый защитник
  dm, // Опорный полузащитник
  cm, // Центральный полузащитник
  am, // Атакующий полузащитник
  lm, // Левый полузащитник
  rm, // Правый полузащитник
  lw, // Левый вингер
  rw, // Правый вингер
  cf, // Центральный форвард
  ss, // Оттянутый форвард
  st, // Нападающий
}

class PlayerStats {
  final double maxSpeed; // Максимальная скорость
  final double lowPass; // Точность паса
  final double shoots; // Сила и точность ударов
  final double defence; // Навыки защиты
  final double dribbling; // Дриблинг
  final double goalkeeper; // Дриблинг

  PlayerStats({
    required this.maxSpeed,
    required this.lowPass,
    required this.shoots,
    required this.defence,
    required this.dribbling,
    required this.goalkeeper,
  });
}

class PlayerInTeamModel {
  final PlayerModel data;
  final int number;
  final PlayerPosition position;
  final String teamId;

  PlayerInTeamModel({required this.teamId, required this.number, required this.position, required this.data});
}

class PlayerModel {
  final String id;
  final String name;
  final PlayerStats stats;
  final PlayerPosition usualPosition;

  PlayerModel({required this.id, required this.name, required this.usualPosition, required this.stats});
}
