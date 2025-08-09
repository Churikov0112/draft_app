import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../../match_game.dart';
import '../../models/player.dart';
import '../ball_component.dart';
import 'player_actions/player_ball_control.dart';
import 'player_actions/player_movement.dart';
import 'player_render.dart';
import 'player_state.dart';

class PlayerComponent extends PositionComponent with HasGameRef<MatchGame> {
  // Constants
  final double radius = 14.0;
  final double stealCooldown = 2.0;
  final double passCooldown = 2.0;

  // Player properties
  final PlayerInTeamModel pit;
  Vector2 velocity = Vector2.zero();
  BallComponent? ball;

  // Timers
  double lastStealTime = 0;
  double lastPassTime = 0;
  double deltaTime = 0;

  // Positioning
  Vector2 desiredPosition = Vector2.zero();
  double positionUpdateTimer = 0.0;
  double positionUpdateInterval = 3.0;

  // State
  double fatigue = 0.0;
  TeamState teamState = TeamState.neutral;
  double microMoveTimer = 0.0;

  PlayerComponent({required this.pit, Vector2? position})
    : super(position: position ?? Vector2.zero(), size: Vector2.all(28)) {
    desiredPosition = Vector2.zero();
  }

  @override
  void update(double dt) {
    deltaTime = dt;
    super.update(deltaTime);
    if (gameRef.gameState == GameState.finished) {
      velocity = Vector2.zero();
      return;
    }

    if (ball == null) return;

    updateTeamState();
    updatePositioning(deltaTime);
    handleBallInteraction();
    clampPosition();
  }

  @override
  void render(Canvas canvas) {
    renderPlayer(canvas, pit, radius, gameRef.teamA, gameRef.teamB);
  }

  void assignBallRef(BallComponent b) => ball = b;
}
