/// Pure-Dart rummy engine (classic / gin / indian / rummy 500 / kalooki /
/// canasta / kids / duel). No Flutter imports: unit-testable headless.

class RummyCard {
  final int suit; // 0=S 1=H 2=D 3=C 4=Joker
  final int rank; // 1..13, 0 for joker
  const RummyCard(this.suit, this.rank);
  bool get isJoker => suit == 4;
  bool isWild(RummyConfig cfg) =>
      isJoker || (cfg.wildRank > 0 && rank == cfg.wildRank);
  int get deadValue =>
      isJoker ? 15 : (rank == 1 ? 1 : (rank >= 10 ? 10 : rank));
  int get meldValue {
    if (isJoker) return 50;
    if (rank == 1 || rank == 2) return 20;
    if (rank >= 7) return 10;
    return 5;
  }

  static const List<String> rankNames = [
    'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'
  ];
  static const List<String> suitChars = ['S', 'H', 'D', 'C'];
  String get rankLabel => isJoker ? 'W' : rankNames[rank - 1];
  String get suitChar => isJoker ? 'J' : suitChars[suit];
  String label() =>
      isJoker ? 'a Joker' : '${rankNames[rank - 1]}${suitChars[suit]}';

  @override
  bool operator ==(Object other) =>
      other is RummyCard && other.suit == suit && other.rank == rank;
  @override
  int get hashCode => suit * 16 + rank;
}

class RummyConfig {
  final String name;
  final int handSize;
  final int meldMin;
  final int jokers;
  final int deadwoodTarget;
  final int rounds; // 0 = open match decided by targetScore
  final int targetScore; // 0 = decided by rounds
  final int wildRank; // -1 = none
  final bool twoDecks;
  final bool canastaMode;
  final bool knockEnabled;
  final bool meldAsYouGo;
  final bool layOffAllowed;
  final bool indianStyle;
  final bool kalookiStyle;
  const RummyConfig({
    required this.name,
    required this.handSize,
    this.meldMin = 3,
    this.jokers = 0,
    this.deadwoodTarget = 10,
    this.rounds = 0,
    this.targetScore = 100,
    this.wildRank = -1,
    this.twoDecks = false,
    this.canastaMode = false,
    this.knockEnabled = false,
    this.meldAsYouGo = false,
    this.layOffAllowed = true,
    this.indianStyle = false,
    this.kalookiStyle = false,
  });
}

bool _isSetMeld(List<RummyCard> cards, RummyConfig cfg) {
  final nat = cards.where((c) => !c.isWild(cfg)).toList();
  if (nat.isEmpty) return false;
  final r = nat.first.rank;
  for (final c in nat) {
    if (c.rank != r) return false;
  }
  return true;
}

bool _isRunMeld(List<RummyCard> cards, RummyConfig cfg) {
  final nat = cards.where((c) => !c.isWild(cfg)).toList();
  if (nat.isEmpty) return false;
  final s = nat.first.suit;
  for (final c in nat) {
    if (c.suit != s) return false;
  }
  final rs = nat.map((c) => c.rank).toList()..sort();
  for (int i = 1; i < rs.length; i++) {
    if (rs[i] == rs[i - 1]) return false; // duplicate rank breaks a run
  }
  if (rs.first == 1 && rs.last == 13) return false; // no wrap-around runs
  final span = rs.last - rs.first + 1;
  return span <= cards.length;
}

/// A valid meld: 3+ cards forming a set (same rank) or a run (same suit,
/// consecutive), with wilds/jokers filling gaps. Never all-wild.
bool isValidMeld(List<RummyCard> cards, RummyConfig cfg) {
  if (cards.length < cfg.meldMin) return false;
  if (cfg.canastaMode && cards.length > 7) return false;
  final nat = cards.where((c) => !c.isWild(cfg)).toList();
  if (nat.isEmpty) return false;
  return _isSetMeld(cards, cfg) || _isRunMeld(cards, cfg);
}

