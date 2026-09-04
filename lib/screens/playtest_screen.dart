import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/deck.dart';
import '../playtest/playtest_controller.dart';
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
  });

  final Deck yourDeck;
  final Deck opponentDeck;

  /// Who takes turn one. Kept as the choice rather than the outcome, so a
  /// random order is rolled again on every restart.
  final TurnOrder turnOrder;

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
          return Scaffold(
            appBar: AppBar(
              title: Text(
                game.stage == PlaytestStage.mulligan
                    ? 'Opening hand'
                    : 'Turn ${game.state.turn} · '
                          '${game.state.yourTurn ? 'You' : 'CPU'}',
              ),
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
          );
        },
      ),
    );
  }

  void _restart(BuildContext context) {
    setState(() {
      _controller?.dispose();
      _controller = PlaytestController(
        store: context.read<DeckStore>(),
        yourDeck: widget.yourDeck,
        opponentDeck: widget.opponentDeck,
        turnOrder: widget.turnOrder,
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

// --------------------------------------------------------------------- mulligan

class _Mulligan extends StatelessWidget {
  const _Mulligan({required this.game});

  final PlaytestController game;

  @override
  Widget build(BuildContext context) {
    final hand = game.you.hand;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                game.you.goesFirst
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
                _SideSummary(side: game.cpu, game: game),
                const SizedBox(height: 6),
                _ZoneRail(game: game, side: game.cpu),
                const SizedBox(height: 8),
                _Field(game: game, side: game.cpu, isYours: false),
                const SizedBox(height: 10),
                _Middle(game: game),
                const SizedBox(height: 10),
                _Field(game: game, side: game.you, isYours: true),
                const SizedBox(height: 8),
                _ZoneRail(game: game, side: game.you),
                const SizedBox(height: 6),
                _SideSummary(side: game.you, game: game),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _showDamageSheet(context, game, side),
            child: _DamageRow(side: side),
          ),
        ),
        const SizedBox(width: 8),
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
            actionLabel: 'Return to hand',
            onAction: (card) => game.returnFromDrop(side, card),
          ),
        ),
        _Pile(
          label: 'Soul',
          count: side.soul.length,
          onTap: () => _showSoulSheet(context, game, side),
        ),
        // The crest, once a deck brings one. It charges the energy on its
        // own, so it is worth being able to see and read.
        if (side.crest != null)
          _Pile(
            label: 'Crest',
            count: side.crestInPlay ? side.energy : 0,
            highlight: side.crestInPlay,
            onTap: () => _showCrestSheet(context, game, side),
          ),
        // Only a deck that strides has a G zone, so it only appears for one.
        if (side.gZone.isNotEmpty)
          _Pile(
            label: 'G',
            count: side.gZone.length,
            highlight: game.engine.canStride(side),
            onTap: () => _showGZoneSheet(context, game, side),
          ),
      ],
    );
  }
}

/// The damage zone, laid out as the cards it is rather than a number. A card
/// turned face down has been spent on a counter-blast.
class _DamageRow extends StatelessWidget {
  const _DamageRow({required this.side});

  final PlaytestSide side;

