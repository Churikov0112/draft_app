import 'dart:math';

import 'package:flame/components.dart';

import '../../goal_component.dart';
import '../player_component.dart';
import '../player_utils.dart';

extension PlayerDecisionMaking on PlayerComponent {
  String selectBestAction(double passScore, double dribbleScore, double shootScore, GoalComponent goal) {
    final randomFactor = gameRef.random.nextDouble();
    if (randomFactor < 0.02) {
      final actions = isOnOwnHalf() ? ['pass', 'dribble'] : ['pass', 'dribble', 'shoot'];
      return actions[gameRef.random.nextInt(actions.length)];
    }

    final teammate = findBestTeammate();
    if (teammate != null) {
      final goalDistNow = (goal.center - position).length;
      final goalDistThen = (goal.center - teammate.position).length;
      if (goalDistThen < goalDistNow && passScore >= 0) passScore += 0.2;
    }

    if (passScore >= dribbleScore && passScore >= shootScore) return 'pass';
    if (shootScore >= passScore && shootScore >= dribbleScore) return 'shoot';
    return 'dribble';
  }

  PlayerComponent? findBestTeammate() {
    final teammates = gameRef.players.where((p) => p.pit.teamId == pit.teamId && p != this);
    PlayerComponent? best;
    double bestScore = -1;

    final goalPos = getOpponentGoal().center;
    final goalDistNow = (goalPos - position).length;

    for (final t in teammates) {
      final score = calculateTeammateScore(t, goalPos, goalDistNow);
      if (score > bestScore && score > 0.5) {
        bestScore = score;
        best = t as PlayerComponent?;
      }
    }
    return best;
  }

  double calculateTeammateScore(PlayerComponent t, Vector2 goalPos, double goalDistNow) {
    final toTeammate = t.position - position;
    final dist = toTeammate.length;
    final goalDistThen = (goalPos - t.position).length;
    final goalDir = goalPos - position;
    final angle = goalDir.angleTo(toTeammate).abs();
    final distScore = 1 - (dist - 150).abs() / 150;
    final angleScore = 1 - angle / (pi / 2);
    final progressScore = goalDistThen < goalDistNow ? 1.0 : 0.0;
    final nearestOpponentDist = getNearestOpponentTo(t.position).length;
    final safetyScore = nearestOpponentDist > 50 ? 1.0 : 0.5;
    return distScore * 0.3 + angleScore * 0.3 + progressScore * 0.2 + safetyScore * 0.2;
  }

  Vector2 getNearestOpponentTo(Vector2 pos) {
    final opponents = gameRef.players.where((p) => p.pit.teamId != pit.teamId);
    Vector2 nearest = Vector2.zero();
    double minDist = double.infinity;
    for (final o in opponents) {
      final dist = (o.position - pos).length;
      if (dist < minDist) {
        minDist = dist;
        nearest = o.position;
      }
    }
    return nearest;
  }
}