bool canLayOff(RummyCard c, List<RummyCard> meld, RummyConfig cfg) {
  if (!cfg.layOffAllowed) return false;
  return isValidMeld([...meld, c], cfg);
}

class _DwPlan {
  final int value;
  final List<List<int>> melds; // index lists into the hand
  const _DwPlan(this.value, this.melds);
}

int _lowBit(int m) => (m & -m).bitLength - 1;

/// Exact minimum deadwood via bitmask DP over all candidate melds.
_DwPlan deadwoodPlan(List<RummyCard> hand, RummyConfig cfg) {
  final n = hand.length;
  if (n == 0) return const _DwPlan(0, []);
  final vals = List<int>.generate(n, (i) => hand[i].deadValue);
  final melds = <int>[];
  final total = 1 << n;
  for (int mask = 0; mask < total && melds.length < 1500; mask++) {
    int cnt = 0;
    int mm = mask;
    while (mm != 0) {
      cnt++;
      mm &= mm - 1;
    }
    if (cnt < cfg.meldMin) continue;
    final cards = <RummyCard>[];
    for (int i = 0; i < n; i++) {
      if ((mask & (1 << i)) != 0) cards.add(hand[i]);
    }
    if (isValidMeld(cards, cfg)) melds.add(mask);
  }
  final byBit = List<List<int>>.generate(n, (_) => <int>[]);
  for (final m in melds) {
    byBit[_lowBit(m)].add(m);
  }
  final val = List<int>.filled(total, -1);
  final choice = List<int>.filled(total, 0);
  int guard = 0;
  int solve(int mask) {
    if (mask == 0) return 0;
    if (val[mask] >= 0) return val[mask];
    final i = _lowBit(mask);
    int best = vals[i] + solve(mask ^ (1 << i));
    int bestC = 0;
    for (final m in byBit[i]) {
      if (guard++ > 400000) break;
      if ((m & mask) == m) {
        final v = solve(mask ^ m);
        if (v < best) {
          best = v;
          bestC = m;
        }
      }
    }
    val[mask] = best;
    choice[mask] = bestC;
    return best;
  }

  final bestVal = solve(total - 1);
  final out = <List<int>>[];
  int mask = total - 1;
  while (mask != 0) {
    final c = choice[mask];
    if (c == 0) {
      mask ^= (1 << _lowBit(mask));
    } else {
      final idx = <int>[];
      for (int i = 0; i < n; i++) {
        if ((c & (1 << i)) != 0) idx.add(i);
      }
      out.add(idx);
      mask ^= c;
    }
  }
  return _DwPlan(bestVal, out);
}

int deadwoodOf(List<RummyCard> hand, RummyConfig cfg) =>
    deadwoodPlan(hand, cfg).value;

class _Snap {
  final List<RummyCard> ph, ah, st, dp;
  final List<List<RummyCard>> pm, am;
  final int ps, as_, pmp, amp, round, moves, pLp, pLa;
  final String phase, event;
  final bool won;
  _Snap(this.ph, this.ah, this.st, this.dp, this.pm, this.am, this.ps,
      this.as_, this.pmp, this.amp, this.round, this.moves, this.pLp,
      this.pLa, this.phase, this.event, this.won);
}

class RummyEngine {
  final RummyConfig cfg;
  late List<RummyCard> playerHand;
  late List<RummyCard> aiHand;
  late List<RummyCard> stock;
  late List<RummyCard> discardPile;
  late List<List<RummyCard>> playerMelds;
  late List<List<RummyCard>> aiMelds;
  int round = 1;
  int playerScore = 0;
  int aiScore = 0;
  int playerMeldPoints = 0;
  int aiMeldPoints = 0;
  int moves = 0;
  int lastRoundPlayer = 0;
  int lastRoundAi = 0;
  String phase = 'draw'; // draw | play | ai | roundOver | matchOver
  String difficulty = 'medium';
  String lastEvent = '';
  bool roundWonByPlayer = false;
  final List<_Snap> _undo = [];