  @override
  Widget build(BuildContext context) {
    if (side.damage.isEmpty) {
      return const SizedBox(
        height: 30,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'No damage',
            style: TextStyle(color: AppColors.textFaint, fontSize: 11),
          ),
        ),
      );
    }
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          for (final card in side.damage)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                width: 20,
                height: 28,
                decoration: BoxDecoration(
                  color: side.isSpent(card)
                      ? AppColors.surface
                      : AppColors.danger.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: side.isSpent(card)
                        ? AppColors.border
                        : AppColors.danger,
                  ),
                ),
              ),
            ),
        ],
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
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: GestureDetector(
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
          for (final card in cards.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CardImage(url: card.imageUrl, width: 32),
              title: Text(
                card.name,
                style: const TextStyle(color: AppColors.text, fontSize: 14),
              ),
              subtitle: Text(
                'Grade ${card.grade}'
                '${card.trigger == null ? '' : ' · ${card.trigger} trigger'}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              trailing: onAction == null
                  ? null
                  : TextButton(
                      onPressed: () {
                        onAction(card);
                        Navigator.of(sheetContext).pop();
                      },
                      child: Text(actionLabel ?? 'Move'),
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

/// The deck: a count, a shuffle, and a search for the abilities that need one.
void _showDeckSheet(
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
    header: (sheetContext) => [
      const Text(
        'The whole deck is listed here so an ability that searches can be '
        'played. It shuffles itself after a search. Only look when a card '
        'tells you to.',
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: () {
          game.shuffleDeck(side);
          Navigator.of(sheetContext).pop();
        },
        child: const Text('Shuffle'),
      ),
      const SizedBox(height: 12),
    ],
  );
}

/// The ride deck crest: what it says, and the energy it has charged.
void _showCrestSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  final crest = side.crest;
  if (crest == null) return;
  final charge = game.engine.crestCharge(side);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeading(card: crest),
            const SizedBox(height: 14),
            Text(
              side.crestInPlay
                  ? '${side.energy} energy, of a maximum of '
                        '${PlaytestSide.energyCap}. It charges $charge at the '
                        'beginning of every one of ${side.name == 'You' ? 'your' : 'its'} '
                        'ride phases, on its own.'
                  : 'Still in the ride deck. It reaches the crest zone on the '
                        'first ride — which is why whoever goes first charges '
                        'nothing on turn one.',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
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
          ],
        ),
      ),
    ),
  );
}

