import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qavexrummyclassicpro/core/app_state.dart';
import 'package:qavexrummyclassicpro/core/sound.dart';
import 'package:qavexrummyclassicpro/game/logic.dart';
import 'package:qavexrummyclassicpro/game/cards_ui.dart';
import 'package:qavexrummyclassicpro/screens/mode_select.dart';

/// Per-game flavor tagline, replaced per game by the factory.
const String kGameFlavor = 'Ten cards. One clever rival. Zero mercy.';

class _Particle {
  double x, y, vx, vy, size;
  Color color;
  _Particle(this.x, this.y, this.vx, this.vy, this.size, this.color);
}

class GameScreen extends StatefulWidget {
  final GameModeDef mode;
  const GameScreen({super.key, required this.mode});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late RummyEngine _e;
  Timer? _timer;
  int _elapsed = 0;
  int _timeLeft = 0;
  final Set<int> _sel = {};
  int _selMeldSide = 0; // 0=none, 1=mine, 2=rival
  int _selMeldIdx = -1;
  String _message = 'Welcome to the Emerald Club! Out-meld Don Rafael.';
  bool _matchOver = false;
  bool _matchWon = false;
  bool _paused = false;
  bool _busyAi = false;
  String _difficulty = 'medium';
  int _ladderRung = 1;
  int _tournWins = 0;
  int _tournLosses = 0;
  int _hints = 0;
  int _undos = 0;
  late AnimationController _confetti;
  final List<_Particle> _particles = [];
  final Random _rng = Random();

  static const List<String> _rungDiff = [
    'easy', 'easy', 'medium', 'medium', 'hard', 'hard', 'expert', 'expert'
  ];

  bool get _isTimed => widget.mode.id == 'timed';
  bool get _isDaily => widget.mode.id == 'daily';
  bool get _isZen => widget.mode.id == 'zen';
  bool get _isKids => widget.mode.id == 'kids';
  bool get _isPractice => widget.mode.id == 'practice';
  bool get _isLadder => widget.mode.id == 'ladder';
  bool get _isTournament => widget.mode.id == 'tournament';

