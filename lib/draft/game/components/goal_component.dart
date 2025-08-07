import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../match_game.dart';

class GoalComponent extends PositionComponent with HasGameRef<MatchGame> {
  final int team; // 0 = левая команда, 1 = правая команда

  GoalComponent({required this.team, required Vector2 position}) : super(position: position, size: Vector2(10, 80));

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = Colors.redAccent;
    final textPainter = TextPainter(
      text: TextSpan(
        text: team == 0 ? gameRef.team0score.toString() : gameRef.team1score.toString(),
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(0, -textPainter.height - 4));

    canvas.drawRect(size.toRect(), paint);
  }

  bool isGoal(Vector2 ballPosition) {
    final goalRect = toAbsoluteRect();
    return goalRect.contains(Offset(ballPosition.x, ballPosition.y));
  }
}
