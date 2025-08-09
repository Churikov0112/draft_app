import 'package:draft_app/draft/game/models/team.dart';
import 'package:flutter/material.dart';

import '../../models/player.dart';

void renderPlayer(Canvas canvas, PlayerInTeamModel pit, double radius, TeamModel teamA, TeamModel teamB) {
  final shadowPaint = Paint()..color = Colors.black.withOpacity(0.25);
  canvas.drawCircle(Offset(2, 3), radius * 0.95, shadowPaint);

  final outlinePaint = Paint()..color = Colors.black;
  canvas.drawCircle(Offset.zero, radius + 2.0, outlinePaint);

  final fillPaint = Paint()..color = pit.teamId == teamA.id ? teamA.color : teamB.color;
  canvas.drawCircle(Offset.zero, radius, fillPaint);

  final textPainter = TextPainter(
    text: TextSpan(
      text: pit.number.toString(),
      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
    ),
    textDirection: TextDirection.ltr,
  );
  textPainter.layout();
  textPainter.paint(canvas, Offset(-textPainter.width / 2, -radius - textPainter.height - 4));
}
