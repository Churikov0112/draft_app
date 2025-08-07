// components/goal_component.dart
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class GoalComponent extends PositionComponent {
  final int team; // 0 = слева, 1 = справа

  GoalComponent({required this.team, required Vector2 position}) : super(position: position, size: Vector2(10, 60));

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.redAccent;
    canvas.drawRect(size.toRect(), paint);
  }

  bool isGoal(Vector2 ballPosition) {
    final goalRect = toAbsoluteRect();
    return goalRect.contains(Offset(ballPosition.x, ballPosition.y));
  }
}
