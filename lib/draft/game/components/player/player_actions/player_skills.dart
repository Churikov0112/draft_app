// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'dart:math';

import '../../../models/player.dart';
import '../../goal_component.dart';
import '../player_component.dart';
import '../player_state.dart';
import '../player_utils.dart';
import 'player_ball_control.dart';
import 'player_decision_making.dart';

extension PlayerSkills on PlayerComponent {
  double calculatePassScore(double time, GoalComponent goal, FieldZone fieldZone) {
    if (!shouldPass(time)) return -1.0;
    final teammate = findBestTeammate();
    if (teammate == null) return -1.0;

    final passTarget = calculatePassTarget(teammate);
    if (!isPassSafe(position, passTarget)) return -1.0;

    final zoneWeight = getZoneWeight(fieldZone);
    final roleModifier = getRoleModifier();
    final _isThreatened = isThreatened(goal);
    final threatFactor = _isThreatened ? 1.2 : 1.0;
    final passSkill = pit.data.stats.lowPass / 100;
    final goalDistNow = (goal.center - position).length;
    final goalDistThen = (goal.center - teammate.position).length;
    final progressScore = goalDistThen < goalDistNow ? 1.0 : 0.5;

    return zoneWeight * roleModifier * (0.4 * passSkill + 0.3 * progressScore + 0.3 * threatFactor);
  }

  double calculateDribbleScore(GoalComponent goal, FieldZone fieldZone) {
    final _isThreatened = isThreatened(goal);
    final dribblingSkill = pit.data.stats.dribbling / 100;
    final zoneWeight = getZoneWeight(fieldZone);
    final roleModifier = getDribbleRoleModifier();
    final threatFactor = _isThreatened ? 0.7 : 1.0;
    return zoneWeight * roleModifier * (0.6 * dribblingSkill + 0.4 * threatFactor);
  }

  double calculateShootScore(double distToGoal, FieldZone fieldZone) {
    final shootThreshold = 200.0;
    if (isOnOwnHalf() || distToGoal > shootThreshold) return -1.0;

    final zoneWeight = getShootZoneWeight(fieldZone, distToGoal);
    final roleModifier = getShootRoleModifier();
    final shootSkill = pit.data.stats.shoots / 100;
    final distanceFactor = pow(1.0 - (distToGoal / shootThreshold), 2);
    final threatFactor = isThreatened(getOpponentGoal()) ? 0.8 : 1.5;

    return zoneWeight * roleModifier * (0.5 * shootSkill + 0.3 * distanceFactor + 0.2 * threatFactor);
  }

  double getZoneWeight(FieldZone fieldZone) {
    switch (fieldZone) {
      case FieldZone.defensive:
        return 0.95;
      case FieldZone.middle:
        return 0.75;
      case FieldZone.attacking:
        return 0.4;
    }
  }

  double getShootZoneWeight(FieldZone fieldZone, double distToGoal) {
    switch (fieldZone) {
      case FieldZone.defensive:
        return 0.0;
      case FieldZone.middle:
        return 0.05;
      case FieldZone.attacking:
        return distToGoal < 50 ? 1.2 : 0.9;
    }
  }

  double getRoleModifier() {
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

  double getDribbleRoleModifier() {
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

  double getShootRoleModifier() {
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
}
