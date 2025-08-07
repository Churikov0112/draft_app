import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';
import 'player_component.dart';

class BallComponent extends PositionComponent with HasGameRef<MatchGame> {
  Vector2 velocity = Vector2.zero();
  double radius = 6.0;
  PlayerComponent? playerA;
  PlayerComponent? playerB;

  BallComponent({Vector2? position}) : super(position: position ?? Vector2.zero(), size: Vector2.all(12));

  PlayerComponent? owner;
  double lastKickTime = 0; // время последнего удара
  final double kickCooldown = 0.5; // сек

  void takeOwnership(PlayerComponent player) {
    owner = player;
    velocity = Vector2.zero();
  }

  bool canBeKickedBy(PlayerComponent player, double gameTime) {
    // Если это попытка пнуть мяч — проверяем cooldown
    if (gameTime - lastKickTime < kickCooldown) return false;

    return true;
  }

  void kickTowards(Vector2 point, double force, double gameTime, PlayerComponent kicker) {
    final dir = (point - position).normalized();
    velocity = dir * force;
    owner = null;
    lastKickTime = gameTime;
  }

  void assignPlayers(PlayerComponent a, PlayerComponent b) {
    playerA = a;
    playerB = b;
  }

  @override
  void update(double dt) {
    super.update(dt);
    position += velocity * dt;

    // трение
    velocity *= 0.98;
    if (velocity.length2 < 0.01) velocity.setZero();

    // отскок от краёв экрана
    if (position.x - radius < 0) {
      position.x = radius;
      velocity.x *= -1;
    }
    if (position.x + radius > gameRef.size.x) {
      position.x = gameRef.size.x - radius;
      velocity.x *= -1;
    }
    if (position.y - radius < 0) {
      position.y = radius;
      velocity.y *= -1;
    }
    if (position.y + radius > gameRef.size.y) {
      position.y = gameRef.size.y - radius;
      velocity.y *= -1;
    }
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset.zero, radius, paint);
  }
}
