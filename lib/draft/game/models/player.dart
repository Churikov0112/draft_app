// enum PlayerPosition {
//   gk, // Вратарь
//   cb, // Центральный защитник
//   lb, // Левый защитник
//   rb, // Правый защитник
//   dm, // Опорный полузащитник
//   cm, // Центральный полузащитник
//   am, // Атакующий полузащитник
//   lm, // Левый полузащитник
//   rm, // Правый полузащитник
//   lw, // Левый вингер
//   rw, // Правый вингер
//   cf, // Центральный форвард
//   ss, // Оттянутый форвард
//   st, // Нападающий
// }

enum PlayerRole { forward, midfielder, defender }

class PlayerStats {
  final double maxSpeed; // Максимальная скорость
  final double lowPass; // Точность паса
  final double shoots; // Сила и точность ударов
  final double defence; // Навыки защиты
  final double dribbling; // Дриблинг

  PlayerStats({
    required this.maxSpeed,
    required this.lowPass,
    required this.shoots,
    required this.defence,
    required this.dribbling,
  });
}

class PlayerInTeamModel {
  final PlayerModel data;
  final int number;
  final PlayerRole role;
  final String teamId;

  PlayerInTeamModel({required this.teamId, required this.number, required this.role, required this.data});
}

class PlayerModel {
  final String id;
  final String name;
  final PlayerStats stats;
  // final PlayerPosition usualPosition;

  PlayerModel({required this.id, required this.name, required this.stats});
}
