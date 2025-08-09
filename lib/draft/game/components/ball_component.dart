import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'player_component.dart';

class BallComponent extends PositionComponent with HasGameRef<MatchGame> {
  final double radius = 6.0;
  Vector2 velocity = Vector2.zero();
  PlayerComponent? owner;
  double lastKickTime = 0;

  double lastOwnershipTime = 0.0;

  BallComponent({required Vector2 position}) : super(position: position, size: Vector2.all(12));

  List<PlayerComponent> allPlayers = [];

  void assignPlayers(List<PlayerComponent> players) {
    allPlayers = players;
  }

  void kickTowards(Vector2 target, double power, double currentTime, PlayerComponent kicker) {
    final dir = (target - position).normalized();
    velocity = dir * power;
    owner = null;
    lastKickTime = currentTime;
  }

  void takeOwnership(PlayerComponent owner) {
    this.owner = owner;
    lastOwnershipTime = gameRef.elapsedTime;
  }

  bool canBeKickedBy(PlayerComponent player, double currentTime) {
    return owner == null || (owner != player && (currentTime - lastKickTime) > 0.5);
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (owner == null) {
      position += velocity * dt;
      velocity *= 0.96; // трение

      if (velocity.length < 1) {
        velocity = Vector2.zero();
      }
    }
  }

  @override
  void render(Canvas canvas) {
    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.2);
    canvas.drawCircle(Offset(2, 3), radius * 0.95, shadowPaint);

    final ballPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset.zero, radius, ballPaint);

    final stripePaint = Paint()..color = Colors.black;
    canvas.drawLine(Offset(-radius + 2, 0), Offset(radius - 2, 0), stripePaint);
  }
}
