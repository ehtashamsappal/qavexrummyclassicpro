import 'package:flutter_test/flutter_test.dart';
import 'package:qavexrummyclassicpro/game/logic.dart';

RummyEngine fresh({int seed = 11}) {
  final e = RummyEngine(gameConfig());
  e.newGame(seed: seed);
  return e;
}

RummyCard c(int s, int r) => RummyCard(s, r);
RummyCard joker() => const RummyCard(4, 0);

void main() {
  test('config deal size matches spec', () {
    expect(gameConfig().handSize, 10);
  });

  test('new game deals full hands and one discard', () {
    final e = fresh();
    expect(e.playerHand.length, gameConfig().handSize);
    expect(e.aiHand.length, gameConfig().handSize);
    expect(e.discardPile.length, 1);
    expect(e.stock.isNotEmpty, isTrue);
    expect(e.phase, 'draw');
    expect(e.round, 1);
  });

  test('set of three is a valid meld', () {
    expect(
        isValidMeld([c(0, 7), c(1, 7), c(2, 7)], gameConfig()), isTrue);
  });

  test('suited run of three is a valid meld', () {
    expect(
        isValidMeld([c(2, 3), c(2, 4), c(2, 5)], gameConfig()), isTrue);
  });

  test('mixed junk is not a meld', () {
    expect(
        isValidMeld([c(0, 7), c(1, 9), c(2, 11)], gameConfig()), isFalse);
  });

  test('a pair is not a meld', () {
    expect(isValidMeld([c(0, 7), c(1, 7)], gameConfig()), isFalse);
  });

  test('deadwood counts unmatched card values', () {
    final e = fresh();
    e.playerHand = [
      c(0, 7), c(1, 7), c(2, 7), // set -> 0
      c(2, 3), c(2, 4), c(2, 5), // run -> 0
      c(0, 13), // K -> 10
      c(1, 9), // 9 -> 9
    ];
    expect(deadwoodOf(e.playerHand, gameConfig()), 19);
  });

  test('draw from stock then undo restores', () {
    final e = fresh();
    final n = e.playerHand.length;
    expect(e.drawStock(), isTrue);
    expect(e.playerHand.length, n + 1);
    expect(e.phase, 'play');
    expect(e.canUndo, isTrue);
    e.undo();
    expect(e.playerHand.length, n);
    expect(e.phase, 'draw');
  });

  test('meld moves cards to the meld area', () {
    final e = fresh();
    e.playerHand = [c(0, 7), c(1, 7), c(2, 7), c(0, 13), c(1, 9)];
    e.phase = 'play';
    expect(e.playerMeld([0, 1, 2]), isTrue);
    expect(e.playerMelds.length, 1);
    expect(e.playerHand.length, 2);
    expect(e.moves, 1);
  });

  test('lay off extends a meld', () {
    final e = fresh();
    e.playerHand = [c(0, 7), c(1, 7), c(2, 7), c(3, 7), c(1, 9)];
    e.phase = 'play';
    expect(e.playerMeld([0, 1, 2]), isTrue);
    expect(e.playerLayOff(0, true, 0), isTrue);
    expect(e.playerMelds[0].length, 4);
    expect(e.playerHand.length, 1);
  });

  test('hint is non-empty before and after the draw', () {
    final e = fresh();
    expect(e.hint(), isNotEmpty);
    e.drawStock();
    expect(e.hint(), isNotEmpty);
  });

  test('AI completes a full turn quickly', () {
    final e = fresh();
    e.drawStock();
    expect(e.playerDiscard(0), isTrue);
    final sw = Stopwatch()..start();
    e.aiTakeTurn();
    sw.stop();
    expect(e.phase, anyOf(equals('draw'), equals('roundOver'), equals('matchOver')));
    expect(sw.elapsedMilliseconds, lessThan(8000));
  });

  test('knock or declare flow resolves a round', () {
    final cfg = gameConfig();
    if (cfg.knockEnabled) {
      final e = fresh();
      e.playerHand = [
        c(0, 7), c(1, 7), c(2, 7), // set
        c(2, 3), c(2, 4), c(2, 5), c(2, 6), // run
        c(0, 1), c(1, 2), c(3, 5), // A, 2, 5 -> deadwood 8
      ];
      e.phase = 'play';
      e.aiHand = [
        c(0, 13), c(1, 13), c(2, 12), c(3, 12), c(0, 11),
        c(1, 4), c(2, 9), c(3, 3), c(0, 5), c(1, 6),
      ];
      expect(e.canKnockWith(9), isTrue);
      expect(e.knock(9), isTrue);
      expect(e.phase, anyOf(equals('roundOver'), equals('matchOver')));
      expect(e.lastRoundPlayer + e.lastRoundAi, greaterThan(0));
      expect(e.roundWonByPlayer, isTrue);
    } else {
      final e = fresh();
      if (cfg.canastaMode) {
        e.playerMelds = [
          [c(0, 5), c(1, 5), c(2, 5), c(3, 5), c(0, 5), c(1, 5), c(2, 5)],
        ];
        e.playerHand = [c(0, 13)];
      } else if (cfg.indianStyle) {
        e.playerMelds = [
          [c(2, 3), c(2, 4), c(2, 5)], // pure run
          [c(1, 7), c(1, 8), joker()], // run with joker
          [c(0, 9), c(1, 9), c(2, 9)], // set
          [c(0, 13), c(1, 13), c(2, 13), joker()], // set with joker
        ];
        e.playerHand = [c(3, 2)];
      } else if (cfg.kalookiStyle) {
        e.playerMelds = [
          [c(0, 7), c(1, 7), c(2, 7)],
          [c(0, 9), c(1, 9), c(2, 9)],
        ];
        e.playerHand = [c(3, 2)];
      } else {
        e.playerMelds = [
          [c(0, 7), c(1, 7), c(2, 7)],
          [c(2, 3), c(2, 4), c(2, 5)],
        ];
        e.playerHand = [c(3, 2)];
      }
      e.phase = 'play';
      expect(e.canDeclare(), isTrue);
      expect(e.declare(), isTrue);
      expect(e.phase, anyOf(equals('roundOver'), equals('matchOver')));
      expect(e.roundWonByPlayer, isTrue);
    }
  });
}
