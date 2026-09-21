import 'package:flutter/material.dart';

import '../playtest/net/playtest_intent.dart';
import '../playtest/net/playtest_wire.dart';
import '../playtest/net/remote_board.dart';
import '../playtest/playtest_state.dart';
import '../theme.dart';
import '../widgets/card_image.dart';
import 'playtest_screen.dart' show phaseColor;

/// The board of a game being played on another device.
///
/// Everything here is drawn from the last picture the host sent, and every
/// control asks the host for something rather than doing it. That is the
/// whole difference from the board you play alone: this one has no engine
/// behind it, so it can only show what it has been told and ask for what it
/// wants.
class RemoteBoardView extends StatefulWidget {
  const RemoteBoardView({
    super.key,
    required this.board,
    required this.onLeave,
    this.notice,
  });

  final RemoteBoard board;
  final VoidCallback onLeave;

  /// Something the game wants said across the top of the board: the other
  /// phone has dropped off, this one is dialling again. The board stays
  /// underneath it either way.
  final String? notice;

  @override
  State<RemoteBoardView> createState() => _RemoteBoardViewState();
}

class _RemoteBoardViewState extends State<RemoteBoardView> {
  /// The opening cards this player has picked out to put back. Kept here
  /// rather than read back off the board: they are a decision in progress,
  /// and nobody else needs to see them being made.
  final Set<int> _picks = {};

  /// The unit chosen to attack with, waiting on a target.
  Circle? _attacker;
  bool _boost = false;

  RemoteBoard get board => widget.board;

  PlaytestSnapshot get snapshot => board.snapshot!;

