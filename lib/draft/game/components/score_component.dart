import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class ScoreComponent extends TextComponent {
  final String Function() getScore;

  ScoreComponent({required this.getScore})
    : super(
        anchor: Anchor.topLeft,
        position: Vector2(10, 10),
        textRenderer: TextPaint(
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(offset: Offset(1, 1), color: Colors.black45, blurRadius: 2)],
          ),
        ),
      );

  @override
  void update(double dt) {
    super.update(dt);
    text = getScore();
  }
}
