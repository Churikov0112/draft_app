import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'game/match_game.dart';

class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key});
  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  late final MatchGame _game;

  @override
  void initState() {
    super.initState();
    _game = MatchGame();
  }

  @override
  void dispose() {
    _game.onDetach(); // if you add cleanup
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MVP: 1v1 Match'),
      ),
      body: GameWidget(
        game: _game,
      ),
    );
  }
}
