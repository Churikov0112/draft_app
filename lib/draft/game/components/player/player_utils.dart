import 'package:flame/components.dart';

import '../goal_component.dart';
import 'player_component.dart';

extension PlayerUtils on PlayerComponent {
  bool isAttackingTeam() => ball?.owner?.pit.teamId == pit.teamId;
  bool isOnOwnHalf() => gameRef.isOwnHalf(pit.teamId, position);

  GoalComponent getOpponentGoal() {
    final isTeamOnLeft = gameRef.isTeamOnLeftSide(pit.teamId);
    return isTeamOnLeft ? gameRef.rightGoal : gameRef.leftGoal;
  }

  String getFieldZone(Vector2 position, Vector2 goalPos, double fieldLength) {
    final distToGoal = (goalPos - position).length;
    final attackingZoneThreshold = fieldLength * 0.3;
    final defensiveZoneThreshold = fieldLength * 0.7;

    if (distToGoal < attackingZoneThreshold) return 'attacking';
    if (distToGoal > defensiveZoneThreshold) return 'defensive';
    return 'middle';
  }
}