  RummyEngine(this.cfg);

  void newGame({int? seed, String difficulty = 'medium'}) {
    this.difficulty = difficulty;
    round = 1;
    playerScore = 0;
    aiScore = 0;
    moves = 0;
    lastEvent = '';
    _undo.clear();
    newRound(seed: seed);
  }

  void newRound({int? seed}) {
    final rng = seed == null ? null : _SeededRandom(seed);
    final deck = <RummyCard>[];
    final decks = cfg.twoDecks ? 2 : 1;
    for (int d = 0; d < decks; d++) {
      for (int s = 0; s < 4; s++) {
        for (int r = 1; r <= 13; r++) {
          deck.add(RummyCard(s, r));
        }
      }
    }
    for (int j = 0; j < cfg.jokers; j++) {
      deck.add(const RummyCard(4, 0));
    }
    if (rng == null) {
      deck.shuffle();
    } else {
      rng.shuffle(deck);
    }
    playerHand = <RummyCard>[];
    aiHand = <RummyCard>[];
    for (int i = 0; i < cfg.handSize; i++) {
      playerHand.add(deck.removeLast());
      aiHand.add(deck.removeLast());
    }
    discardPile = [deck.removeLast()];
    stock = deck;
    playerMelds = <List<RummyCard>>[];
    aiMelds = <List<RummyCard>>[];
    playerMeldPoints = 0;
    aiMeldPoints = 0;
    lastRoundPlayer = 0;
    lastRoundAi = 0;
    phase = 'draw';
    lastEvent = 'Round $round: draw a card.';
    sortPlayerHand();
  }

  void sortPlayerHand() {
    playerHand.sort((a, b) {
      final wa = a.isWild(cfg) ? 1 : 0;
      final wb = b.isWild(cfg) ? 1 : 0;
      if (wa != wb) return wa - wb;
      if (a.suit != b.suit) return a.suit - b.suit;
      return a.rank - b.rank;
    });
  }

  void _pushUndo() {
    _undo.add(_Snap(
      List<RummyCard>.from(playerHand),
      List<RummyCard>.from(aiHand),
      List<RummyCard>.from(stock),
      List<RummyCard>.from(discardPile),
      playerMelds.map((m) => List<RummyCard>.from(m)).toList(),
      aiMelds.map((m) => List<RummyCard>.from(m)).toList(),
      playerScore,
      aiScore,
      playerMeldPoints,
      aiMeldPoints,
      round,
      moves,
      lastRoundPlayer,
      lastRoundAi,
      phase,
      lastEvent,
      roundWonByPlayer,
    ));
    if (_undo.length > 120) _undo.removeAt(0);
  }

  bool get canUndo => _undo.isNotEmpty;

  void undo() {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    playerHand = s.ph;
    aiHand = s.ah;
    stock = s.st;
    discardPile = s.dp;
    playerMelds = s.pm;
    aiMelds = s.am;
    playerScore = s.ps;
    aiScore = s.as_;
    playerMeldPoints = s.pmp;
    aiMeldPoints = s.amp;
    round = s.round;
    moves = s.moves;
    lastRoundPlayer = s.pLp;
    lastRoundAi = s.pLa;
    phase = s.phase;
    lastEvent = s.event;
    roundWonByPlayer = s.won;
  }

  // ---------------- player actions ----------------

  bool drawStock() {
    if (phase != 'draw' || stock.isEmpty) return false;
    _pushUndo();
    playerHand.add(stock.removeLast());
    sortPlayerHand();
    phase = 'play';
    moves++;
    lastEvent = 'Drew from the stock.';
    return true;
  }

