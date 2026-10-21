import 'package:flutter/material.dart';
import 'package:qavexrummyclassicpro/core/app_state.dart';
import 'package:qavexrummyclassicpro/widgets/ui.dart';

class HowToScreen extends StatelessWidget {
  const HowToScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBuilder(
      builder: (context, s) => QxScaffold(
        title: 'How to Play',
        body: ListView(
          children: const [
            QxCard(
              child: Text('HOW TO PLAY\n\nGoal: be the first to 100 points across rounds of 10-card rummy.\n\n- Each round you get 10 cards. On your turn, draw from the stock or take the\n  top discard, optionally meld sets (3+ same rank) or runs (3+ same suit in\n  sequence), then discard one card.\n- Tap cards to select them, then use Meld, Auto, Lay Off, Discard, Knock.\n- KNOCK: when your unmatched cards (deadwood) total 10 or less, discard and\n  knock. You score the rival\'s deadwood minus yours. Knock with zero\n  deadwood for GIN: 25 bonus plus all rival deadwood.\n- UNDERCUT: if the rival\'s deadwood beats yours after a knock, they score\n  the difference plus 25. Knock only when you are confident!\n- Lay off spare cards onto any open meld, yours or the rival\'s.\n\nMODES\n- Classic: pure 10-card rummy to 100 points.\n- Timed Run: 10 minutes; finish the match before the clock.\n- Daily Challenge: one seeded deal per day; streaks pay bonus.\n- Zen Table: no timer, free hints and undo.\n- AI Ladder: 8 rungs from Easy to Expert. Win to climb.\n- Tournament: best-of-5 rounds.\n- Kids Mode: a gentle rival and extra guidance.\n- Practice: free play with auto-hints.',
                  style: TextStyle(fontSize: 15, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}