  @override
  void initState() {
    super.initState();
    _confetti = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..addListener(() {
        if (_particles.isNotEmpty) setState(_tickParticles);
      });
    _difficulty = _isKids ? 'easy' : 'medium';
    _newMatch();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ladderRung = (prefs.getInt('qavexrummyclassicpro_ladder_rung') ?? 1).clamp(1, 8);
      if (_isLadder) {
        _difficulty = _rungDiff[_ladderRung - 1];
        _e.difficulty = _difficulty;
      } else if (_isTournament) {
        _difficulty = 'hard';
        _e.difficulty = _difficulty;
      }
    });
  }

  int _initialSeed() {
    if (_isDaily) {
      final n = DateTime.now();
      return n.year * 10000 + n.month * 100 + n.day;
    }
    return DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
  }

  void _newMatch() {
    _timer?.cancel();
    _e = RummyEngine(gameConfig());
    _e.newGame(seed: _initialSeed(), difficulty: _difficulty);
    _elapsed = 0;
    _timeLeft = _isTimed ? 600 : 0;
    _sel.clear();
    _selMeldSide = 0;
    _selMeldIdx = -1;
    _matchOver = false;
    _matchWon = false;
    _paused = false;
    _busyAi = false;
    _hints = 0;
    _undos = 0;
    _tournWins = 0;
    _tournLosses = 0;
    _particles.clear();
    _confetti.reset();
    _message = 'Welcome to the Emerald Club! Out-meld Don Rafael.';
    SoundService.I.play('click');
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_paused || _matchOver) return;
      setState(() {
        _elapsed++;
        if (_isTimed) {
          _timeLeft--;
          if (_timeLeft <= 0) {
            _timeLeft = 0;
            _onMatchEnd(false, 'Time is up!');
          }
        }
      });
    });
    setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _confetti.dispose();
    super.dispose();
  }

  void _flash(String msg) {
    setState(() => _message = msg);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _message == msg) setState(() => _message = '');
    });
  }

  void _clearSel() {
    _sel.clear();
    _selMeldSide = 0;
    _selMeldIdx = -1;
  }

  // ---------------- player input ----------------

  void _drawStock() {
    if (_e.phase != 'draw' || _busyAi || _paused || _matchOver) return;
    _clearSel();
    if (_e.drawStock()) {
      SoundService.I.play('tap');
      setState(() {});
    } else {
      SoundService.I.play('error');
    }
  }

  void _drawDiscard() {
    if (_e.phase != 'draw' || _busyAi || _paused || _matchOver) return;
    _clearSel();
    if (_e.drawDiscard()) {
      SoundService.I.play('tap');
      setState(() {});
    } else {
      SoundService.I.play('error');
    }
  }

  void _toggleHand(int i) {
    if (_e.phase != 'play' || _busyAi || _paused || _matchOver) return;
    setState(() {
      if (_sel.contains(i)) {
        _sel.remove(i);
      } else {
        _sel.add(i);
      }
    });
    SoundService.I.play('tap');
  }

  void _selectMeld(int side, int idx) {
    if (_e.phase != 'play' || _busyAi || _paused || _matchOver) return;
    setState(() {
      if (_selMeldSide == side && _selMeldIdx == idx) {
        _selMeldSide = 0;
        _selMeldIdx = -1;
      } else {
        _selMeldSide = side;
        _selMeldIdx = idx;
      }
    });
    SoundService.I.play('tap');
  }

  void _doMeld() {
    if (_sel.length < _e.cfg.meldMin) {
      _flash('Select at least ${_e.cfg.meldMin} cards to meld.');
      return;
    }
    if (_e.playerMeld(_sel.toList())) {
      _clearSel();
      SoundService.I.play('pop');
      setState(() {});
    } else {
      SoundService.I.play('error');
      _flash('Those cards do not form a set or run.');
    }
  }

  void _doAutoMeld() {
    final n = _e.playerAutoMeld();
    _clearSel();
    if (n > 0) {
      SoundService.I.play('pop');
      setState(() {});
    } else {
      SoundService.I.play('error');
      _flash('No melds in your hand right now.');
    }
  }

  void _doLayOff() {
    if (_sel.length != 1 || _selMeldSide == 0 || _selMeldIdx < 0) {
      _flash('Select one card, then tap a meld to extend it.');
      return;
    }
    if (_e.playerLayOff(_sel.first, _selMeldSide == 1, _selMeldIdx)) {
      _clearSel();
      SoundService.I.play('pop');
      setState(() {});
    } else {
      SoundService.I.play('error');
      _flash('That card does not extend the meld.');
    }
  }

  void _doDiscard() {
    if (_sel.length != 1) {
      _flash('Select exactly one card to discard.');
      return;
    }
    if (_e.playerDiscard(_sel.first)) {
      _clearSel();
      SoundService.I.play('tap');
      setState(() {});
      _runAi();
    }
  }

  void _doKnock() {
    if (_sel.length != 1) {
      _flash('Select your discard, then knock.');
      return;
    }
    if (_e.knock(_sel.first)) {
      _clearSel();
      SoundService.I.play('success');
      _afterRoundResolved();
    } else {
      SoundService.I.play('error');
      _flash('You cannot knock yet: deadwood is too high.');
    }
  }

  void _doGin() {
    if (_e.gin()) {
      SoundService.I.play('win');
      _afterRoundResolved();
    } else {
      SoundService.I.play('error');
    }
  }

  void _doDeclare() {
    if (_e.declare()) {
      SoundService.I.play('success');
      _afterRoundResolved();
    } else {
      SoundService.I.play('error');
      _flash('You cannot declare yet.');
    }
  }

  Future<void> _runAi() async {
    if (_busyAi) return;
    _busyAi = true;
    setState(() {});
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;
    _e.aiTakeTurn();
    _busyAi = false;
    SoundService.I.play('tap');
    _afterRoundResolved();
    if (_isPractice && _e.phase == 'play' && mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _e.phase == 'play' && !_busyAi) _doHint(auto: true);
      });
    }
    setState(() {});
  }

  void _afterRoundResolved() {
    if (_e.phase == 'roundOver' || _e.phase == 'matchOver') {
      _onRoundEnd();
    } else {
      setState(() {});
    }
  }

  Future<void> _onRoundEnd() async {
    final wonRound = _e.roundWonByPlayer;
    if (_isTournament) {
      if (wonRound) {
        _tournWins++;
      } else {
        _tournLosses++;
      }
      if (_tournWins >= 3 ||
          _tournLosses >= 3 ||
          _tournWins + _tournLosses >= 5 ||
          _e.phase == 'matchOver') {
        await _onMatchEnd(_tournWins > _tournLosses,
            _tournWins > _tournLosses ? 'Tournament champion!' : 'Tournament lost.');
        return;
      }
    } else if (_e.phase == 'matchOver') {
      await _onMatchEnd(
          _e.matchWonByPlayer, _e.matchWonByPlayer ? 'Match won!' : 'Match lost.');
      return;
    }
    SoundService.I.play(wonRound ? 'success' : 'lose');
    setState(() {});
  }

  Future<void> _onMatchEnd(bool won, String title) async {
    _matchOver = true;
    _matchWon = won;
    _timer?.cancel();
    SoundService.I.play(won ? 'win' : 'lose');
    final app = AppScope.of(context);
    await app.recordGame(mode: widget.mode.id, score: _e.playerScore, won: won);
    if (won) {
      app.addCounter('nohint_wins', _hints == 0 ? 1 : 0);
      app.addCounter('flawless_wins', (_hints == 0 && _undos == 0) ? 1 : 0);
      app.addCoins(20);
      if (_isLadder && _ladderRung < 8) {
        _ladderRung++;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('qavexrummyclassicpro_ladder_rung', _ladderRung);
        SoundService.I.play('levelup');
      }
      if (_isDaily) {
        await app.touchDaily();
        app.addCounter('daily_played', 1);
      }
    }
    if (_isTimed && won) app.addCounter('timed_wins', 1);
    if (_isZen) app.addCounter('zen_games', 1);
    if (_isKids) app.addCounter('kids_games', 1);
    if (_isPractice) app.addCounter('practice_games', 1);
    _flash(title);
    if (won) {
      _spawnConfetti();
      _confetti.forward();
    }
    if (mounted) setState(() {});
  }

  void _nextRound() {
    if (_e.nextRound()) {
      _clearSel();
      SoundService.I.play('click');
      setState(() {});
    }
  }

  void _doHint({bool auto = false}) {
    if (_matchOver || _paused) return;
    final h = _e.hint();
    _hints++;
    AppScope.of(context).addCounter('hints_used', 1);
    if (!auto) SoundService.I.play('tap');
    _flash(_isKids ? 'Helper: $h You are doing great!' : h);
    setState(() {});
  }

  void _doUndo() {
    if (_e.canUndo && !_busyAi && !_matchOver) {
      _e.undo();
      _undos++;
      _clearSel();
      SoundService.I.play('tap');
      setState(() {});
    } else {
      SoundService.I.play('error');
      _flash('Nothing to undo.');
    }
  }

  void _doSort() {
    _e.sortPlayerHand();
    _clearSel();
    SoundService.I.play('tap');
    setState(() {});
  }

  void _spawnConfetti() {
    final colors = [
      QCardColors.gold,
      QCardColors.accent,
      Colors.white,
      const Color(0xFFFF6B6B),
      const Color(0xFF4CC9F0),
    ];
    for (int i = 0; i < 90; i++) {
      _particles.add(_Particle(
        _rng.nextDouble(),
        -0.05 - _rng.nextDouble() * 0.2,
        (_rng.nextDouble() - 0.5) * 0.4,
        0.25 + _rng.nextDouble() * 0.45,
        4 + _rng.nextDouble() * 7,
        colors[_rng.nextInt(colors.length)],
      ));
    }
  }

  void _tickParticles() {
    const dt = 1 / 60;
    for (final p in _particles) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 0.35 * dt;
    }
    _particles.removeWhere((p) => p.y > 1.15);
  }

  String _clock() {
    final t = _isTimed ? _timeLeft : _elapsed;
    final m = t ~/ 60;
    final s = t % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _phaseText() {
    switch (_e.phase) {
      case 'draw':
        return 'Your turn: draw';
      case 'play':
        return 'Your turn: play';
      case 'ai':
        return 'Rival thinking…';
      case 'roundOver':
        return 'Round over';
      case 'matchOver':
        return 'Match over';
      default:
        return '';
    }
  }

  String _difficultyLabel() {
    if (_isLadder) return 'Ladder $_ladderRung/8 · $_difficulty';
    if (_isTournament) return 'Tournament $_tournWins–$_tournLosses';
    if (_isKids) return 'Gentle rival';
    return _difficulty;
  }

  // ============================ UI ============================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: QCardColors.bgDark,
      body: QFeltScaffold(
        child: _buildTable(context),
        overlays: [
          if (_particles.isNotEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _ConfettiPainter(_particles)),
              ),
            ),
          if (_paused && !_matchOver) _buildPauseOverlay(),
          if (_e.phase == 'roundOver' && !_matchOver) _buildRoundOverlay(),
          if (_matchOver) _buildMatchOverlay(),
        ],
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final handW = (w / 7.5).clamp(46.0, 64.0);
      final midW = (w / 6.5).clamp(52.0, 72.0);
      final meldW = (w / 9.0).clamp(38.0, 52.0);
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHud(),
            _buildControls(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _buildAiZone(meldW),
            ),
            const SizedBox(height: 6),
            _buildCenter(midW),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _buildPlayerMelds(meldW),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('Your hand (${_e.playerHand.length})',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.75), fontSize: 12)),
            ),
            _buildHand(handW),
            const SizedBox(height: 4),
            _buildActions(),
            _buildMessageBar(),
            const SizedBox(height: 6),
          ],
        ),
      );
    });
  }

  Widget _chip(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.30),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: QCardColors.gold),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildHud() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: 'Back',
                iconSize: 26,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(widget.mode.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis),
              ),
              _chip('You ${_e.playerScore}', Icons.person),
              const SizedBox(width: 6),
              _chip('AI ${_e.aiScore}', Icons.smart_toy),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 2),
            child: Text(kGameFlavor,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11,
                    fontStyle: FontStyle.italic),
                overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Row(
              children: [
                _chip('R${_e.round}', Icons.layers),
                const SizedBox(width: 6),
                _chip('${_e.moves}', Icons.touch_app),
                const SizedBox(width: 6),
                if (!_isZen) _chip(_clock(), Icons.access_time),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hudButton(IconData icon, String tip, VoidCallback onTap) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        tooltip: tip,
        iconSize: 25,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _hudButton(Icons.refresh, 'New match', _newMatch),
          _hudButton(Icons.undo, 'Undo', _doUndo),
          _hudButton(Icons.lightbulb, 'Hint', () => _doHint()),
          _hudButton(Icons.pause, 'Pause',
              () => setState(() => _paused = true)),
        ],
      ),
    );
  }

  Widget _miniLabel(String text) {
    return Text(text,
        style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 12,
            fontWeight: FontWeight.w700));
  }

  Widget _countLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text,
          style: TextStyle(
              color: Colors.white.withOpacity(0.7), fontSize: 11)),
    );
  }

  Widget _buildAiZone(double meldW) {
    final n = _e.aiHand.length;
    final show = n > 8 ? 8 : n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _miniLabel('The Emerald Club — Rival'),
            const SizedBox(width: 8),
            Text('$n cards',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55), fontSize: 11)),
            const Spacer(),
            Text(_difficultyLabel(),
                style: TextStyle(
                    color: QCardColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (int i = 0; i < show; i++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: QCardBack(width: meldW),
              ),
            if (n > show)
              Text('+${n - show}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
          ],
        ),
        if (_e.aiMelds.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: meldW * 1.42 + 10,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (int mi = 0; mi < _e.aiMelds.length; mi++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _meldGroup(_e.aiMelds[mi], meldW, 2, mi),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _meldGroup(
      List<RummyCard> meld, double w, int side, int idx) {
    final selected = _selMeldSide == side && _selMeldIdx == idx;
    return GestureDetector(
      onTap: () => _selectMeld(side, idx),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.black.withOpacity(0.25),
          border: Border.all(
            color: selected ? QCardColors.gold : Colors.white.withOpacity(0.22),
            width: selected ? 2.4 : 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in meld)
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: QCardFace(
                    rank: c.rankLabel, suit: c.suitChar, width: w),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerMelds(double meldW) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _miniLabel(
            'Your melds line the green felt here. (${_e.playerMelds.length} groups)'),
        const SizedBox(height: 4),
        if (_e.playerMelds.isEmpty)
          Text('No melds yet: select 3+ cards to form a set or run.',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5), fontSize: 11)),
        if (_e.playerMelds.isNotEmpty)
          SizedBox(
            height: meldW * 1.42 + 10,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (int mi = 0; mi < _e.playerMelds.length; mi++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _meldGroup(_e.playerMelds[mi], meldW, 1, mi),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCenter(double midW) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: _drawStock,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _e.stock.isEmpty
                  ? QCardSlot(width: midW)
                  : QCardBack(width: midW),
              _countLabel('stock ${_e.stock.length}'),
            ],
          ),
        ),
        const SizedBox(width: 20),
        GestureDetector(
          onTap: _drawDiscard,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _e.discardPile.isEmpty
                  ? QCardSlot(width: midW)
                  : QCardFace(
                      rank: _e.discardPile.last.rankLabel,
                      suit: _e.discardPile.last.suitChar,
                      width: midW),
              _countLabel('discard'),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Container(
          constraints: const BoxConstraints(minWidth: 110, maxWidth: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.30),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_phaseText(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(_e.lastEvent,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHand(double handW) {
    return SizedBox(
      height: handW * 1.42 + 18,
      child: _e.playerHand.isEmpty
          ? Center(
              child: Text('Hand is empty.',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12)))
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _e.playerHand.length,
              itemBuilder: (ctx, i) {
                final c = _e.playerHand[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 6, top: 10),
                  child: GestureDetector(
                    onTap: () => _toggleHand(i),
                    child: QCardFace(
                      rank: c.rankLabel,
                      suit: c.suitChar,
                      width: handW,
                      selected: _sel.contains(i),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback? onTap,
      {bool primary = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          icon: Icon(icon,
              size: 18,
              color: primary ? QCardColors.bgDark : Colors.white),
          label: Text(label,
              style: TextStyle(
                  color: primary ? QCardColors.bgDark : Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: primary
                ? QCardColors.gold
                : Colors.white.withOpacity(0.12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: onTap,
        ),
      ),
    );
  }

  Widget _tip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white.withOpacity(0.65), fontSize: 13)),
    );
  }

  Widget _buildActions() {
    final bs = <Widget>[];
    if (_matchOver) {
      // handled by overlay
    } else if (_e.phase == 'draw' && !_busyAi) {
      bs.add(_tip('Tap the stock or the discard pile to draw.'));
    } else if (_e.phase == 'play' && !_busyAi) {
      bs.add(_actionButton('Meld (${_sel.length})', Icons.layers,
          _sel.length >= _e.cfg.meldMin ? _doMeld : null));
      bs.add(_actionButton('Auto', Icons.auto_awesome, _doAutoMeld));
      bs.add(_actionButton(
          'Lay Off',
          Icons.add_link,
          (_sel.length == 1 && _selMeldSide != 0 && _selMeldIdx >= 0)
              ? _doLayOff
              : null));
      bs.add(_actionButton('Discard', Icons.delete_outline,
          _sel.length == 1 ? _doDiscard : null));
      if (_e.cfg.knockEnabled) {
        bs.add(_actionButton('Knock', Icons.front_hand,
            _sel.length == 1 ? _doKnock : null));
        bs.add(_actionButton('Gin!', Icons.bolt,
            _e.canGin() ? _doGin : null));
      } else if (_e.canDeclare()) {
        bs.add(_actionButton('Declare', Icons.emoji_events, _doDeclare,
            primary: true));
      }
      bs.add(_actionButton('Sort', Icons.sort, _doSort));
    } else if (_busyAi || _e.phase == 'ai') {
      bs.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
            child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 3))),
      ));
    } else if (_e.phase == 'roundOver') {
      bs.add(_actionButton('Next Round', Icons.arrow_forward, _nextRound,
          primary: true));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: bs,
      ),
    );
  }

  Widget _buildMessageBar() {
    return SizedBox(
      height: 30,
      child: Center(
        child: AnimatedOpacity(
          opacity: _message.isEmpty ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(_message,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }

  Widget _overlayCard(Widget child) {
    return Container(
      color: Colors.black.withOpacity(0.62),
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 36),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: QCardColors.bgMid,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: QCardColors.gold.withOpacity(0.6), width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 24)
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _menuButton(String label, IconData icon, VoidCallback onTap,
      {bool primary = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon:
            Icon(icon, color: primary ? QCardColors.bgDark : Colors.white),
        label: Text(label,
            style: TextStyle(
                color: primary ? QCardColors.bgDark : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              primary ? QCardColors.gold : Colors.white.withOpacity(0.12),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildPauseOverlay() {
    return _overlayCard(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Paused',
            style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 6),
        Text(widget.mode.name,
            style: TextStyle(
                color: Colors.white.withOpacity(0.7), fontSize: 14)),
        const SizedBox(height: 18),
        _menuButton('Resume', Icons.play_arrow,
            () => setState(() => _paused = false),
            primary: true),
        const SizedBox(height: 10),
        _menuButton('New Match', Icons.refresh, () {
          setState(() => _paused = false);
          _newMatch();
        }),
        const SizedBox(height: 10),
        _menuButton('Quit to Menu', Icons.home,
            () => Navigator.of(context).maybePop()),
      ],
    ));
  }

  Widget _buildRoundOverlay() {
    return _overlayCard(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_e.roundWonByPlayer ? 'Round Won!' : 'Round Lost',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(_e.lastEvent,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withOpacity(0.85), fontSize: 14)),
        const SizedBox(height: 8),
        Text(
            'Round: you +${_e.lastRoundPlayer} · rival +${_e.lastRoundAi}\nMatch: you ${_e.playerScore} · rival ${_e.aiScore}',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withOpacity(0.75), fontSize: 13)),
        if (_isTournament)
          Text('Tournament: $_tournWins–$_tournLosses (first to 3)',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        _menuButton('Next Round', Icons.arrow_forward, _nextRound,
            primary: true),
        const SizedBox(height: 10),
        _menuButton('Back to Menu', Icons.home,
            () => Navigator.of(context).maybePop()),
      ],
    ));
  }

  int _starsForWin() {
    if (!_matchWon) return 1;
    if (_e.aiScore == 0) return 3;
    return 2;
  }

  Widget _buildMatchOverlay() {
    final stars = _starsForWin();
    return _overlayCard(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.5, end: 1.0),
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          builder: (context, v, child) =>
              Transform.scale(scale: v, child: child),
          child: Text(_matchWon ? 'You Win!' : 'Rival Wins',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900)),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < 3; i++)
              Icon(Icons.star,
                  size: 40,
                  color: i < stars
                      ? QCardColors.gold
                      : Colors.white.withOpacity(0.25)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
            'Final: you ${_e.playerScore} · rival ${_e.aiScore}\n${_e.moves} moves · ${_clock()}',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withOpacity(0.85), fontSize: 14)),
        if (_isLadder)
          Text('Ladder rung: $_ladderRung / 8',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        const SizedBox(height: 18),
        _menuButton('Play Again', Icons.refresh, _newMatch, primary: true),
        const SizedBox(height: 10),
        _menuButton('Back to Menu', Icons.home,
            () => Navigator.of(context).maybePop()),
      ],
    ));
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  _ConfettiPainter(this.particles);
  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final paint = Paint()..color = p.color;
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset(p.x * size.width, p.y * size.height),
            width: p.size,
            height: p.size * 0.6),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
