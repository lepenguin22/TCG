import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../games/card_catalog.dart';
import '../games/game_definition.dart';
import '../games/games.dart';
import '../models/card_definition.dart';
import '../models/deck.dart';
import '../playtest/playtest_controller.dart';
import '../playtest/playtest_engine.dart';
import '../playtest/playtest_state.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/card_image.dart';
import '../widgets/common.dart';

/// The playtest board.
///
/// Laid out the way the game sits on a table: the opponent's field across the
/// top, yours below it, your hand along the bottom. What you can do is driven
/// by the phase, so the screen only ever offers legal moves and the buttons
/// tell you what the rules are waiting for.
class PlaytestScreen extends StatefulWidget {
  const PlaytestScreen({
    super.key,
    required this.yourDeck,
    required this.opponentDeck,
    this.turnOrder = TurnOrder.youFirst,
    this.mode = PlaytestMode.vsCpu,
    this.random,
  });

  final Deck yourDeck;
  final Deck opponentDeck;

  /// Who plays the far side: the CPU, or you with both hands.
  final PlaytestMode mode;

  /// Who takes turn one. Kept as the choice rather than the outcome, so a
  /// random order is rolled again on every restart.
  final TurnOrder turnOrder;

  /// The shuffle. Left unset in the app, where a game should be a fresh one
  /// every time; fixed by the tests, so a board they drive is the same board
  /// on every run rather than one that usually happens to work.
  final Random? random;

  @override
  State<PlaytestScreen> createState() => _PlaytestScreenState();
}

