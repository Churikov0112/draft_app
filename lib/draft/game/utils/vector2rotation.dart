import 'dart:math';

import 'package:flame/game.dart';

extension Vector2Rotation on Vector2 {
  Vector2 rotated(double angle) {
    final cosA = cos(angle);
    final sinA = sin(angle);
    return Vector2(x * cosA - y * sinA, x * sinA + y * cosA);
  }
}