  bool drawDiscard() {
    if (phase != 'draw' || discardPile.isEmpty) return false;
    _pushUndo();
    playerHand.add(discardPile.removeLast());
    sortPlayerHand();
    phase = 'play';
    moves++;
    lastEvent = 'Picked up the discard.';
    return true;
  }

  bool playerMeld(List<int> idx) {
    if (phase != 'play') return false;
    final s = idx.toSet().toList()..sort();
    if (s.length < cfg.meldMin) return false;
    if (s.any((i) => i < 0 || i >= playerHand.length)) return false;
    final cards = [for (final i in s) playerHand[i]];
    if (!isValidMeld(cards, cfg)) return false;
    _pushUndo();
    for (final i in s.reversed) {
      playerHand.removeAt(i);
    }
    playerMelds.add(cards);
    if (cfg.meldAsYouGo || cfg.canastaMode) {
      playerMeldPoints += cards.fold(0, (t, c) => t + c.meldValue);
    }
    moves++;
    lastEvent = 'Melded ${cards.length} cards.';
    return true;
  }

  bool playerLayOff(int handIdx, bool ownMeld, int meldIdx) {
    if (phase != 'play' || !cfg.layOffAllowed) return false;
    if (handIdx < 0 || handIdx >= playerHand.length) return false;
    final melds = ownMeld ? playerMelds : aiMelds;
    if (meldIdx < 0 || meldIdx >= melds.length) return false;
    final card = playerHand[handIdx];
    if (!canLayOff(card, melds[meldIdx], cfg)) return false;
    _pushUndo();
    playerHand.removeAt(handIdx);
    melds[meldIdx].add(card);
    if (cfg.meldAsYouGo || cfg.canastaMode) {
      playerMeldPoints += card.meldValue;
    }
    moves++;
    lastEvent = 'Laid off ${card.label()}.';
    return true;
  }

  /// Meld every optimal group at once. Returns groups melded.
  int playerAutoMeld() {
    if (phase != 'play') return 0;
    final plan = deadwoodPlan(playerHand, cfg);
    final drop = <int>{};
    final groups = <List<RummyCard>>[];
    for (final idx in plan.melds) {
      final cards = [for (final i in idx) playerHand[i]];
      if (!isValidMeld(cards, cfg)) continue;
      groups.add(cards);
      drop.addAll(idx);
    }
    if (groups.isEmpty) return 0;
    _pushUndo();
    playerHand = [
      for (int i = 0; i < playerHand.length; i++)
        if (!drop.contains(i)) playerHand[i]
    ];
    for (final g in groups) {
      playerMelds.add(g);
      if (cfg.meldAsYouGo || cfg.canastaMode) {
        playerMeldPoints += g.fold(0, (t, c) => t + c.meldValue);
      }
    }
    moves++;
    lastEvent =
        'Auto-melded ${groups.length} group${groups.length == 1 ? '' : 's'}.';
    return groups.length;
  }

  bool playerDiscard(int handIdx) {
    if (phase != 'play') return false;
    if (handIdx < 0 || handIdx >= playerHand.length) return false;
    _pushUndo();
    discardPile.add(playerHand.removeAt(handIdx));
    moves++;
    sortPlayerHand();
    phase = 'ai';
    lastEvent = 'You discard. Rival thinking.';
    return true;
  }

  bool canKnockWith(int handIdx) {
    if (phase != 'play' || !cfg.knockEnabled) return false;
    if (handIdx < 0 || handIdx >= playerHand.length) return false;
    final rest = [
      for (int i = 0; i < playerHand.length; i++)
        if (i != handIdx) playerHand[i]
    ];
    return deadwoodOf(rest, cfg) <= cfg.deadwoodTarget;
  }

  bool canGin() {
    if (phase != 'play' || !cfg.knockEnabled) return false;
    return deadwoodOf(playerHand, cfg) == 0;
  }

