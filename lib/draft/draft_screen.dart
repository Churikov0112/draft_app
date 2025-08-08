import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/match_game.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: GameWidget.controlled(gameFactory: MatchGame.new)),
    );
  }
}
