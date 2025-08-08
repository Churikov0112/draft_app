import 'dart:ui';

import 'player.dart';

class TeamModel {
  final String id;
  final String name;
  final Color color;
  final List<PlayerInTeamModel> startingPlayers; // Стартовый состав (11 игроков)
  final List<PlayerInTeamModel> substitutes; // Запасные (до 7 игроков)
  final List<PlayerInTeamModel> reserves; // Резервные (если нужны)

  TeamModel({
    required this.id,
    required this.name,
    required this.color,
    required this.startingPlayers,
    this.substitutes = const [],
    this.reserves = const [],
  });

  // Переключить игрока между стартовым составом и запасными
  void substitute(PlayerInTeamModel fromStart, PlayerInTeamModel toStart) {
    if (startingPlayers.contains(fromStart) && substitutes.contains(toStart)) {
      startingPlayers.remove(fromStart);
      substitutes.remove(toStart);
      startingPlayers.add(toStart);
      substitutes.add(fromStart);
    }
  }

  // Получить всех игроков команды (стартовые + запасные)
  List<PlayerInTeamModel> getAllPlayers() => [...startingPlayers, ...substitutes, ...reserves];
}