  bool knock(int handIdx) {
    if (!canKnockWith(handIdx)) return false;
    _pushUndo();
    discardPile.add(playerHand.removeAt(handIdx));
    moves++;
    _resolveKnock(byPlayer: true);
    return true;
  }

  bool gin() {
    if (!canGin()) return false;
    _pushUndo();
    moves++;
    _resolveKnock(byPlayer: true);
    return true;
  }

  bool canDeclare() {
    if (phase != 'play' || cfg.knockEnabled) return false;
    if (playerHand.length != 1) return false;
    return _contractOk(playerMelds);
  }

  bool declare() {
    if (!canDeclare()) return false;
    _pushUndo();
    discardPile.add(playerHand.removeAt(0));
    moves++;
    _resolveDeclare(byPlayer: true);
    return true;
  }

  // ---------------- contracts ----------------

  bool _contractOk(List<List<RummyCard>> melds) {
    if (cfg.canastaMode) {
      return melds.any((m) => m.length >= 7);
    }
    if (cfg.indianStyle) {
      int total = 0, runs = 0, pure = 0;
      for (final m in melds) {
        total += m.length;
        if (_isRunMeld(m, cfg)) {
          runs++;
          if (!m.any((c) => c.isWild(cfg))) pure++;
        }
      }
      return total == cfg.handSize && runs >= 2 && pure >= 1;
    }
    if (cfg.kalookiStyle) return _kalookiOk(melds);
    return true;
  }

  List<List<int>> _kalookiContract() {
    // [kind, size]: kind 0 = set, 1 = run
    switch (round % 6) {
      case 1:
        return [
          [0, 3],
          [0, 3]
        ];
      case 2:
        return [
          [0, 3],
          [1, 4]
        ];
      case 3:
        return [
          [1, 4],
          [1, 4]
        ];
      case 4:
        return [
          [0, 3],
          [0, 3],
          [1, 4]
        ];
      case 5:
        return [
          [0, 3],
          [1, 4],
          [1, 4]
        ];
      default:
        return [
          [1, 4],
          [1, 4],
          [1, 4]
        ];
    }
  }