/// The G zone, and the stride it exists for.
void _showGZoneSheet(
  BuildContext context,
  PlaytestController game,
  PlaytestSide side,
) {
  final yours = side == game.you;
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
          SectionHeader(title: 'G zone (${side.gZone.length})'),
          Text(
            side.isStriding
                ? 'Striding already. The G unit goes back at end of turn.'
                : canStride
                ? 'Pick a G unit to stride, then discard cards worth grade 3 '
                      'or more between them to pay for it.'
                : 'A stride needs a grade 3 vanguard and grade 3 worth of '
                      'cards in hand to discard.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          for (final card in side.gZone)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CardImage(url: card.imageUrl, width: 32),
              title: Text(
                card.name,
                style: const TextStyle(color: AppColors.text, fontSize: 14),
              ),
              subtitle: Text(
                'Grade ${card.grade} · ${card.power} power',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
              trailing: !canStride
                  ? null
                  : TextButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        _showStrideCostSheet(context, game, card);
                      },
                      child: const Text('Stride'),
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
                for (final card in game.you.hand)
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
                            game.stride(strider, picks.toList());
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
    final canPlace =
        isYours &&
        held != null &&
        game.engine.canCall(game.you, held, circle) &&
        game.state.phase == PlaytestPhase.main &&
        game.state.yourTurn;

    // Highlight what this tap would do right now: a place, an attack, or a
    // target for the attack you are making.
    final isAttackTarget =
        !isYours &&
        game.state.yourTurn &&
        game.state.phase == PlaytestPhase.battle &&
        game.selectedAttacker != null &&
        circle.isFrontRow &&
        unit != null;
    final isAttacker =
        isYours &&
        game.state.yourTurn &&
        game.state.phase == PlaytestPhase.battle &&
        unit != null &&
        !unit.rested &&
        circle.isFrontRow;

    final borderColour = canPlace || isAttackTarget
        ? AppColors.accent
        : (game.selectedAttacker == circle && isYours
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

/// The strip between the two boards: whatever the game is waiting on.
class _Middle extends StatelessWidget {
  const _Middle({required this.game});

  final PlaytestController game;

  @override
  Widget build(BuildContext context) {
    final attack = game.state.attack;
    final checks = game.lastChecks;

    if (attack == null && checks.isEmpty) {
      return Container(height: 1, color: AppColors.border);
    }

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (attack != null)
            Text(
              '${attack.attacker.card.name} → '
              '${attack.target.card.name}   '
              '${attack.attackPower} vs ${attack.defence}'
              '${attack.perfectGuarded ? '  (perfect guard)' : ''}',
              style: TextStyle(
                color: attack.connects ? AppColors.danger : AppColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (checks.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final card in checks)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Column(
                        children: [
                          CardImage(url: card.imageUrl, width: 34),
                          if (card.trigger != null)
                            Text(
                              card.trigger!,
                              style: const TextStyle(
                                fontSize: 8,
                                color: AppColors.warning,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Your hand, and what tapping a card does in the phase you are in.
class _Hand extends StatelessWidget {
  const _Hand({required this.game});

  final PlaytestController game;

  @override
  Widget build(BuildContext context) {
    final guarding = game.stage == PlaytestStage.guarding;
    final hand = game.you.hand;

    return Container(
      height: 108,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: hand.isEmpty
          ? const Center(
              child: Text(
                'No cards in hand',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12),
              ),
            )
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        : (game.state.yourTurn && !game.state.isOver);

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
        return [
          Expanded(
            child: Text(
              attack.connects
                  ? 'Tap shields to guard — it hits for '
                        '${attack.attacker.critical} otherwise.'
                  : 'The attack is held off.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          FilledButton(
            onPressed: game.confirmGuard,
            child: const Text('Take it'),
          ),
        ];

      case PlaytestStage.cpuAttack:
        return [
          const Expanded(
            child: Text(
              'The CPU\'s attack resolves.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          FilledButton(
            onPressed: game.resolveCpuAttack,
            child: const Text('Continue'),
          ),
        ];

      case PlaytestStage.yourAttack:
        final attack = state.attack!;
        final drove = game.lastChecks.isNotEmpty || !attack.isVanguardAttack;
        return [
          Expanded(
            child: Text(
              drove
                  ? '${attack.attackPower} against ${attack.defence}.'
                  : 'Drive check to see what you turn up.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          if (!drove)
            FilledButton(
              onPressed: game.driveCheck,
              child: Text(
                'Drive check ×${game.engine.driveCount(attack.attacker)}',
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
    if (!state.yourTurn) {
      return const [
        Expanded(
          child: Text(
            'The CPU is playing.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      ];
    }

    return [
      Expanded(
        child: Text(switch (state.phase) {
          PlaytestPhase.ride =>
            state.ridden
                ? 'Ridden. Move on to your main phase.'
                : 'Ride phase — ride up a grade.',
          PlaytestPhase.main =>
            game.holding == null
                ? 'Main phase — tap a card in hand to call it, or a '
                      'rear-guard to move it up or back.'
                : 'Tap a circle to call ${game.holding!.name}.',
          PlaytestPhase.battle =>
            game.selectedAttacker == null
                ? 'Battle — tap one of your front row units to attack with.'
                : game.availableBooster == null
                ? 'Tap the unit to attack.'
                : 'Boost is ${game.boostSelected ? 'on' : 'off'} — '
                      'tap the unit to attack.',
          _ => state.phase.label,
        }, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
          label: Text('+${game.availableBooster!.card.power}'),
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
  final fromDeck = game.engine.rideDeckOption(game.you);
  final fromHand = game.engine.handRideOptions(game.you);

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
                  'Ride deck · grade ${fromDeck.grade}',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                onTap: () {
                  game.ride(fromDeck, fromRideDeck: true);
                  Navigator.of(sheetContext).pop();
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeading(card: card),
            const SizedBox(height: 12),
            if (game.state.yourTurn &&
                game.state.phase == PlaytestPhase.main &&
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
            if (game.state.yourTurn && !card.isUnit)
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
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
            // Moving between the rows of a column is a rule the engine keeps,
            // not something applied by hand, so it sits above that line.
            if (side == game.you && game.engine.canMove(side, circle)) ...[
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final amount in [5000, 10000, -5000])
                  OutlinedButton(
                    onPressed: () => game.addPower(side, circle, amount),
                    child: Text(
                      '${amount > 0 ? '+' : ''}${amount ~/ 1000}k power',
                    ),
                  ),
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
                if (circle != Circle.vanguard)
                  OutlinedButton(
                    onPressed: () {
                      game.retire(side, circle);
                      Navigator.of(sheetContext).pop();
                    },
                    child: const Text('Retire'),
                  ),
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
        ),
      ),
    ),
  );
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