  void ask(PlaytestIntent intent) {
    board.ask(intent);
    setState(() {
      _attacker = null;
      _boost = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: board,
      builder: (context, _) {
        if (!board.connected) {
          return const Center(child: CircularProgressIndicator());
        }
        final refusal = board.refusal;
        final notice = widget.notice;
        return Column(
          children: [
            _PhaseBar(phase: snapshot.phase),
            if (notice != null)
              Container(
                width: double.infinity,
                color: AppColors.warning.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        notice,
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (refusal != null)
              Container(
                width: double.infinity,
                color: AppColors.danger.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Text(
                  refusal,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            Expanded(
              child: snapshot.phase == PlaytestPhase.mulligan
                  ? _mulligan()
                  : _board(),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------- the opening

  Widget _mulligan() {
    final hand = snapshot.me.handIds;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const Text(
          'Your opening hand',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap the cards to put back, then keep the hand. The other player '
          'is deciding theirs at the same time.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in hand)
              GestureDetector(
                key: ValueKey('mulligan-$id'),
                onTap: () {
                  setState(() {
                    _picks.contains(id) ? _picks.remove(id) : _picks.add(id);
                  });
                  board.ask(PlaytestIntent(IntentKind.togglePick, card: id));
                },
                child: _CardTile(
                  face: board.cardOf(id),
                  selected: _picks.contains(id),
                  width: 74,
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () =>
              board.ask(const PlaytestIntent(IntentKind.confirmMulligan)),
          child: Text(
            _picks.isEmpty
                ? 'Keep this hand'
                : 'Put ${_picks.length} back and draw',
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- the board

  Widget _board() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                _SideStrip(
                  side: snapshot.them,
                  board: board,
                  mine: false,
                  active: snapshot.activeName == snapshot.them.name,
                  phase: snapshot.phase,
                ),
                const SizedBox(height: 6),
                _Field(
                  side: snapshot.them,
                  board: board,
                  mine: false,
                  selected: null,
                  onTap: _tapTheirCircle,
                ),
                const SizedBox(height: 10),
                _Middle(snapshot: snapshot, board: board),
                const SizedBox(height: 10),
                _Field(
                  side: snapshot.me,
                  board: board,
                  mine: true,
                  selected: _attacker,
                  onTap: _tapMyCircle,
                ),
                const SizedBox(height: 6),
                _SideStrip(
                  side: snapshot.me,
                  board: board,
                  mine: true,
                  active: snapshot.myTurn,
                  phase: snapshot.phase,
                  onPlayFromDrop: _playFromDrop,
                ),
              ],
            ),
          ),
        ),
        _Hand(snapshot: snapshot, board: board, onTap: (id) => _handSheet(id)),
        _controls(),
      ],
    );
  }

  void _tapMyCircle(Circle circle) {
    final unit = snapshot.me.units[circle];
    if (unit == null) return;
    // In the battle phase a front row unit is picked up to attack with;
    // everywhere else, tapping a unit is asking what can be done to it.
    if (snapshot.phase == PlaytestPhase.battle &&
        snapshot.myTurn &&
        circle.isFrontRow &&
        !unit.rested &&
        snapshot.attack == null) {
      setState(() {
        _attacker = _attacker == circle ? null : circle;
        _boost = false;
      });
      return;
    }
    _unitSheet(circle, unit);
  }

  void _tapTheirCircle(Circle circle) {
    final from = _attacker;
    if (from == null || !circle.isFrontRow) return;
    if (snapshot.them.units[circle] == null) return;
    ask(
      PlaytestIntent(
        IntentKind.attack,
        circle: from,
        to: circle,
        amount: _boost ? 1 : 0,
      ),
    );
  }

  // ------------------------------------------------------------- the buttons

  Widget _controls() {
    final attack = snapshot.attack;
    final children = <Widget>[];
    String says;

    if (snapshot.winnerName != null) {
      says = '${snapshot.winnerName} wins.';
    } else if (attack != null) {
      final mine = snapshot.myTurn;
      says = mine
          ? '${attack.attackPower} against ${attack.defence}.'
          : 'They are attacking. Guard from your hand, or let it through.';
      if (mine && !attack.driveChecked) {
        children.add(
          FilledButton(
            onPressed: () => ask(const PlaytestIntent(IntentKind.driveCheck)),
            child: const Text('Drive check'),
          ),
        );
      } else if (mine) {
        children.add(
          FilledButton(
            onPressed: () =>
                ask(const PlaytestIntent(IntentKind.resolveAttack)),
            child: const Text('Resolve'),
          ),
        );
      }
    } else if (!snapshot.myTurn) {
      says = 'Waiting for ${snapshot.them.name}.';
    } else {
      says = switch (snapshot.phase) {
        PlaytestPhase.ride =>
          snapshot.ridden
              ? 'Ridden. On to the main phase.'
              : 'Ride phase — ride up a grade from your hand or ride deck.',
        PlaytestPhase.main =>
          'Main phase — tap a card in hand to call it, or a unit to move it.',
        PlaytestPhase.battle =>
          _attacker == null
              ? 'Battle — tap a front row unit to attack with.'
              : 'Tap the unit to attack.',
        _ => snapshot.phase.label,
      };
      if (snapshot.phase == PlaytestPhase.ride && !snapshot.ridden) {
        children.add(
          TextButton(onPressed: _rideSheet, child: const Text('Ride')),
        );
      }
      if (_attacker != null && _attacker!.boostedBy != null) {
        final booster = snapshot.me.units[_attacker!.boostedBy];
        if (booster != null && !booster.rested) {
          children.add(
            TextButton.icon(
              onPressed: () => setState(() => _boost = !_boost),
              icon: Icon(
                _boost
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank,
                size: 18,
              ),
              label: const Text('Boost'),
            ),
          );
        }
      }
      children.add(
        FilledButton(
          onPressed: () => ask(const PlaytestIntent(IntentKind.nextPhase)),
          child: Text(
            snapshot.phase == PlaytestPhase.battle ? 'End turn' : 'Next',
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              says,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ),
          for (final child in children) ...[const SizedBox(width: 8), child],
        ],
      ),
    );
  }

  // -------------------------------------------------------------- the sheets

  /// A card used out of your own drop zone, which leaves the game as it goes.
  ///
  /// The same moment as a blitz order when it happens in a battle, so it is
  /// asked the same question: what did it hand the unit being attacked.
  Future<void> _playFromDrop(int id) async {
    final face = board.cardOf(id);
    if (face == null) return;
    final inBattle = snapshot.attack != null;
    await _sheet([
      _CardHeading(face: face),
      if (!inBattle)
        _Action(
          icon: Icons.replay,
          label: face.isOrder ? 'Play it from the drop' : 'Use its ability',
          detail: 'It is removed from the game afterwards.',
          onTap: () =>
              ask(PlaytestIntent(IntentKind.activateFromDrop, card: id)),
        ),
      if (inBattle)
        for (final amount in [0, 5000, 10000, 15000, 20000])
          _Action(
            icon: Icons.replay,
            label: amount == 0
                ? 'Use it against this attack'
                : 'Use it, +$amount to the defence',
            detail: amount == 0
                ? 'It is removed from the game afterwards.'
                : 'Shield or power, it is the same off this attack.',
            onTap: () => ask(
              PlaytestIntent(
                IntentKind.activateFromDrop,
                card: id,
                amount: amount,
              ),
            ),
          ),
    ]);
  }

  Future<void> _handSheet(int id) async {
    final face = board.cardOf(id);
    if (face == null) return;
    final attack = snapshot.attack;
    final guarding = attack != null && !snapshot.myTurn;
    await _sheet([
      _CardHeading(face: face),
      if (guarding && face.canGuard)
        _Action(
          icon: Icons.shield_outlined,
          label: 'Guard with it',
          detail: '${face.shield} shield',
          onTap: () => ask(PlaytestIntent(IntentKind.guard, card: id)),
        ),
      // The one card either player may play in the middle of a battle, and
      // the answer for a defender with nothing to guard with.
      if (face.isBlitz && attack != null)
        for (final amount in [0, 5000, 10000, 15000, 20000])
          _Action(
            icon: Icons.flash_on_outlined,
            label: amount == 0
                ? 'Play as a blitz order'
                : 'Play as a blitz order, +$amount',
            detail: amount == 0
                ? 'It goes to the drop zone; apply its text yourself.'
                : 'Shield or power, it is the same off this attack.',
            onTap: () => ask(
              PlaytestIntent(IntentKind.playBlitz, card: id, amount: amount),
            ),
          ),
      if (snapshot.myTurn && !guarding) ...[
        if (face.isUnit && snapshot.phase == PlaytestPhase.ride)
          _Action(
            icon: Icons.upgrade,
            label: 'Ride it',
            onTap: () => ask(PlaytestIntent(IntentKind.ride, card: id)),
          ),
        if (face.isUnit)
          for (final circle in Circle.values)
            if (snapshot.me.units[circle] == null || circle != Circle.vanguard)
              _Action(
                icon: Icons.add_circle_outline,
                label: 'Call to ${circle.label.toLowerCase()}',
                onTap: () => ask(
                  PlaytestIntent(IntentKind.call, card: id, circle: circle),
                ),
              ),
        if (face.isOrder)
          _Action(
            icon: Icons.bolt_outlined,
            label: 'Play as an order',
            onTap: () => ask(PlaytestIntent(IntentKind.playOrder, card: id)),
          ),
      ],
      _Action(
        icon: Icons.delete_outline,
        label: 'Discard',
        onTap: () => ask(PlaytestIntent(IntentKind.discard, card: id)),
      ),
      _Action(
        icon: Icons.auto_awesome_outlined,
        label: 'To the soul',
        onTap: () => ask(PlaytestIntent(IntentKind.handToSoul, card: id)),
      ),
      _Action(
        icon: Icons.vertical_align_bottom,
        label: 'To the bottom of the deck',
        onTap: () => ask(PlaytestIntent(IntentKind.bottomDeck, card: id)),
      ),
    ]);
  }

  Future<void> _rideSheet() async {
    final options = [
      ...snapshot.me.rideDeckIds,
      ...snapshot.me.handIds,
    ].where((id) => board.cardOf(id)?.isUnit ?? false);
    await _sheet([
      const _SheetTitle('Ride'),
      for (final id in options)
        _Action(
          icon: Icons.upgrade,
          label: board.cardOf(id)!.name,
          detail: snapshot.me.rideDeckIds.contains(id)
              ? 'Grade ${board.cardOf(id)!.grade} · ride deck'
              : 'Grade ${board.cardOf(id)!.grade} · hand',
          onTap: () => ask(PlaytestIntent(IntentKind.ride, card: id)),
        ),
    ]);
  }

  Future<void> _unitSheet(Circle circle, UnitSnapshot unit) async {
    final face = board.cardOf(unit.cardId);
    await _sheet([
      if (face != null) _CardHeading(face: face),
      _Action(
        icon: unit.rested ? Icons.arrow_upward : Icons.arrow_downward,
        label: unit.rested ? 'Stand it' : 'Rest it',
        onTap: () => ask(PlaytestIntent(IntentKind.toggleRest, circle: circle)),
      ),
      _Action(
        icon: Icons.add,
        label: 'Give it 5000 power',
        onTap: () => ask(
          PlaytestIntent(IntentKind.addPower, circle: circle, amount: 5000),
        ),
      ),
      _Action(
        icon: Icons.priority_high,
        label: 'Give it a critical',
        onTap: () => ask(
          PlaytestIntent(IntentKind.addCritical, circle: circle, amount: 1),
        ),
      ),
      if (circle.isRearGuard) ...[
        _Action(
          icon: Icons.swap_vert,
          label: 'Move it up or back',
          onTap: () => ask(PlaytestIntent(IntentKind.moveUnit, circle: circle)),
        ),
        _Action(
          icon: Icons.auto_awesome_outlined,
          label: 'Into the soul',
          onTap: () =>
              ask(PlaytestIntent(IntentKind.unitToSoul, circle: circle)),
        ),
        _Action(
          icon: Icons.delete_outline,
          label: 'Retire it',
          onTap: () => ask(PlaytestIntent(IntentKind.retire, circle: circle)),
        ),
      ],
    ]);
  }

  Future<void> _sheet(List<Widget> children) => showModalBottomSheet<void>(
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
            for (final child in children)
              if (child is _Action)
                _Action(
                  icon: child.icon,
                  label: child.label,
                  detail: child.detail,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    child.onTap();
                  },
                )
              else
                child,
          ],
        ),
      ),
    ),
  );
}

/// The turn as six segments, the one being played lit, as on the board you
/// play alone.
class _PhaseBar extends StatelessWidget {
  const _PhaseBar({required this.phase});

  final PlaytestPhase phase;

  static const _turnPhases = [
    PlaytestPhase.stand,
    PlaytestPhase.draw,
    PlaytestPhase.ride,
    PlaytestPhase.main,
    PlaytestPhase.battle,
    PlaytestPhase.end,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          for (final each in _turnPhases)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: each == phase
                        ? phaseColor(each)
                        : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      each.label,
                      key: ValueKey('remote-phase-${each.name}'),
                      style: TextStyle(
                        color: each == phase
                            ? AppColors.bg
                            : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One player's counters and piles.
class _SideStrip extends StatelessWidget {
  const _SideStrip({
    required this.side,
    required this.board,
    required this.mine,
    required this.active,
    required this.phase,
    this.onPlayFromDrop,
  });

  final SideSnapshot side;
  final RemoteBoard board;
  final bool mine;
  final bool active;
  final PlaytestPhase phase;
  final void Function(int id)? onPlayFromDrop;

  @override
  Widget build(BuildContext context) {
    final colour = phaseColor(phase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? colour : AppColors.border,
          width: active ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 2,
            children: [
              Text(
                mine ? '${side.name} (you)' : side.name,
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              _Count(label: 'Dmg', value: '${side.damageIds.length}/6'),
              _Count(label: 'Hand', value: '${side.handCount}'),
              _Count(label: 'Deck', value: '${side.deckCount}'),
              _Count(label: 'Energy', value: '${side.energy}'),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final pile in [
                ('Drop', side.dropIds),
                ('Soul', side.soulIds),
                if (side.gZoneIds.isNotEmpty) ('G', side.gZoneIds),
                if (side.removedIds.isNotEmpty) ('Removed', side.removedIds),
                if (side.crestIds.isNotEmpty) ('Crest', side.crestIds),
              ])
                _PileChip(
                  label: pile.$1,
                  cards: pile.$2,
                  board: board,
                  owner: side.name,
                  // Cards work out of your own drop zone, and often in the
                  // middle of somebody else's attack.
                  onPlay: mine && pile.$1 == 'Drop' ? onPlayFromDrop : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$label ',
        style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
      ),
      Text(
        value,
        style: const TextStyle(
          color: AppColors.text,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

/// A public pile, which either player may look through.
class _PileChip extends StatelessWidget {
  const _PileChip({
    required this.label,
    required this.cards,
    required this.board,
    required this.owner,
    this.onPlay,
  });

  final String label;
  final List<int> cards;
  final RemoteBoard board;
  final String owner;

  /// What a card in this pile can be asked to do, where it can do anything.
  final void Function(int id)? onPlay;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: cards.isEmpty
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: AppColors.surface,
              showDragHandle: true,
              builder: (_) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    _SheetTitle('$owner’s $label (${cards.length})'),
                    for (final id in cards.reversed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CardImage(
                          url: board.cardOf(id)?.imageUrl,
                          width: 30,
                        ),
                        title: Text(
                          board.cardOf(id)?.name ?? 'A card',
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                          ),
                        ),
                        trailing: onPlay == null
                            ? null
                            : TextButton(
                                key: ValueKey('play-from-drop-$id'),
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  onPlay!(id);
                                },
                                child: const Text('Play'),
                              ),
                      ),
                  ],
                ),
              ),
            ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          '$label ${cards.length}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
      ),
    );
  }
}

/// Six circles, the front row nearest the middle of the table.
class _Field extends StatelessWidget {
  const _Field({
    required this.side,
    required this.board,
    required this.mine,
    required this.selected,
    required this.onTap,
  });

  final SideSnapshot side;
  final RemoteBoard board;
  final bool mine;
  final Circle? selected;
  final void Function(Circle circle) onTap;

  static const _front = [Circle.frontLeft, Circle.vanguard, Circle.frontRight];
  static const _back = [Circle.backLeft, Circle.backCenter, Circle.backRight];

  @override
  Widget build(BuildContext context) {
    // Your own front row sits nearest the middle, and so does theirs: the
    // two boards face each other the way they would on a table.
    final rows = mine ? [_front, _back] : [_back, _front];
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
                      child: _UnitCell(
                        key: ValueKey(
                          '${mine ? 'my' : 'their'}-${circle.name}',
                        ),
                        unit: side.units[circle],
                        face: side.units[circle] == null
                            ? null
                            : board.cardOf(side.units[circle]!.cardId),
                        selected: selected == circle,
                        onTap: () => onTap(circle),
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

class _UnitCell extends StatelessWidget {
  const _UnitCell({
    super.key,
    required this.unit,
    required this.face,
    required this.selected,
    required this.onTap,
  });

  final UnitSnapshot? unit;
  final GameCard? face;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final power = face == null
        ? null
        : face!.power + (unit?.powerBonus ?? 0) + (unit?.battleBonus ?? 0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 78,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: unit == null ? AppColors.bg : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : unit?.rested ?? false
                ? AppColors.textFaint
                : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: unit == null
            ? const SizedBox.shrink()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(child: CardImage(url: face?.imageUrl, width: 34)),
                  Text(
                    face?.name ?? 'A unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.text, fontSize: 10),
                  ),
                  Text(
                    '${power ?? ''}'
                    '${unit!.rested ? ' · rested' : ''}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// The attack on the table, and what the checks have turned up.
class _Middle extends StatelessWidget {
  const _Middle({required this.snapshot, required this.board});

  final PlaytestSnapshot snapshot;
  final RemoteBoard board;

  @override
  Widget build(BuildContext context) {
    final attack = snapshot.attack;
    return Column(
      children: [
        if (attack != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accent),
            ),
            child: Text(
              '${attack.attackPower} against ${attack.defence}'
              '${attack.perfectGuarded ? ' — guarded outright' : ''}',
              style: const TextStyle(color: AppColors.text, fontSize: 12),
            ),
          ),
        if (snapshot.triggerZone.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final check in snapshot.triggerZone)
                _CardTile(face: board.cardOf(check.cardId), width: 44),
            ],
          ),
        ],
        if (snapshot.log.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            snapshot.log.last,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

/// Your hand, along the bottom.
class _Hand extends StatelessWidget {
  const _Hand({
    required this.snapshot,
    required this.board,
    required this.onTap,
  });

  final PlaytestSnapshot snapshot;
  final RemoteBoard board;
  final void Function(int id) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        children: [
          for (final id in snapshot.me.handIds)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                key: ValueKey('hand-$id'),
                onTap: () => onTap(id),
                child: _CardTile(face: board.cardOf(id), width: 60),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.face,
    required this.width,
    this.selected = false,
  });

  final GameCard? face;
  final double width;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.border,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A card is taller than it is wide, so the picture is drawn
          // narrower than the tile to leave the name somewhere to go.
          CardImage(url: face?.imageUrl, width: width * 0.62),
          const SizedBox(height: 2),
          Text(
            face?.name ?? 'Face down',
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.text, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.text,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _CardHeading extends StatelessWidget {
  const _CardHeading({required this.face});

  final GameCard face;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CardImage(url: face.imageUrl, width: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                face.name,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Grade ${face.grade}'
                '${face.power > 0 ? ' · ${face.power} power' : ''}'
                '${face.shield > 0 ? ' · ${face.shield} shield' : ''}',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One thing a sheet offers to do.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: AppColors.textMuted),
    title: Text(
      label,
      style: const TextStyle(color: AppColors.text, fontSize: 14),
    ),
    subtitle: detail == null
        ? null
        : Text(
            detail!,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
          ),
    onTap: onTap,
  );
}