class _PlaytestScreenState extends State<PlaytestScreen> {
  PlaytestController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= PlaytestController(
      store: context.read<DeckStore>(),
      yourDeck: widget.yourDeck,
      opponentDeck: widget.opponentDeck,
      turnOrder: widget.turnOrder,
      mode: widget.mode,
      random: widget.random,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    return ChangeNotifierProvider<PlaytestController>.value(
      value: controller,
      child: Consumer<PlaytestController>(
        builder: (context, game, _) {
          return PopScope(
            // A game is a board you cannot get back: leaving it throws away
            // the hands, the field and everything applied by hand, and a
            // back press is easy to make by accident on a phone. A finished
            // game has nothing left to lose, so that one leaves at once.
            canPop: game.stage == PlaytestStage.over,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              final leave = await _confirmLeaving(context);
              if (leave && context.mounted) Navigator.of(context).pop();
            },
            child: Scaffold(
              appBar: AppBar(
                title: Text(
                  game.stage == PlaytestStage.mulligan
                      ? game.bothSides
                            ? '${game.mulliganSide.name}\u2019s opening hand'
                            : 'Opening hand'
                      : 'Turn ${game.state.turn} · ${game.state.active.name}',
                ),
                // The turn as a bar of phases, always on screen rather than
                // scrolling away with the board.
                bottom: game.stage == PlaytestStage.mulligan
                    ? null
                    : _PhaseBar(game: game),
                actions: [
                  IconButton(
                    tooltip: 'Game log',
                    icon: const Icon(Icons.receipt_long_outlined),
                    onPressed: () => _showLog(context, game),
                  ),
                  IconButton(
                    tooltip: 'Restart',
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _restart(context),
                  ),
                ],
              ),
              body: SafeArea(
                child: game.stage == PlaytestStage.mulligan
                    ? _Mulligan(game: game)
                    : _Board(game: game),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Asks before a game is thrown away.
  static Future<bool> _confirmLeaving(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Leave the game?'),
        content: const Text(
          'The board goes with it — both hands, both fields and everything '
          'applied by hand. The decks in your library are not touched.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  void _restart(BuildContext context) {
    setState(() {
      _controller?.dispose();
      _controller = PlaytestController(
        store: context.read<DeckStore>(),
        yourDeck: widget.yourDeck,
        opponentDeck: widget.opponentDeck,
        turnOrder: widget.turnOrder,
        mode: widget.mode,
      );
    });
  }

  static void _showLog(BuildContext context, PlaytestController game) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scrollController) => ListView.builder(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          itemCount: game.state.log.length,
          itemBuilder: (_, index) {
            final entry = game.state.log[game.state.log.length - 1 - index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                entry.text,
                style: TextStyle(
                  color: entry.text.startsWith('---')
                      ? AppColors.text
                      : AppColors.textMuted,
                  fontWeight: entry.text.startsWith('---')
                      ? FontWeight.w700
                      : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The colour a phase is shown in, on the phase bar and around the board of
/// whoever is playing.
///
/// One colour per phase, so a glance at the board says where the turn is
/// without reading anything. Colour is never the only cue: the phase bar
/// names the phase as well, for a player who cannot tell two of these apart.
Color phaseColor(PlaytestPhase phase) => switch (phase) {
  PlaytestPhase.stand => const Color(0xFF6FA8DC),
  PlaytestPhase.draw => const Color(0xFF4FC08D),
  PlaytestPhase.ride => const Color(0xFF8C6BD1),
  PlaytestPhase.main => const Color(0xFFF0C24B),
  PlaytestPhase.battle => const Color(0xFFE4573D),
  PlaytestPhase.end => const Color(0xFF9AA5B1),
  PlaytestPhase.mulligan || PlaytestPhase.over => AppColors.textFaint,
};

/// The phases of a turn in order, as the bar shows them. The mulligan is not
/// one of them -- it happens before the first turn starts -- and neither is
/// the end of the game.
const _turnPhases = [
  PlaytestPhase.stand,
  PlaytestPhase.draw,
  PlaytestPhase.ride,
  PlaytestPhase.main,
  PlaytestPhase.battle,
  PlaytestPhase.end,
];

/// The turn laid out as six segments, with the one being played lit up.
///
/// Equal segments rather than a row of chips: the bar has to fit a narrow
/// phone, and one that scrolls could carry the lit segment off the edge --
/// which is the one thing it is there to show.
class _PhaseBar extends StatelessWidget implements PreferredSizeWidget {
  const _PhaseBar({required this.game});

  final PlaytestController game;

  @override
  Size get preferredSize => const Size.fromHeight(30);

  @override
  Widget build(BuildContext context) {
    final phase = game.state.phase;
    final current = _turnPhases.indexOf(phase);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          for (final (index, each) in _turnPhases.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _PhaseSegment(
                  phase: each,
                  // Where the turn has got to: the phase being played is lit,
                  // the ones already gone are dimmed rather than blank, so the
                  // bar reads as a turn in progress and not as six buttons.
                  state: each == phase
                      ? _SegmentState.now
                      : (current >= 0 && index < current)
                      ? _SegmentState.done
                      : _SegmentState.ahead,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _SegmentState { done, now, ahead }

class _PhaseSegment extends StatelessWidget {
  const _PhaseSegment({required this.phase, required this.state});

  final PlaytestPhase phase;
  final _SegmentState state;

  @override
  Widget build(BuildContext context) {
    final color = phaseColor(phase);
    final lit = state == _SegmentState.now;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lit
            ? color
            : state == _SegmentState.done
            ? color.withValues(alpha: 0.18)
            : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            phase.label,
            key: ValueKey('phase-${phase.name}'),
            maxLines: 1,
            style: TextStyle(
              // Dark text on the lit segment: these colours are bright, and
              // white on gold is not readable.
              color: lit ? AppColors.bg : AppColors.textMuted,
              fontSize: 11,
              fontWeight: lit ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// One player's half of the board, framed while it is their turn.
///
/// The frame is the phase's colour, so whose turn it is and what part of it
/// they are in are the same glance.
class _SideFrame extends StatelessWidget {
  const _SideFrame({
    required this.game,
    required this.side,
    required this.children,
  });

  final PlaytestController game;
  final PlaytestSide side;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theirs = game.state.active == side && !game.state.isOver;
    final color = phaseColor(game.state.phase);
    return AnimatedContainer(
      key: ValueKey('frame-${side.name}'),
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: theirs ? color.withValues(alpha: 0.05) : null,
        border: Border.all(
          color: theirs ? color : AppColors.border,
          width: theirs ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }
}

// --------------------------------------------------------------------- mulligan

class _Mulligan extends StatelessWidget {
  const _Mulligan({required this.game});

  final PlaytestController game;

  @override
  Widget build(BuildContext context) {
    final side = game.mulliganSide;
    final hand = side.hand;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                game.bothSides
                    ? side.goesFirst
                          ? '${side.name} goes first.'
                          : '${side.name} goes second, and is paid three '
                                'energy for it.'
                    : side.goesFirst
                    ? 'You go first.'
                    : 'The CPU goes first, so you are paid three energy.',
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tap the cards you want to put back, then keep the rest. '
                'They are shuffled away and replaced.',
                style: TextStyle(color: AppColors.textMuted, height: 1.4),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.count(
            padding: const EdgeInsets.all(16),
            crossAxisCount: 3,
            childAspectRatio: cardAspectRatio,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (final card in hand)
                _HandCard(
                  card: card,
                  selected: game.mulliganPicks.contains(card),
                  onTap: () => game.togglePick(card),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: game.confirmMulligan,
              child: Text(
                game.mulliganPicks.isEmpty
                    ? 'Keep this hand'
                    : 'Put ${game.mulliganPicks.length} back',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    required this.card,
    required this.onTap,
    this.selected = false,
  });

  final GameCard card;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Opacity(
          opacity: selected ? 0.55 : 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CardImage(url: card.imageUrl, width: 200),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'G${card.grade} · ${card.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------------ board

class _Board extends StatelessWidget {
  const _Board({required this.game});

  final PlaytestController game;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                _SideFrame(
                  game: game,
                  side: game.cpu,
                  children: [
                    _SideSummary(side: game.cpu, game: game),
                    const SizedBox(height: 6),
                    _ZoneRail(game: game, side: game.cpu),
                    const SizedBox(height: 8),
                    _Field(game: game, side: game.cpu, isYours: false),
                  ],
                ),
                const SizedBox(height: 10),
                _Middle(game: game),
                const SizedBox(height: 10),
                _SideFrame(
                  game: game,
                  side: game.you,
                  children: [
                    _Field(game: game, side: game.you, isYours: true),
                    const SizedBox(height: 8),
                    _ZoneRail(game: game, side: game.you),
                    const SizedBox(height: 6),
                    _SideSummary(side: game.you, game: game),
                  ],
                ),
              ],
            ),
          ),
        ),
        _Hand(game: game),
        _Controls(game: game),
      ],
    );
  }
}

/// The damage, hand size, deck size and energy for one player.
class _SideSummary extends StatelessWidget {
  const _SideSummary({required this.side, required this.game});

  final PlaytestSide side;
  final PlaytestController game;

  @override
  Widget build(BuildContext context) {
    // A Wrap rather than a Row: six counters do not fit across a narrow
    // phone, and a summary that runs off the edge of the board is worse than
    // one that takes a second line.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 2,
      children: [
        Text(
          side.name,
          style: const TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        // Whose turn it is, said again beside the name: the frame around this
        // half says so too, but the board scrolls and its edge can be off
        // screen while the summary is not.
        if (game.state.active == side && !game.state.isOver)
          _TurnMarker(phase: game.state.phase),
        _Pip(
          label: 'Dmg',
          value: '${side.damageCount}/6',
          danger: side.damageCount >= 5,
        ),
        _Pip(label: 'Hand', value: '${side.hand.length}'),
        // Energy is only ever gained by an ability, so it is a counter the
        // player keeps rather than something the board can work out. Tap to
        // add one, hold to take one away.
        GestureDetector(
          onTap: () => game.setEnergy(side, side.energy + 1),
          onLongPress: () => game.setEnergy(side, side.energy - 1),
          child: _Pip(label: 'Energy', value: '${side.energy}', tappable: true),
        ),
      ],
    );
  }
}

/// A pill beside a player's name saying the turn is theirs, and where in it
/// they are.
class _TurnMarker extends StatelessWidget {
  const _TurnMarker({required this.phase});

  final PlaytestPhase phase;

  @override
  Widget build(BuildContext context) {
    final color = phaseColor(phase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        phase == PlaytestPhase.mulligan ? 'To play' : phase.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip({
    required this.label,
    required this.value,
    this.danger = false,
    this.tappable = false,
  });

  final String label;
  final String value;
  final bool danger;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
        ),
        Text(
          value,
          style: TextStyle(
            color: danger
                ? AppColors.danger
                : (tappable ? AppColors.accent : AppColors.text),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The zones that sit beside the field: the damage row, and the piles.
///
/// These are half the game once abilities come into it -- a counter-blast pays
/// out of damage, a soul-blast out of soul, a search goes through the deck --
/// so they are on the board and tappable rather than left as numbers.
class _ZoneRail extends StatelessWidget {
  const _ZoneRail({required this.game, required this.side});

  final PlaytestController game;
  final PlaytestSide side;

  @override
  Widget build(BuildContext context) {
    // The damage zone gets a line of its own, with the piles wrapped below
    // it. Sharing one line meant every pile took a fixed width and the damage
    // took whatever was left, so a game that removed a card grew another pile
    // and squeezed the damage zone -- the one thing on the rail that says how
    // close someone is to losing -- down to a sliver.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: ValueKey('damage-${side.name}'),
          onTap: () => _showDamageSheet(context, game, side),
          behavior: HitTestBehavior.opaque,
          child: _DamageRow(side: side),
        ),
        const SizedBox(height: 4),
        Wrap(
          key: ValueKey('piles-${side.name}'),
          spacing: 4,
          runSpacing: 4,
          children: _piles(context),
        ),
      ],
    );
  }

  /// The piles beside the field, in the order they are reached for.
  List<Widget> _piles(BuildContext context) {
    return [
      _Pile(
        label: 'Deck',
        count: side.deck.length,
        onTap: () => _showDeckSheet(context, game, side),
      ),
      _Pile(
        label: 'Drop',
        count: side.drop.length,
        onTap: () => _showPileSheet(
          context,
          game,
          side,
          title: 'Drop zone',
          cards: side.drop,
          actionLabel: 'To hand',
          onAction: (card) => game.returnFromDrop(side, card),
          callable: true,
          bottomable: true,
          fromDrop: true,
        ),
      ),
      _Pile(
        label: 'Soul',
        count: side.soul.length,
        onTap: () => _showSoulSheet(context, game, side),
      ),
      // The crest. Shown even with none in play, since an empty crest zone
      // is where one gets played from -- a deck that brings no crest of its
      // own is exactly the deck that wants to choose one.
      _Pile(
        label: 'Crest',
        count: side.crestInPlay ? side.energy : 0,
        highlight: side.crestInPlay,
        onTap: () => _showCrestSheet(context, game, side),
      ),
      // Tickets are in no deck and on no pile: an ability makes one out of
      // nothing. The button is always there, since a deck that wants one
      // wants it on a turn the board cannot predict.
      if (game.controls(side))
        _Pile(
          label: 'Tickets',
          count: side.hand.where((c) => c.isTicket).length,
          onTap: () => _showTokenSheet(context, game, side),
        ),
      // Cards removed from the game, which only an over trigger does. The
      // pile appears once there is something in it, since a game with none
      // does not need the space.
      if (side.removed.isNotEmpty)
        _Pile(
          label: 'Removed',
          count: side.removed.length,
          onTap: () => _showPileSheet(
            context,
            game,
            side,
            title: 'Removed from the game',
            cards: side.removed,
            header: (_) => [
              const Text(
                'An over trigger is removed as it resolves, rather than '
                'reaching hand from a drive check or the damage zone from '
                'a damage one. Nothing comes back from here.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      // Only a deck that strides has a G zone, so it only appears for one.
      if (side.gZone.isNotEmpty)
        _Pile(
          // Face up over total: the face-up half is the number an ability
          // counting a Generation Break is asking about.
          label: side.generationBreak > 0 ? 'G ↑${side.generationBreak}' : 'G',
          count: side.gZone.length,
          highlight: game.engine.canStride(side),
          onTap: () => _showGZoneSheet(context, game, side),
        ),
    ];
  }
}

/// The damage zone, laid out as the cards it is rather than a number.
///
/// All six places are drawn, taken or not: how close someone is to losing is
/// the gap between what is filled and the sixth box, and a row that grew a
/// box at a time made that something to count rather than something to see.
/// A card turned face down has been spent on a counter-blast.
class _DamageRow extends StatelessWidget {
  const _DamageRow({required this.side});

  final PlaytestSide side;

  /// The sixth card is the game, so the row says so before it gets there.
  static const _lethal = 6;

  @override
  Widget build(BuildContext context) {
    final taken = side.damage.length;
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              taken == 0 ? 'No damage' : 'Damage $taken/$_lethal',
              style: TextStyle(
                color: taken >= 5 ? AppColors.danger : AppColors.textFaint,
                fontSize: 11,
                fontWeight: taken >= 5 ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          for (var index = 0; index < _lethal; index += 1)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: _DamageBox(
                // Past the end of the damage taken, this place is empty; up
                // to it, the card is either standing or spent.
                state: index >= taken
                    ? _DamageState.empty
                    : side.isSpent(side.damage[index])
                    ? _DamageState.spent
                    : _DamageState.taken,
              ),
            ),
        ],
      ),
    );
  }
}

enum _DamageState { empty, spent, taken }

class _DamageBox extends StatelessWidget {
  const _DamageBox({required this.state});

  final _DamageState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 28,
      decoration: BoxDecoration(
        color: switch (state) {
          // An empty place is a hole in the row rather than a card, so it is
          // the board's own colour and not the surface the cards sit on.
          _DamageState.empty => Colors.transparent,
          _DamageState.spent => AppColors.surface,
          _DamageState.taken => AppColors.danger.withValues(alpha: 0.75),
        },
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: switch (state) {
            _DamageState.empty => AppColors.border.withValues(alpha: 0.6),
            _DamageState.spent => AppColors.border,
            _DamageState.taken => AppColors.danger,
          },
        ),
      ),
    );
  }
}

class _Pile extends StatelessWidget {
  const _Pile({
    required this.label,
    required this.count,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final int count;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: highlight ? AppColors.accent : AppColors.border,
            width: highlight ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.textFaint, fontSize: 9),
            ),
            Text(
              '$count',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sheet listing the cards in a zone, with one action per card.
void _showPileSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side, {
  required String title,
  required List<GameCard> cards,
  String? actionLabel,
  void Function(GameCard card)? onAction,
  List<Widget> Function(BuildContext sheetContext)? header,
  bool callable = false,
  bool bottomable = false,
  bool fromDrop = false,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          SectionHeader(title: '$title (${cards.length})'),
          ...?header?.call(sheetContext),
          if (cards.isEmpty)
            const Text('Empty.', style: TextStyle(color: AppColors.textMuted)),
          // The actions sit under each card rather than beside it: a pile
          // can offer three of them, which will not fit alongside a card
          // name on a phone.
          for (final card in cards.reversed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardImage(url: card.imageUrl, width: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.name,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Grade ${card.grade}'
                          '${card.trigger == null ? '' : ' · ${card.trigger} trigger'}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            // Abilities call out of the deck, the drop and
                            // the soul as readily as out of hand, so every
                            // pile offers it for a unit that could legally
                            // be called.
                            if (callable &&
                                game.controls(side) &&
                                game.engine.canCall(
                                  side,
                                  card,
                                  Circle.frontLeft,
                                ))
                              TextButton(
                                onPressed: () {
                                  game.hold(card);
                                  Navigator.of(sheetContext).pop();
                                },
                                child: const Text('Call'),
                              ),
                            if (onAction != null)
                              TextButton(
                                onPressed: () {
                                  onAction(card);
                                  Navigator.of(sheetContext).pop();
                                },
                                child: Text(actionLabel ?? 'Move'),
                              ),
                            // Cards work from the drop zone: an order played
                            // a second time, a unit with an "[ACT](Drop)"
                            // ability whose cost is removing itself. Which
                            // cards can is on the card, so the board offers
                            // it and the player reads the text -- and either
                            // way it leaves the game rather than going back
                            // to the drop.
                            if (fromDrop && game.controls(side))
                              TextButton(
                                onPressed: () {
                                  game.activateFromDrop(side, card);
                                  Navigator.of(sheetContext).pop();
                                },
                                child: Text(
                                  card.isOrder
                                      ? 'Play from drop'
                                      : 'Activate from drop',
                                ),
                              ),
                            // The other half of those abilities: a cost that
                            // removes cards from the drop which are not the
                            // one being played.
                            if (fromDrop && game.controls(side))
                              TextButton(
                                onPressed: () {
                                  game.removeFromDrop(side, card);
                                  Navigator.of(sheetContext).pop();
                                },
                                child: const Text('Remove'),
                              ),
                            // Costs put cards under the deck out of the drop
                            // and the soul as well as out of hand.
                            if (bottomable && game.controls(side))
                              TextButton(
                                onPressed: () {
                                  game.bottomDeck(side, card);
                                  Navigator.of(sheetContext).pop();
                                },
                                child: const Text('To bottom'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

void _showDamageSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  _showPileSheet(
    context,
    game,
    side,
    title: 'Damage zone',
    cards: side.damage,
    header: (sheetContext) => [
      Text(
        '${side.openDamage} of ${side.damageCount} face up. '
        'A counter-blast turns damage face down to pay for an ability.',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: () {
              game.counterBlast(side, 1);
              Navigator.of(sheetContext).pop();
            },
            child: const Text('Counter-blast 1'),
          ),
          OutlinedButton(
            onPressed: () {
              game.counterBlast(side, 2);
              Navigator.of(sheetContext).pop();
            },
            child: const Text('Counter-blast 2'),
          ),
          OutlinedButton(
            onPressed: () {
              game.counterCharge(side, 1);
              Navigator.of(sheetContext).pop();
            },
            child: const Text('Counter-charge 1'),
          ),
          OutlinedButton(
            onPressed: () {
              game.dealDamage(side);
              Navigator.of(sheetContext).pop();
            },
            child: const Text('Take damage'),
          ),
        ],
      ),
      const SizedBox(height: 12),
    ],
  );
}

void _showSoulSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  _showPileSheet(
    context,
    game,
    side,
    title: 'Soul',
    cards: side.soul,
    actionLabel: 'Soul-blast',
    onAction: (card) => game.soulBlast(side, card),
    callable: true,
    bottomable: true,
    header: (sheetContext) => [
      OutlinedButton(
        onPressed: () {
          game.soulCharge(side, 1);
          Navigator.of(sheetContext).pop();
        },
        child: const Text('Soul-charge 1'),
      ),
      const SizedBox(height: 12),
    ],
  );
}

/// The deck: what can be done to it without looking at it.
///
/// Drawing is the common thing and looking is the rare one, so the list of
/// every card comes up only when it is asked for. Opening the deck to draw a
/// card meant reading the whole deck to take the top of it, which is not a
/// thing the game lets anyone do.
void _showDeckSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      // Scrollable: four actions and a heading do not fit a short screen,
      // and a sheet that overflows shows a stripe instead of a button.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: 'Deck (${side.deck.length})',
              caption: side.deck.isEmpty
                  ? 'Empty. The next card drawn loses the game.'
                  : null,
            ),
            _SheetAction(
              icon: Icons.download_outlined,
              label: 'Draw a card',
              detail: 'The top card, face down to everyone but you.',
              onTap: () {
                game.drawCard(side);
                Navigator.of(sheetContext).pop();
              },
            ),
            _SheetAction(
              icon: Icons.shuffle,
              label: 'Shuffle',
              detail: 'For an ability that says to.',
              onTap: () {
                game.shuffleDeck(side);
                Navigator.of(sheetContext).pop();
              },
            ),
            _SheetAction(
              icon: Icons.vertical_align_top,
              label: 'Look at the top cards',
              detail:
                  'Three, five or seven, in order — and take what the card '
                  'says out of them.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showTopOfDeckSheet(context, game, side);
              },
            ),
            _SheetAction(
              icon: Icons.search,
              label: 'Look through the deck',
              detail:
                  'Every card, to search or to call one. '
                  'Only when a card tells you to.',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showDeckSearchSheet(context, game, side);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// The tickets a game hands out, which are in no deck.
///
/// "Put a Persona Shield ticket into your hand" makes a card out of nothing,
/// so there is nowhere on the board to take one from. This is that nowhere,
/// and the cards come from the database rather than from anything written
/// here: a ticket says what it is on its own face -- "(This card is a ticket
/// card, and cannot be put in a deck)" -- so a set that prints another is
/// picked up without the app being taught about it.
void _showTokenSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  final definition = gameById(game.gameId);
  final store = context.read<DeckStore>();
  final fromLibrary = store.cards
      .where((card) => card.gameId == definition.id && _isTicket(card))
      .toList();
  final options = _ticketOptions(context, definition);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scrollController) => FutureBuilder<List<CatalogCard>>(
          future: options,
          builder: (builderContext, snapshot) {
            final tickets = <CardDefinition>[
              ...fromLibrary,
              for (final entry in snapshot.data ?? const <CatalogCard>[])
                if (!fromLibrary.any((c) => c.name == entry.name))
                  CardDefinition(
                    id: 'catalog:${entry.attributes['cardNo'] ?? entry.name}',
                    gameId: definition.id,
                    name: entry.name,
                    attributes: entry.attributes,
                    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
                    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
                  ),
            ];

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const SectionHeader(
                  title: 'Tickets',
                  caption:
                      'Cards in no deck: an ability makes one and puts it '
                      'into your hand. Take one when a card says to.',
                ),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Text(
                    'Reading the card database…',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                if (snapshot.connectionState != ConnectionState.waiting &&
                    tickets.isEmpty)
                  const Text(
                    'The database knows no ticket cards.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                for (final ticket in tickets)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CardImage(
                      url: ticket.attributes['imageUrl'],
                      width: 32,
                    ),
                    title: Text(
                      ticket.name,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      [
                        ticket.attributes['cardNo'],
                        if ((ticket.attributes['shield'] ?? '').isNotEmpty)
                          '${ticket.attributes['shield']} shield',
                      ].whereType<String>().join(' · '),
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () {
                        game.addToken(side, ticket);
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('To hand'),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// A ticket says so on its own face, which is how one is told from a card
/// that merely mentions tickets.
bool _isTicket(CardDefinition card) => (card.attributes['effect'] ?? '')
    .toLowerCase()
    .contains('is a ticket card');

/// The ticket cards the database knows, or none where it is not there to be
/// read -- a test, or a build with no catalog.
Future<List<CatalogCard>> _ticketOptions(
  BuildContext context,
  GameDefinition game,
) async {
  final asset = game.catalogAsset;
  if (asset == null) return const [];
  final catalog = context.read<CardCatalog?>();
  if (catalog == null) return const [];
  final cards = await catalog.load(asset);
  return cards
      .where(
        (card) => (card.attributes['effect'] ?? '').toLowerCase().contains(
          'is a ticket card',
        ),
      )
      .toList();
}

/// The top few cards of the deck, in order, for the abilities that look at
/// them.
///
/// "Look at the top five cards of your deck, choose up to one, put it into
/// your hand" is one of the commonest shapes in the game, and the whole point
/// is that it is the *top* cards rather than the whole deck: what you leave
/// stays where it was, in the order it was in.
void _showTopOfDeckSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  // Five to begin with, because most of these abilities say five, and typed
  // over for the ones that say something else. Cards say every number from
  // one to a dozen, and a chip each was never going to cover them.
  var looking = game.engine.topOfDeck(side, 5);
  final howMany = TextEditingController(text: '5');

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scrollController) => StatefulBuilder(
          builder: (builderContext, setSheetState) => ListenableBuilder(
            listenable: game,
            builder: (_, _) {
              // What is still there: a card taken drops out of the list
              // rather than being replaced from underneath.
              final showing = looking.where(side.deck.contains).toList();
              return ListView(
                controller: scrollController,
                // Padded out from under the keyboard the number box brings
                // up, so the cards being looked at are not behind it.
                padding: EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  24 + MediaQuery.viewInsetsOf(builderContext).bottom,
                ),
                children: [
                  SectionHeader(
                    // However many were asked for, this is how many there
                    // were: a deck of three answers "look at the top five"
                    // with three.
                    title: 'Top ${looking.length} of the deck',
                    caption: showing.length == looking.length
                        ? 'The top card first. What you leave stays in the '
                              'order it is in — shuffle below if the card '
                              'says to.'
                        : '${showing.length} of ${looking.length} left to '
                              'choose from. Nothing new is turned over; what '
                              'you leave stays in the order it is in.',
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: TextField(
                          controller: howMany,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'How many',
                            isDense: true,
                          ),
                          // A different number is a different look, so the
                          // window is read again as it is typed. Nothing is
                          // moved by looking, so reading it again costs
                          // nothing and a half-typed number puts nothing
                          // wrong on the screen.
                          onChanged: (typed) {
                            final wanted = int.tryParse(typed);
                            if (wanted == null || wanted < 1) return;
                            setSheetState(
                              () =>
                                  looking = game.engine.topOfDeck(side, wanted),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'cards from the top of the deck',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (showing.isEmpty)
                    Text(
                      looking.isEmpty
                          ? 'The deck is empty.'
                          : 'All of them have been taken.',
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  for (final card in showing)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CardImage(url: card.imageUrl, width: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  card.name,
                                  style: const TextStyle(
                                    color: AppColors.text,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'Grade ${card.grade}'
                                  '${card.trigger == null ? '' : ' · ${card.trigger} trigger'}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    for (final pick in [
                                      (DeckPick.hand, 'To hand'),
                                      (DeckPick.drop, 'To drop'),
                                      (DeckPick.soul, 'To soul'),
                                      (DeckPick.bottom, 'To bottom'),
                                    ])
                                      TextButton(
                                        onPressed: () => game.takeFromTop(
                                          side,
                                          card,
                                          pick.$1,
                                        ),
                                        child: Text(pick.$2),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          game.shuffleDeck(side);
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Shuffle and close'),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Leave the order'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  ).whenComplete(howMany.dispose);
}

/// The whole deck, listed, for the abilities that search it.
void _showDeckSearchSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  _showPileSheet(
    context,
    game,
    side,
    title: 'Deck',
    cards: side.deck,
    actionLabel: 'To hand',
    onAction: (card) => game.searchDeck(side, card),
    callable: true,
    header: (sheetContext) => [
      const Text(
        'The whole deck: take a card to hand, or call it straight to a circle '
        'where the card says to. It shuffles itself either way.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      const SizedBox(height: 12),
    ],
  );
}

/// The crest zone: what is in it, what it charges, and what can be added.
///
/// A zone rather than a slot, because a player can hold more than one crest at
/// once -- the Energy Generator out of the ride deck and a stride deck's own
/// crest beside it. Playing the second must not cost the first, so this shows
/// what is there and offers what else could be, rather than making one crest
/// the only crest.
void _showCrestSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  final definition = gameById(game.gameId);
  final store = context.read<DeckStore>();
  final fromLibrary = store.cards
      .where(
        (card) =>
            card.gameId == definition.id &&
            _crestTypes.contains(card.attributes['cardType']),
      )
      .toList();
  // Asked for once rather than on every rebuild: the sheet redraws whenever
  // the board changes, and a fresh future each time would reload the card
  // database under the reader.
  final crestOptions = _crestOptions(context, definition);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        // Listening to the board, so spending energy or changing the cap
        // shows in the numbers at the top of this sheet rather than waiting
        // for it to be closed and opened again.
        builder: (_, scrollController) => ListenableBuilder(
          listenable: game,
          builder: (_, _) => FutureBuilder<List<CatalogCard>>(
            future: crestOptions,
            builder: (builderContext, snapshot) {
              final catalogCrests = snapshot.data ?? const <CatalogCard>[];
              final options = <CardDefinition>[
                ...fromLibrary,
                for (final entry in catalogCrests)
                  if (!fromLibrary.any((c) => c.name == entry.name))
                    CardDefinition(
                      id: 'catalog:${entry.attributes['cardNo'] ?? entry.name}',
                      gameId: definition.id,
                      name: entry.name,
                      attributes: entry.attributes,
                      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
                      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
                    ),
              ];

              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  SectionHeader(
                    title: 'Crest zone (${side.crestZone.length})',
                    caption: '${side.energy} of ${side.energyCap} energy',
                  ),
                  if (side.rideCrest != null)
                    Text(
                      '${side.rideCrest!.name} is still in the ride deck. It '
                      'reaches the crest zone on the first ride — which is why '
                      'whoever goes first charges nothing on turn one.',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  if (side.crestZone.isEmpty && side.rideCrest == null)
                    const Text(
                      'Empty. A ride deck crest puts itself here on the first '
                      'ride; a stride deck\'s crest is put here by an ability, '
                      'so you play it below when that ability fires.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),

                  // What is in the zone, each with what it charges and a way
                  // back out. One crest leaving never disturbs the others.
                  for (final crest in side.crestZone) ...[
                    const SizedBox(height: 14),
                    _CardHeading(card: crest),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            game.engine.chargeOf(crest) == 0
                                ? 'Charges no energy of its own — what it does '
                                      'is on the card.'
                                : 'Charges ${game.engine.chargeOf(crest)} at the '
                                      'beginning of every ride phase, on its own.',
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            game.removeCrest(side, crest);
                            Navigator.of(sheetContext).pop();
                          },
                          child: const Text('Take it out'),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 14),
                  const Text(
                    'Spending it is an ability, so it is yours to apply',
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final cost in [1, 2, 3, 7])
                        OutlinedButton(
                          onPressed: side.energy < cost
                              ? null
                              : () => game.setEnergy(side, side.energy - cost),
                          child: Text('Blast $cost'),
                        ),
                      OutlinedButton(
                        onPressed: () => game.setEnergy(side, side.energy + 1),
                        child: const Text('Charge 1'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  const Text(
                    'How much you may hold',
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The Energy Generator says ten. A card that raises the '
                    'maximum -- "gets +5" -- is played to '
                    '${PlaytestSide.baseEnergyCap + 5}, and the new cap stays '
                    'until you change it back.',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: side.energyCap == 15
                            ? null
                            : () => game.setEnergyCap(side, 15),
                        child: const Text('Cap 15'),
                      ),
                      OutlinedButton(
                        onPressed: side.energyCap == PlaytestSide.baseEnergyCap
                            ? null
                            : () => game.setEnergyCap(
                                side,
                                PlaytestSide.baseEnergyCap,
                              ),
                        child: const Text('Cap 10'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            game.setEnergyCap(side, side.energyCap + 1),
                        child: const Text('+1 cap'),
                      ),
                      OutlinedButton(
                        onPressed: side.energyCap <= 1
                            ? null
                            : () => game.setEnergyCap(side, side.energyCap - 1),
                        child: const Text('-1 cap'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),
                  const Text(
                    'Play a crest',
                    style: TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Added to the crest zone beside whatever is already there.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Reading the card database…',
                        style: TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (snapshot.connectionState != ConnectionState.waiting &&
                      options.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'No crest to play. Add one to your library and it will '
                        'show up here.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  for (final option in options)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CardImage(
                        url: option.attributes['imageUrl'],
                        width: 32,
                      ),
                      title: Text(
                        option.name,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        option.attributes['effect']?.split('\n').first ??
                            'A crest.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          game.playCrest(side, option);
                          Navigator.of(sheetContext).pop();
                        },
                        child: const Text('Play'),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

/// What counts as a crest: the ride deck crest a Divinez deck carries, and
/// the crest a Stride Deckset's own ability puts into the crest zone --
/// DZ-SS03/T01EN Nightrose and its like, which are what let those decks
/// stride at all.
const _crestTypes = {'ride-deck-crest', 'crest'};

/// The crests the card database knows, or none where it is not
/// there to be read -- a test, or a build with no catalog.
Future<List<CatalogCard>> _crestOptions(
  BuildContext context,
  GameDefinition game,
) async {
  final asset = game.catalogAsset;
  if (asset == null) return const [];
  final catalog = context.read<CardCatalog?>();
  if (catalog == null) return const [];
  final cards = await catalog.load(asset);
  return cards
      .where((card) => _crestTypes.contains(card.attributes['cardType']))
      .toList();
}

/// The G zone, and the stride it exists for.
void _showGZoneSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  final yours = game.controls(side);
  final canStride = yours && game.engine.canStride(side);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          SectionHeader(
            title: 'G zone (${side.gZone.length})',
            caption: '${side.generationBreak} face up',
          ),
          Text(
            canStride
                ? 'Pick a G unit to stride, then discard cards worth grade 3 '
                      'or more between them to pay for it. Striding again '
                      'over a stride is allowed: the unit standing there '
                      'goes back face up.'
                : 'A stride needs a grade 3 vanguard and grade 3 worth of '
                      'cards in hand to discard.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          const Text(
            'A G unit comes back face up when its stride ends. Turn cards up '
            'and down here for the abilities that count them or pay with '
            'them.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          // Same shape as the other piles: the card, then what can be done
          // with it underneath, since two actions will not sit beside a name.
          for (final card in side.gZone)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                    opacity: side.isFaceUp(card) ? 1 : 0.4,
                    child: CardImage(url: card.imageUrl, width: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card.name,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Grade ${card.grade} · ${card.power} power · '
                          '${side.isFaceUp(card) ? 'face up' : 'face down'}',
                          style: TextStyle(
                            color: side.isFaceUp(card)
                                ? AppColors.warning
                                : AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        Wrap(
                          spacing: 4,
                          children: [
                            if (canStride)
                              TextButton(
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                  _showStrideCostSheet(
                                    context,
                                    game,
                                    side,
                                    card,
                                  );
                                },
                                child: const Text('Stride'),
                              ),
                            if (yours)
                              TextButton(
                                onPressed: () {
                                  game.flipG(
                                    side,
                                    card,
                                    faceUp: !side.isFaceUp(card),
                                  );
                                  Navigator.of(sheetContext).pop();
                                },
                                child: Text(
                                  side.isFaceUp(card)
                                      ? 'Turn face down'
                                      : 'Flip face up',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// Picks the cards discarded to pay for a stride.
void _showStrideCostSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
  GameCard strider,
) {
  final picks = <GameCard>{};

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (builderContext, setSheetState) {
        final total = picks.fold(0, (sum, card) => sum + card.grade);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  title: 'Pay for ${strider.name}',
                  caption:
                      'Discard cards worth grade 3 or more. '
                      'Picked: $total.',
                ),
                for (final card in side.hand)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: picks.contains(card),
                    onChanged: (checked) => setSheetState(() {
                      if (checked ?? false) {
                        picks.add(card);
                      } else {
                        picks.remove(card);
                      }
                    }),
                    title: Text(
                      card.name,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Grade ${card.grade}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: total < 3
                        ? null
                        : () {
                            game.stride(side, strider, picks.toList());
                            Navigator.of(sheetContext).pop();
                          },
                    child: Text(total < 3 ? 'Grade $total of 3' : 'Stride'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// One player's six circles, back row nearer the middle for the opponent so
/// the two boards face each other the way they would on a table.
class _Field extends StatelessWidget {
  const _Field({required this.game, required this.side, required this.isYours});

  final PlaytestController game;
  final PlaytestSide side;
  final bool isYours;

  @override
  Widget build(BuildContext context) {
    const front = [Circle.frontLeft, Circle.vanguard, Circle.frontRight];
    const back = [Circle.backLeft, Circle.backCenter, Circle.backRight];
    final rows = isYours ? [front, back] : [back, front];

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                for (final circle in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _CircleSlot(
                        // Named so a test can reach one circle in particular
                        // rather than counting its way across the board.
                        key: ValueKey('circle-${side.name}-${circle.name}'),
                        game: game,
                        side: side,
                        circle: circle,
                        isYours: isYours,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CircleSlot extends StatelessWidget {
  const _CircleSlot({
    super.key,
    required this.game,
    required this.side,
    required this.circle,
    required this.isYours,
  });

  final PlaytestController game;
  final PlaytestSide side;
  final Circle circle;
  final bool isYours;

  @override
  Widget build(BuildContext context) {
    final unit = side.field[circle];
    final held = game.holding;
    // Calling is offered in the battle phase as well as the main one: the
    // abilities that call out of a deck fire mid-battle, and a board that
    // only allowed it before the fight could not play them.
    // Whose board this is, and whether you are the one playing it. With both
    // hands yours that is both boards, one turn at a time.
    final mine = game.controls(side) && game.isTurnOf(side);
    final canPlace =
        mine &&
        held != null &&
        game.engine.canCall(side, held, circle) &&
        (game.state.phase == PlaytestPhase.main ||
            game.state.phase == PlaytestPhase.battle);

    // Highlight what this tap would do right now: a place, an attack, or a
    // target for the attack you are making.
    final isAttackTarget =
        !game.isTurnOf(side) &&
        game.state.phase == PlaytestPhase.battle &&
        game.selectedAttacker != null &&
        circle.isFrontRow &&
        unit != null &&
        unit.isActive;
    final isAttacker =
        mine &&
        game.state.phase == PlaytestPhase.battle &&
        game.engine.canAttack(side) &&
        unit != null &&
        unit.isActive &&
        !unit.rested &&
        circle.isFrontRow;

    final borderColour = canPlace || isAttackTarget
        ? AppColors.accent
        : (game.selectedAttacker == circle && game.isTurnOf(side)
              ? AppColors.warning
              : AppColors.border);

    return GestureDetector(
      onTap: () => _onTap(context, canPlace, isAttackTarget, isAttacker),
      onLongPress: unit == null
          ? null
          : () => _showUnitSheet(context, game, side, circle, unit),
      child: AspectRatio(
        aspectRatio: 1.05,
        child: Container(
          decoration: BoxDecoration(
            color: unit == null ? AppColors.surface : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColour,
              width: borderColour == AppColors.border ? 1 : 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: unit == null
              ? Center(
                  child: Text(
                    circle == Circle.vanguard ? 'VG' : '—',
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11,
                    ),
                  ),
                )
              : _UnitTile(unit: unit, circle: circle),
        ),
      ),
    );
  }

  void _onTap(
    BuildContext context,
    bool canPlace,
    bool isAttackTarget,
    bool isAttacker,
  ) {
    if (canPlace) {
      game.placeHeld(circle);
      return;
    }
    if (isAttackTarget) {
      game.attackWithSelected(circle);
      return;
    }
    if (isAttacker) {
      game.selectAttacker(circle);
      return;
    }
    final unit = side.field[circle];
    if (unit != null) _showUnitSheet(context, game, side, circle, unit);
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.unit, required this.circle});

  final FieldUnit unit;
  final Circle circle;

  @override
  Widget build(BuildContext context) {
    // A locked card is face down on the table, so it is face down here: the
    // art upside down and dimmed under a lock, with its power hidden, since
    // a locked card has none to give.
    if (unit.locked) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.25,
            child: RotatedBox(
              quarterTurns: 2,
              child: CardImage(url: unit.card.imageUrl, width: 140),
            ),
          ),
          Container(color: AppColors.surface.withValues(alpha: 0.6)),
          const Center(
            child: Icon(Icons.lock_outline, size: 20, color: AppColors.warning),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.7),
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: const Text(
                'LOCKED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: unit.rested ? 0.45 : 1,
          child: CardImage(url: unit.card.imageUrl, width: 140),
        ),
        if (unit.rested)
          const Center(
            child: Icon(Icons.rotate_right, size: 18, color: Colors.white70),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black.withValues(alpha: 0.7),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${unit.power}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: unit.powerBonus > 0
                        ? AppColors.success
                        : Colors.white,
                  ),
                ),
                // A hollowed unit is on loan: it fights this turn and is
                // retired at the end of it, which the board has to say.
                if (unit.hollowed)
                  const Text(
                    ' ☠',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                // A unit given [Boost] by an ability is a booster for the
                // turn, which is not something its grade would tell you.
                if (unit.grantedBoost)
                  const Text(
                    ' ⇧',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                // One critical is the default and not worth the space; a
                // unit carrying more, or reduced to none, is.
                if (unit.criticalBonus != 0)
                  Text(
                    ' ★${unit.critical}',
                    style: TextStyle(
                      fontSize: 10,
                      color: unit.criticalBonus > 0
                          ? AppColors.warning
                          : AppColors.textFaint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The strip between the two boards: the battle, laid out as its zones.
///
/// A guardian circle and a trigger zone are where a fight is actually read in
/// the real game -- what was thrown in front of the attack, and what came off
/// the top -- so they are shown as the cards they are rather than folded into
/// a shield total and a log line.
class _Middle extends StatelessWidget {
  const _Middle({required this.game});

  final PlaytestController game;

  @override
  Widget build(BuildContext context) {
    final attack = game.state.attack;
    final checks = game.triggerZone;

    if (attack == null && checks.isEmpty) {
      return Container(height: 1, color: AppColors.border);
    }

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (attack != null) ...[
            Text(
              '${attack.attacker.card.name} → ${attack.target.card.name}'
              '   ${attack.attackPower} vs ${attack.defence}'
              '${attack.perfectGuarded ? '  (perfect guard)' : ''}',
              style: TextStyle(
                color: attack.connects ? AppColors.danger : AppColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _GuardianZone(attack: attack),
          ],
          if (checks.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TriggerZone(game: game, checks: checks),
          ],
        ],
      ),
    );
  }
}

/// The guardian circle: what has been called in front of this attack.
class _GuardianZone extends StatelessWidget {
  const _GuardianZone({required this.attack});

  final PendingAttack attack;

  @override
  Widget build(BuildContext context) {
    return _ZoneStrip(
      label: 'Guardian',
      trailing: attack.perfectGuarded
          ? 'perfect guard'
          : attack.guardians.isEmpty
          ? null
          : '+${attack.shield} shield',
      empty: 'Nothing guarding',
      children: [
        for (final card in attack.guardians)
          _CheckTile(
            card: card,
            caption: card.isSentinel ? 'PG' : '${card.shield ~/ 1000}k',
            colour: card.isSentinel ? AppColors.success : AppColors.textMuted,
          ),
      ],
    );
  }
}

/// The trigger zone: every card this battle has turned face up, drive checks
/// and damage checks alike, in the order they were checked.
class _TriggerZone extends StatelessWidget {
  const _TriggerZone({required this.game, required this.checks});

  final PlaytestController game;
  final List<CheckedCard> checks;

  @override
  Widget build(BuildContext context) {
    return _ZoneStrip(
      label: 'Trigger',
      empty: 'Nothing checked',
      children: [
        for (final check in checks)
          _CheckTile(
            card: check.card,
            caption: check.card.trigger ?? check.kind.label.toLowerCase(),
            colour: check.card.trigger != null
                ? AppColors.warning
                : AppColors.textFaint,
            corner: check.kind == CheckKind.drive ? 'D' : '✚',
            cornerColour: check.kind == CheckKind.drive
                ? AppColors.accent
                : AppColors.danger,
            tooltip: check.isSplittable
                ? '${check.sideName} · ${check.kind.label} — '
                      'tap to choose who gets it'
                : '${check.sideName} · ${check.kind.label}',
            // A trigger's power and critical are the checking player's to
            // place, and they do not have to go to the same unit.
            onTap: !check.isSplittable
                ? null
                : () {
                    final side = _sideNamed(game, check.sideName);
                    if (side == null || !game.controls(side)) return;
                    _showTriggerSplitSheet(context, game, side, check);
                  },
          ),
      ],
    );
  }
}

PlaytestSide? _sideNamed(PlaytestController game, String name) {
  if (game.you.name == name) return game.you;
  if (game.cpu.name == name) return game.cpu;
  return null;
}

/// Who a checked trigger's power and critical go to.
///
/// The board hands them both to the unit that is fighting, because that is
/// right nearly every time. It is still a choice the game gives you, and the
/// split -- the critical on the vanguard, the power on a rear-guard about to
/// swing -- is the whole point of a good many attacks.
void _showTriggerSplitSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
  CheckedCard check,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scrollController) => ListenableBuilder(
          listenable: game,
          builder: (_, _) {
            Widget targets({required bool power}) {
              final held = power ? check.powerTo : check.criticalTo;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in side.field.entries)
                    if (entry.value.isActive)
                      ListTile(
                        key: ValueKey(
                          'trigger-${power ? 'power' : 'critical'}-'
                          '${entry.key.name}',
                        ),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          held == entry.key
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: held == entry.key
                              ? AppColors.accent
                              : AppColors.textFaint,
                        ),
                        title: Text(
                          entry.value.card.name,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${entry.key.label} · ${entry.value.power} power'
                          '${entry.value.critical == 1 ? '' : ' · ${entry.value.critical} critical'}',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => game.moveTriggerGift(
                          side,
                          check,
                          entry.key,
                          power: power,
                        ),
                      ),
                ],
              );
            }

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                SectionHeader(
                  title: check.card.name,
                  caption:
                      '${check.card.trigger} trigger — its power and its '
                      'critical can go to different units.',
                ),
                if (check.powerGiven > 0) ...[
                  Text(
                    'Power +${check.powerGiven}',
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  targets(power: true),
                ],
                if (check.criticalGiven > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Critical +${check.criticalGiven}',
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  targets(power: false),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// A labelled row of cards, scrolling sideways when there are many.
class _ZoneStrip extends StatelessWidget {
  const _ZoneStrip({
    required this.label,
    required this.children,
    required this.empty,
    this.trailing,
  });

  final String label;
  final List<Widget> children;
  final String empty;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              Text(
                trailing!,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        if (children.isEmpty)
          Text(
            empty,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
          )
        else
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final child in children)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: child,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One card in a zone strip, with a word underneath saying what it is doing.
class _CheckTile extends StatelessWidget {
  const _CheckTile({
    required this.card,
    required this.caption,
    required this.colour,
    this.corner,
    this.cornerColour,
    this.tooltip,
    this.onTap,
  });

  final GameCard card;
  final String caption;
  final Color colour;
  final String? corner;
  final Color? cornerColour;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            CardImage(url: card.imageUrl, width: 30),
            if (corner != null)
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.75),
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    corner!,
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: cornerColour ?? Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 8, color: colour),
        ),
      ],
    );
    final label = tooltip;
    final wrapped = onTap == null
        ? tile
        : GestureDetector(onTap: onTap, child: tile);
    return label == null ? wrapped : Tooltip(message: label, child: wrapped);
  }
}

/// Your hand, and what tapping a card does in the phase you are in.
class _Hand extends StatelessWidget {
  const _Hand({required this.game});

  final PlaytestController game;

  @override
  Widget build(BuildContext context) {
    final guarding = game.stage == PlaytestStage.guarding;
    final side = game.handSide;
    final hand = side.hand;

    return Container(
      height: game.bothSides ? 124 : 108,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // With both hands yours, which one this is matters more than
          // anything else on the strip.
          if (game.bothSides)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(
                guarding
                    ? '${side.name}\u2019s hand — guarding'
                    : '${side.name}\u2019s hand',
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 10,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(
            child: hand.isEmpty
                ? const Center(
                    child: Text(
                      'No cards in hand',
                      style: TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    children: [
                      for (final card in hand)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _HandSlot(
                            key: ValueKey('hand-${card.instanceId}'),
                            game: game,
                            card: card,
                            guarding: guarding,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _HandSlot extends StatelessWidget {
  const _HandSlot({
    super.key,
    required this.game,
    required this.card,
    required this.guarding,
  });

  final PlaytestController game;
  final GameCard card;
  final bool guarding;

  @override
  Widget build(BuildContext context) {
    final held = game.holding == card;
    final usable = guarding
        ? card.canGuard
        : (game.isTurnOf(game.handSide) && !game.state.isOver);

    return GestureDetector(
      onTap: () {
        if (guarding) {
          if (card.canGuard) game.guardWith(card);
          return;
        }
        _showHandSheet(context, game, card);
      },
      child: Opacity(
        opacity: usable ? 1 : 0.4,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: held ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              CardImage(url: card.imageUrl, width: 58),
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  child: Text(
                    guarding && card.canGuard
                        ? (card.isSentinel ? 'PG' : '${card.shield ~/ 1000}k')
                        : 'G${card.grade}',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The buttons that move the game on. What is here is always the thing the
/// rules are waiting for.
class _Controls extends StatelessWidget {
  const _Controls({required this.game});

  final PlaytestController game;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: _buttons(context)),
    );
  }

  List<Widget> _buttons(BuildContext context) {
    final state = game.state;

    if (state.isOver) {
      return [
        Expanded(
          child: Text(
            '${state.winner?.name ?? '—'} wins.',
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ];
    }

    switch (game.stage) {
      case PlaytestStage.guarding:
        final attack = state.attack!;
        // With both hands yours the defender is a player with a name, and
        // saying which one is the difference between a guard made on purpose
        // and one made with the wrong hand.
        final whose = game.bothSides ? '${state.inactive.name}: ' : '';
        return [
          Expanded(
            child: Text(
              attack.connects
                  ? '${whose}tap shields to guard — it hits for '
                        '${attack.attacker.critical} otherwise.'
                  : '${whose}the attack is held off.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          FilledButton(
            onPressed: game.confirmGuard,
            child: Text(game.bothSides ? 'Done guarding' : 'Take it'),
          ),
        ];

      // The CPU's main phase, a tap at a time: what it just did, and the
      // button that lets it do the next thing.
      case PlaytestStage.cpuTurn:
        return [
          Expanded(
            child: Text(
              game.lastCpuAction ?? 'The CPU takes its turn.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          FilledButton(onPressed: game.cpuStep, child: const Text('Continue')),
        ];

      case PlaytestStage.cpuAttack:
        // Its checks are flipped one at a time as well, so a twin drive is
        // two things to read rather than a pair that appears together.
        final owed = game.drivesLeft;
        return [
          Expanded(
            child: Text(
              owed > 0
                  ? 'The CPU has $owed drive '
                        '${owed == 1 ? 'check' : 'checks'} to make.'
                  : 'The CPU\'s attack resolves.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          if (owed > 0)
            FilledButton(
              onPressed: game.driveCheck,
              child: const Text('Drive check'),
            )
          else
            FilledButton(
              onPressed: game.resolveCpuAttack,
              child: const Text('Continue'),
            ),
        ];

      case PlaytestStage.yourAttack:
        final attack = state.attack!;
        final drove = attack.driveChecked || !attack.isVanguardAttack;
        // One check per tap. A twin drive is two moments at a table, and what
        // the first turns up is read before the second is flipped.
        final owed = game.drivesLeft;
        final taken = attack.drivesTaken;
        return [
          Expanded(
            child: Text(
              drove
                  ? '${attack.attackPower} against ${attack.defence}.'
                  : taken == 0
                  ? 'Drive check to see what you turn up.'
                  : '${attack.attackPower} against ${attack.defence} — '
                        '$owed to go.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          if (!drove)
            FilledButton(
              onPressed: game.driveCheck,
              child: Text(
                owed > 1 ? 'Drive check ($owed left)' : 'Drive check',
              ),
            )
          else
            FilledButton(
              onPressed: game.resolveYourAttack,
              child: const Text('Resolve'),
            ),
        ];

      default:
        return _yourTurnButtons(context);
    }
  }

  List<Widget> _yourTurnButtons(BuildContext context) {
    final state = game.state;
    // Against the CPU there is nothing to do on its turn. With both hands
    // yours there is no such turn: you play them both.
    if (!state.yourTurn && !game.bothSides) {
      return const [
        Expanded(
          child: Text(
            'The CPU is playing.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      ];
    }

    // Which player the bar is talking to, said out loud where it could be
    // either of them.
    final whose = game.bothSides ? '${game.me.name}: ' : '';

    return [
      Expanded(
        child: Text(
          whose +
              switch (state.phase) {
                PlaytestPhase.ride =>
                  state.ridden
                      ? 'Ridden. Move on to the main phase.'
                      : 'Ride phase — ride up a grade.',
                PlaytestPhase.main =>
                  game.holding == null
                      ? 'Main phase — tap a card in hand to call it, or a '
                            'rear-guard to move it up or back.'
                      : 'Tap a circle to call ${game.holding!.name}.',
                PlaytestPhase.battle =>
                  game.holding != null
                      ? 'Tap a circle to call ${game.holding!.name}.'
                      : !game.engine.canAttack(game.me)
                      // The turn one rule, said rather than left as a board that
                      // does not respond.
                      ? 'Turn one — whoever goes first does not attack.'
                      : game.selectedAttacker == null
                      ? 'Battle — tap a front row unit to attack with.'
                      : game.availableBooster == null
                      // Say why the boost is not on offer where a unit is standing
                      // behind and simply cannot give one.
                      ? game.boosterThatCannot == null
                            ? 'Tap the unit to attack.'
                            : '${game.boosterThatCannot!.card.name} cannot boost '
                                  '(grade ${game.boosterThatCannot!.card.grade}) — '
                                  'tap the unit to attack.'
                      : 'Boost is ${game.boostSelected ? 'on' : 'off'} — '
                            'tap the unit to attack.',
                _ => state.phase.label,
              },
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ),
      if (state.phase == PlaytestPhase.ride && !state.ridden)
        TextButton(
          onPressed: () => _showRideSheet(context, game),
          child: const Text('Ride'),
        ),
      // Boosting is a choice, not a default: a unit that restands wants its
      // booster kept back for the second swing.
      if (state.phase == PlaytestPhase.battle && game.availableBooster != null)
        TextButton.icon(
          onPressed: game.toggleBoost,
          icon: Icon(
            game.boostSelected
                ? Icons.check_box_outlined
                : Icons.check_box_outline_blank,
            size: 18,
          ),
          label: Text('+${game.availableBooster!.power}'),
          style: TextButton.styleFrom(
            foregroundColor: game.boostSelected
                ? AppColors.accent
                : AppColors.textMuted,
          ),
        ),
      if (state.phase == PlaytestPhase.battle && game.selectedAttacker != null)
        TextButton(
          onPressed: () => game.selectAttacker(null),
          child: const Text('Cancel'),
        ),
      FilledButton(
        onPressed: game.nextPhase,
        child: Text(state.phase == PlaytestPhase.battle ? 'End turn' : 'Next'),
      ),
    ];
  }
}

// ----------------------------------------------------------------- sheets

void _showRideSheet(BuildContext context, PlaytestController game) {
  final fromDeck = game.engine.rideDeckOption(game.me);
  final fromHand = game.engine.handRideOptions(game.me);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    // A hand can hold several units of a rideable grade, so the list has to be
    // free to scroll rather than run off the bottom of the sheet.
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              title: 'Ride',
              caption: 'The unit you ride over goes to the soul.',
            ),
            if (fromDeck == null && fromHand.isEmpty)
              const Text(
                'Nothing to ride: the ride deck has no next grade and your '
                'hand has nothing of the right grade.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            if (fromDeck != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CardImage(url: fromDeck.imageUrl, width: 36),
                title: Text(
                  fromDeck.name,
                  style: const TextStyle(color: AppColors.text),
                ),
                subtitle: Text(
                  'Ride deck · grade ${fromDeck.grade} · '
                  '${game.me.hand.isEmpty ? 'needs a card to discard' : 'discard a card to ride it'}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                // The discard is a choice, so it is asked for rather than
                // taken: which card leaves the hand decides the next turn.
                enabled: game.engine.canRideFromDeck(game.me),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showRideCostSheet(context, game, fromDeck);
                },
              ),
            for (final card in fromHand)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CardImage(url: card.imageUrl, width: 36),
                title: Text(
                  card.name,
                  style: const TextStyle(color: AppColors.text),
                ),
                subtitle: Text(
                  'From hand · grade ${card.grade}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                onTap: () {
                  game.ride(card, fromRideDeck: false);
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// What a card in hand can do, and what it says.
/// Paying for a ride out of the ride deck.
///
/// The cost is one card discarded from hand, and which one is a real decision
/// -- the shield you keep, the grade you keep for a stride -- so the hand is
/// laid out and the choice is yours.
void _showRideCostSheet(
  BuildContext context,
  PlaytestController game,
  GameCard riding,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            SectionHeader(
              title: 'Ride ${riding.name}',
              caption: 'Discard a card from hand to pay for it.',
            ),
            for (final card in game.me.hand)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CardImage(url: card.imageUrl, width: 32),
                title: Text(
                  card.name,
                  style: const TextStyle(color: AppColors.text, fontSize: 14),
                ),
                subtitle: Text(
                  'Grade ${card.grade}'
                  '${card.shield > 0 ? ' · ${card.shield} shield' : ''}'
                  '${card.isSentinel ? ' · perfect guard' : ''}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () {
                    game.ride(riding, fromRideDeck: true, discard: card);
                    Navigator.of(sheetContext).pop();
                  },
                  child: const Text('Discard'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

void _showHandSheet(
  BuildContext context,
  PlaytestController game,
  GameCard card,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        // Padded out from under the keyboard where anything brings one up.
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeading(card: card),
            const SizedBox(height: 12),
            if (game.isTurnOf(game.handSide) &&
                (game.state.phase == PlaytestPhase.main ||
                    game.state.phase == PlaytestPhase.battle) &&
                card.isUnit)
              _SheetAction(
                icon: Icons.add_circle_outline,
                label: 'Call to a circle',
                detail: 'Then tap the circle to put it on.',
                onTap: () {
                  game.hold(card);
                  Navigator.of(sheetContext).pop();
                },
              ),
            if (game.isTurnOf(game.handSide) && !card.isUnit)
              _SheetAction(
                icon: Icons.bolt_outlined,
                label: 'Play as an order',
                detail: 'It goes to the drop zone; apply its text yourself.',
                onTap: () {
                  game.playOrder(card);
                  Navigator.of(sheetContext).pop();
                },
              ),
            _SheetAction(
              icon: Icons.delete_outline,
              label: 'Discard',
              detail: 'For a cost the card text asks for.',
              onTap: () {
                game.discard(card);
                Navigator.of(sheetContext).pop();
              },
            ),
            _SheetAction(
              icon: Icons.auto_awesome_outlined,
              label: 'To the soul',
              detail:
                  'What a card asks for either way round: as its cost, '
                  'or as the thing it does.',
              onTap: () {
                game.handToSoul(card);
                Navigator.of(sheetContext).pop();
              },
            ),
            _SheetAction(
              icon: Icons.vertical_align_bottom,
              label: 'To the bottom of the deck',
              detail: 'The other cost cards ask for, kept out of the drop.',
              onTap: () {
                game.bottomDeck(game.handSide, card);
                Navigator.of(sheetContext).pop();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// A unit on the board: its text, and the hand-applied controls.
void _showUnitSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
  Circle circle,
  FieldUnit unit,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        // The power field brings up the keyboard, so the sheet is padded
        // out from under it rather than left half covered.
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeading(
              card: unit.card,
              unit: unit,
              circle: circle,
              drive: circle == Circle.vanguard
                  ? game.engine.driveCount(unit)
                  : null,
            ),
            // A locked card is face down and can do nothing: there is only
            // one thing to offer, which is turning it back over.
            if (unit.locked) ...[
              const SizedBox(height: 14),
              const Text(
                'Locked. It is face down, so it is not a unit: it cannot '
                'attack, boost, be attacked or be chosen, and nothing can be '
                'called over it. It unlocks on its own at the end of its '
                "owner's turn.",
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  game.toggleLock(side, circle);
                  Navigator.of(sheetContext).pop();
                },
                child: const Text('Unlock'),
              ),
            ] else ...[
              // Moving between the rows of a column is a rule the engine keeps,
              // not something applied by hand, so it sits above that line.
              if (game.controls(side) && game.engine.canMove(side, circle)) ...[
                const SizedBox(height: 14),
                _MoveAction(
                  game: game,
                  side: side,
                  circle: circle,
                  onDone: () => Navigator.of(sheetContext).pop(),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Applied by hand',
                style: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _PowerControl(game: game, side: side, circle: circle, unit: unit),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Critical is the other half of what an ability gives a unit:
                  // how many damage a hit on the vanguard is worth.
                  OutlinedButton(
                    onPressed: () => game.addCritical(side, circle, 1),
                    child: const Text('+1 critical'),
                  ),
                  OutlinedButton(
                    onPressed: unit.critical <= 0
                        ? null
                        : () => game.addCritical(side, circle, -1),
                    child: const Text('-1 critical'),
                  ),
                  // Only the vanguard drive checks, so the drive controls only
                  // appear where they would do something.
                  if (circle == Circle.vanguard) ...[
                    OutlinedButton(
                      onPressed: () => game.addDrive(side, circle, 1),
                      child: const Text('+1 drive'),
                    ),
                    OutlinedButton(
                      onPressed: game.engine.driveCount(unit) <= 0
                          ? null
                          : () => game.addDrive(side, circle, -1),
                      child: const Text('-1 drive'),
                    ),
                  ],
                  OutlinedButton(
                    onPressed: () => game.toggleRest(side, circle),
                    child: Text(unit.rested ? 'Stand' : 'Rest'),
                  ),
                  if (circle != Circle.vanguard) ...[
                    // [Boost] is printed on grades 0 and 1 only. Everything
                    // else that boosts does so because a card gave it the
                    // keyword, so that is offered here rather than assumed.
                    if (unit.card.grade >= 2)
                      OutlinedButton(
                        onPressed: () {
                          game.grantBoost(
                            side,
                            circle,
                            granted: !unit.grantedBoost,
                          );
                          Navigator.of(sheetContext).pop();
                        },
                        child: Text(
                          unit.grantedBoost
                              ? 'Take [Boost] back'
                              : 'Give [Boost]',
                        ),
                      ),
                    // Locking is done to a rear-guard, most often the
                    // opponent's, so it is offered on both sides of the board.
                    OutlinedButton(
                      onPressed: () {
                        game.toggleLock(side, circle);
                        Navigator.of(sheetContext).pop();
                      },
                      child: Text(unit.locked ? 'Unlock' : 'Lock'),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        game.retire(side, circle);
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Retire'),
                    ),
                    // A rear-guard paying its way into the soul, which is
                    // where a soul-blast will find it later. Not a retire:
                    // the drop and the soul are different places, and which
                    // one a card ends up in decides what can spend it.
                    OutlinedButton(
                      onPressed: () {
                        game.unitToSoul(side, circle);
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('To soul'),
                    ),
                    // A cost that puts a unit back in the deck rather than the
                    // drop zone, which is a different place for it to end up.
                    OutlinedButton(
                      onPressed: () {
                        game.bottomDeckUnit(side, circle);
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('To bottom of deck'),
                    ),
                  ],
                  OutlinedButton(
                    onPressed: () => game.drawCard(side),
                    child: const Text('Draw a card'),
                  ),
                  OutlinedButton(
                    onPressed: () => game.dealDamage(side),
                    child: const Text('Take damage'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// The power an ability gives a unit, typed in rather than picked off a
/// short list of buttons.
///
/// Cards give 2000, 3000 and 4000 as readily as the 5000 and 10000 the board
/// used to offer, and rounding to whatever happened to be on screen is not
/// playing the card. So the amount is a field -- it opens on 5000, the most
/// common one -- and the two buttons add or take away exactly what is in it.
class _PowerControl extends StatefulWidget {
  const _PowerControl({
    required this.game,
    required this.side,
    required this.circle,
    required this.unit,
  });

  final PlaytestController game;
  final PlaytestSide side;
  final Circle circle;
  final FieldUnit unit;

  @override
  State<_PowerControl> createState() => _PowerControlState();
}

class _PowerControlState extends State<_PowerControl> {
  final TextEditingController _amount = TextEditingController(text: '5000');

  @override
  void initState() {
    super.initState();
    // What is typed decides whether the buttons do anything, so the row
    // follows the field.
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The typed amount, or null where there is nothing usable in the field.
  int? get _typed {
    final value = int.tryParse(_amount.text.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  void _apply(int sign) {
    final amount = _typed;
    if (amount == null) return;
    setState(
      () => widget.game.addPower(widget.side, widget.circle, sign * amount),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typed = _typed;
    final bonus = widget.unit.powerBonus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 104,
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: AppColors.text, fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Power',
                  hintText: '5000',
                ),
              ),
            ),
            OutlinedButton(
              onPressed: typed == null ? null : () => _apply(1),
              child: const Text('Add power'),
            ),
            OutlinedButton(
              onPressed: typed == null ? null : () => _apply(-1),
              child: const Text('Remove power'),
            ),
          ],
        ),
        // What has been applied by hand so far, and a way back out of it.
        if (bonus != 0) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.unit.power} power '
                  '(${bonus > 0 ? '+' : ''}$bonus by hand)',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(
                  () =>
                      widget.game.addPower(widget.side, widget.circle, -bonus),
                ),
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Moving a rear-guard between the front and back of its own column.
///
/// A main phase action of the real game, and one the board had no way of
/// doing: a booster that wants to attack had to stay where it was called.
class _MoveAction extends StatelessWidget {
  const _MoveAction({
    required this.game,
    required this.side,
    required this.circle,
    required this.onDone,
  });

  final PlaytestController game;
  final PlaytestSide side;
  final Circle circle;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final target = game.engine.moveTargetOf(circle);
    if (target == null) return const SizedBox.shrink();
    final occupant = side.field[target];
    final forward = target.isFrontRow;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        forward ? Icons.arrow_upward : Icons.arrow_downward,
        color: AppColors.accent,
      ),
      title: Text(
        occupant == null
            ? 'Move to ${target.label.toLowerCase()}'
            : 'Swap with ${occupant.card.name}',
        style: const TextStyle(
          color: AppColors.text,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        forward
            ? 'Into the front row, where it can attack.'
            : 'Into the back row, where it can boost.',
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      onTap: () {
        game.moveUnit(side, circle);
        onDone();
      },
    );
  }
}

class _CardHeading extends StatelessWidget {
  const _CardHeading({required this.card, this.unit, this.circle, this.drive});

  final GameCard card;
  final FieldUnit? unit;
  final Circle? circle;

  /// How many drive checks this unit makes, for the vanguard alone.
  final int? drive;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CardImage(url: card.imageUrl, width: 78),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.name,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  'Grade ${card.grade}',
                  if (card.power > 0) '${unit?.power ?? card.power} power',
                  if (card.shield > 0) '${card.shield} shield',
                  if (card.trigger != null) '${card.trigger} trigger',
                  if (drive != null) '$drive drive',
                  if (circle != null) circle!.label,
                ].join(' · '),
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              if (card.effect.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  card.effect,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.textMuted),
      title: Text(label, style: const TextStyle(color: AppColors.text)),
      subtitle: Text(
        detail,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      onTap: onTap,
    );
  }
}