  bool _kalookiOk(List<List<RummyCard>> melds) {
    final reqs = _kalookiContract();
    final used = List<bool>.filled(melds.length, false);
    for (final req in reqs) {
      bool found = false;
      for (int i = 0; i < melds.length; i++) {
        if (used[i]) continue;
        final m = melds[i];
        final isSet = _isSetMeld(m, cfg);
        final isRun = _isRunMeld(m, cfg);
        if (req[0] == 0 && isSet && m.length >= req[1]) {
          used[i] = true;
          found = true;
          break;
        }
        if (req[0] == 1 && isRun && m.length >= req[1]) {
          used[i] = true;
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
  }

  // ---------------- round resolution ----------------

  void _meldAll(List<RummyCard> hand, List<List<RummyCard>> melds) {
    final plan = deadwoodPlan(hand, cfg);
    final drop = <int>{};
    for (final idx in plan.melds) {
      melds.add([for (final i in idx) hand[i]]);
      drop.addAll(idx);
    }
    final kept = <RummyCard>[];
    for (int i = 0; i < hand.length; i++) {
      if (!drop.contains(i)) kept.add(hand[i]);
    }
    hand
      ..clear()
      ..addAll(kept);
  }

  void _layOffOn(List<RummyCard> hand, List<List<RummyCard>> melds) {
    bool changed = true;
    int guard = 0;
    while (changed && guard++ < 60) {
      changed = false;
      for (int i = hand.length - 1; i >= 0; i--) {
        for (final m in melds) {
          if (canLayOff(hand[i], m, cfg)) {
            m.add(hand.removeAt(i));
            changed = true;
            break;
          }
        }
      }
    }
  }

  void _resolveKnock({required bool byPlayer}) {
    final kHand = byPlayer ? playerHand : aiHand;
    final kMelds = byPlayer ? playerMelds : aiMelds;
    final dHand = byPlayer ? aiHand : playerHand;
    _meldAll(kHand, kMelds);
    final kDw = deadwoodOf(kHand, cfg);
    int pPts = 0, aPts = 0;
    String evt;
    if (kDw == 0) {
      final dDw = deadwoodOf(dHand, cfg);
      if (byPlayer) {
        pPts = 25 + dDw;
        evt = 'Gin! You score $pPts.';
      } else {
        aPts = 25 + dDw;
        evt = 'Rival gins and scores $aPts.';
      }
    } else {
      _layOffOn(dHand, kMelds);
      final dDw = deadwoodOf(dHand, cfg);
      if (dDw < kDw) {
        final pts = (kDw - dDw) + 25; // undercut
        if (byPlayer) {
          aPts = pts;
          evt = 'Undercut! Rival scores $pts.';
        } else {
          pPts = pts;
          evt = 'Undercut! You score $pts.';
        }
      } else {
        final pts = dDw - kDw;
        if (byPlayer) {
          pPts = pts;
          evt = 'Knock holds. You score $pts.';
        } else {
          aPts = pts;
          evt = 'Rival knocks and scores $pts.';
        }
      }
    }
    lastRoundPlayer = pPts;
    lastRoundAi = aPts;
    playerScore += pPts;
    aiScore += aPts;
    roundWonByPlayer = pPts > aPts;
    lastEvent = evt;
    _finishRound();
  }

  void _resolveDeclare({required bool byPlayer}) {
    int pPts, aPts;
    String evt;
    if (cfg.canastaMode) {
      pPts = _canastaPoints(playerMelds, byPlayer, playerHand);
      aPts = _canastaPoints(aiMelds, !byPlayer, aiHand);
      evt = byPlayer ? 'You go out! +$pPts.' : 'Rival goes out. +$aPts.';
    } else if (cfg.meldAsYouGo) {
      final pDw = deadwoodOf(playerHand, cfg);
      final aDw = deadwoodOf(aiHand, cfg);
      pPts = playerMeldPoints + (byPlayer ? aDw + 25 : 0);
      aPts = aiMeldPoints + (!byPlayer ? pDw + 25 : 0);
      evt = byPlayer ? 'You meld out! +$pPts.' : 'Rival melds out. +$aPts.';
    } else {
      final dDw =
          byPlayer ? deadwoodOf(aiHand, cfg) : deadwoodOf(playerHand, cfg);
      if (byPlayer) {
        pPts = dDw;
        aPts = 0;
        evt = 'You take the round! +$pPts.';
      } else {
        aPts = dDw;
        pPts = 0;
        evt = 'Rival takes the round. +$aPts.';
      }
    }
    lastRoundPlayer = pPts;
    lastRoundAi = aPts;
    playerScore += pPts;
    aiScore += aPts;
    roundWonByPlayer = pPts > aPts;
    lastEvent = evt;
    _finishRound();
  }

  int _canastaPoints(
      List<List<RummyCard>> melds, bool wentOut, List<RummyCard> hand) {
    int pts = 0;
    for (final m in melds) {
      pts += m.fold(0, (t, c) => t + c.meldValue);
      if (m.length >= 7) {
        pts += m.any((c) => c.isWild(cfg)) ? 300 : 500;
      }
    }
    if (wentOut) pts += 100;
    pts -= _unmeldedPenalty(hand);
    return pts < 0 ? 0 : pts;
  }

  int _unmeldedPenalty(List<RummyCard> hand) {
    final plan = deadwoodPlan(hand, cfg);
    final used = <int>{};
    for (final idx in plan.melds) {
      used.addAll(idx);
    }
    int p = 0;
    for (int i = 0; i < hand.length; i++) {
      if (!used.contains(i)) {
        p += cfg.canastaMode ? hand[i].meldValue : hand[i].deadValue;
      }
    }
    return p;
  }

  void _finishRound() {
    phase = 'roundOver';
    if (cfg.targetScore > 0 &&
        (playerScore >= cfg.targetScore || aiScore >= cfg.targetScore)) {
      phase = 'matchOver';
    } else if (cfg.rounds > 0 && round >= cfg.rounds) {
      phase = 'matchOver';
    }
  }

  bool get matchWonByPlayer =>
      phase == 'matchOver' && playerScore >= aiScore;

  bool nextRound() {
    if (phase != 'roundOver') return false;
    round++;
    newRound();
    return true;
  }

  // ---------------- AI ----------------

  void aiTakeTurn() {
    if (phase != 'ai') return;
    // 1. draw: take the discard when it clearly helps
    final top = discardPile.isNotEmpty ? discardPile.last : null;
    bool takeDisc = false;
    if (top != null) {
      if (stock.isEmpty) {
        takeDisc = true;
      } else {
        final before = deadwoodOf(aiHand, cfg);
        final after = deadwoodOf([...aiHand, top], cfg);
        final need =
            difficulty == 'easy' ? 6 : (difficulty == 'expert' ? 1 : 3);
        takeDisc = before - after >= need;
        if (difficulty == 'easy' && takeDisc && before - after < 8) {
          takeDisc = false; // easy rival is sloppy
        }
      }
    }
    if (takeDisc && top != null) {
      aiHand.add(discardPile.removeLast());
    } else if (stock.isNotEmpty) {
      aiHand.add(stock.removeLast());
    } else if (top != null) {
      aiHand.add(discardPile.removeLast());
    }
    // 2. meld everything the plan finds
    _meldAll(aiHand, aiMelds);
    // 3. lay off leftovers
    _layOffOn(aiHand, aiMelds);
    if (cfg.layOffAllowed) _layOffOn(aiHand, playerMelds);
    // 4. knock / declare / discard
    if (cfg.knockEnabled) {
      if (aiHand.isNotEmpty && deadwoodOf(aiHand, cfg) == 0) {
        _resolveKnock(byPlayer: false); // gin, no discard needed
        return;
      }
      final di = _aiDiscardIndex();
      final rest = [
        for (int i = 0; i < aiHand.length; i++)
          if (i != di) aiHand[i]
      ];
      final dw = deadwoodOf(rest, cfg);
      final wantsKnock = dw <= cfg.deadwoodTarget &&
          (difficulty == 'easy' ? deadwoodOf(aiHand, cfg) % 2 == 0 : true);
      if (wantsKnock && di >= 0) {
        discardPile.add(aiHand.removeAt(di));
        _resolveKnock(byPlayer: false);
        return;
      }
      if (di >= 0) discardPile.add(aiHand.removeAt(di));
    } else {
      if (aiHand.length == 1 && _contractOk(aiMelds)) {
        discardPile.add(aiHand.removeAt(0));
        _resolveDeclare(byPlayer: false);
        return;
      }
      final di = _aiDiscardIndex();
      if (di >= 0) discardPile.add(aiHand.removeAt(di));
      if (aiHand.isEmpty && _contractOk(aiMelds)) {
        _resolveDeclare(byPlayer: false);
        return;
      }
    }
    _reshuffleIfNeeded();
    phase = 'draw';
    lastEvent = 'Rival plays.';
  }

  int _aiDiscardIndex() {
    if (aiHand.isEmpty) return -1;
    if (difficulty == 'easy' && aiHand.length > 4) {
      // easy rival sometimes just tosses a random card
      var h = 0;
      for (final c in aiHand) {
        h = (h * 31 + c.hashCode) & 0x7fffffff;
      }
      if (h % 10 < 3) return h % aiHand.length;
    }
    int best = 0;
    int bestDw = 1 << 30;
    int bestVal = -1;
    for (int i = 0; i < aiHand.length; i++) {
      final rest = [
        for (int j = 0; j < aiHand.length; j++)
          if (j != i) aiHand[j]
      ];
      final dw = deadwoodOf(rest, cfg);
      final v = aiHand[i].deadValue;
      if (dw < bestDw || (dw == bestDw && v > bestVal)) {
        bestDw = dw;
        bestVal = v;
        best = i;
      }
    }
    if (difficulty == 'expert' && aiHand.length > 1) {
      for (int i = 0; i < aiHand.length; i++) {
        if (i == best) continue;
        final rest = [
          for (int j = 0; j < aiHand.length; j++)
            if (j != i) aiHand[j]
        ];
        if (deadwoodOf(rest, cfg) == bestDw &&
            !_feedsPlayer(aiHand[i]) &&
            _feedsPlayer(aiHand[best])) {
          best = i;
          break;
        }
      }
    }
    return best;
  }

  bool _feedsPlayer(RummyCard c) {
    for (final m in playerMelds) {
      if (canLayOff(c, m, cfg)) return true;
    }
    return false;
  }

  void _reshuffleIfNeeded() {
    if (stock.isEmpty && discardPile.length > 1 && phase == 'draw') {
      final top = discardPile.removeLast();
      stock = List<RummyCard>.from(discardPile)..shuffle();
      discardPile = [top];
    }
  }

  // ---------------- hint ----------------

  String hint() {
    if (phase == 'draw') {
      if (discardPile.isNotEmpty) {
        final top = discardPile.last;
        final before = deadwoodOf(playerHand, cfg);
        final after = deadwoodOf([...playerHand, top], cfg);
        if (before - after >= 3) {
          return 'Take ${top.label()} from the discard pile: it fits your hand.';
        }
      }
      return 'Draw from the stock to start your turn.';
    }
    if (phase == 'play') {
      if (cfg.knockEnabled) {
        if (deadwoodOf(playerHand, cfg) == 0) {
          return 'Gin! Declare now for the bonus.';
        }
        for (int i = 0; i < playerHand.length; i++) {
          if (canKnockWith(i)) {
            return 'Discard ${playerHand[i].label()} and knock: your deadwood is low.';
          }
        }
      }
      if (!cfg.knockEnabled && canDeclare()) {
        return 'You can declare: discard your last card to take the round.';
      }
      final plan = deadwoodPlan(playerHand, cfg);
      if (plan.melds.isNotEmpty) {
        final cards = [for (final i in plan.melds.first) playerHand[i]];
        final kind = _isRunMeld(cards, cfg) ? 'run' : 'set';
        return 'Meld the ${cards.map((c) => c.label()).join(', ')} $kind.';
      }
      if (playerHand.isNotEmpty) {
        int bi = 0, bdw = 1 << 30;
        for (int i = 0; i < playerHand.length; i++) {
          final rest = [
            for (int j = 0; j < playerHand.length; j++)
              if (j != i) playerHand[j]
          ];
          final dw = deadwoodOf(rest, cfg);
          if (dw < bdw) {
            bdw = dw;
            bi = i;
          }
        }
        return 'No melds yet: discard ${playerHand[bi].label()} to keep deadwood low.';
      }
      return 'Draw a card to begin.';
    }
    if (phase == 'roundOver') return 'Round over: start the next round.';
    return 'Start a new match.';
  }
}

/// Deterministic shuffle helper (seeded daily deals).
class _SeededRandom {
  int _s;
  _SeededRandom(int seed) : _s = seed & 0x7fffffff;
  int _next() {
    _s = (_s * 1103515245 + 12345) & 0x7fffffff;
    return _s;
  }

  void shuffle(List<RummyCard> list) {
    for (int i = list.length - 1; i > 0; i--) {
      final j = _next() % (i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
  }
}

RummyConfig gameConfig() {
  return const RummyConfig(name: 'classic', handSize: 10, meldMin: 3, knockEnabled: true, deadwoodTarget: 10, targetScore: 100);
}
