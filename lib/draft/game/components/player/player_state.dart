import 'package:flame/components.dart';

import 'player_component.dart';

enum TeamState { attack, defence, counter, neutral }

enum FieldZone { attacking, defensive, middle }

extension PlayerState on PlayerComponent {
  void updateTeamState() {
    final ballOwnerTeam = ball?.owner?.pit.teamId;
    if (ballOwnerTeam == pit.teamId) {
      teamState = TeamState.attack;
    } else if (ballOwnerTeam == null) {
      teamState = TeamState.neutral;
    } else {
      teamState = isCounterAttackOpportunity() ? TeamState.counter : TeamState.defence;
    }
  }

  bool isCounterAttackOpportunity() {
    final ballPos = ball?.position ?? Vector2.zero();
    final isInMiddle = ballPos.x > gameRef.size.x * 0.3 && ballPos.x < gameRef.size.x * 0.7;
    final hasFastPlayers = pit.data.stats.maxSpeed > 70;
    return isInMiddle && hasFastPlayers;
  }

  bool isAttackingTeam() => ball?.owner?.pit.teamId == pit.teamId;
}
