import 'package:flutter/material.dart';

import '../playtest/playtest_state.dart';
import '../theme.dart';
import 'card_image.dart';

// The cards a board puts on the table beside its field: set orders, which
// stay out doing what they say, and crests. Shared by the board you play
// alone and the board of a game on two devices, so the two draw them alike.

/// The crests a board draws on the table beside the field: a stride deck's
/// crest, such as Nightrose, and anything else an ability put in the crest
/// zone.
///
/// Not the Energy Generator. Nearly every deck has one, all it does is
/// charge energy, and the energy is on the board already as a number; drawn
/// as a card it would take room in almost every game to say nothing new. It
/// is still in the crest zone, which the Crest pile opens.
List<GameCard> tableCrests(Iterable<GameCard> crestZone) => [
  for (final crest in crestZone)
    if (crest.cardType != 'ride-deck-crest') crest,
];

/// What heads a run of cards on the table: how many orders, since a deck
/// built on set orders counts them, or what it is when it is only a crest.
/// A crest carries its own badge, so a run with both still reads; naming
/// both up top did not fit the width of one small card.
String tableCaption(List<GameCard> crests, List<GameCard> orders) =>
    orders.isNotEmpty
    ? 'ORDERS ${orders.length}'
    : (crests.length == 1 ? 'CREST' : 'CRESTS');

/// The colour a crest is framed in on the table: the one the deck builder
/// badges a crest with.
const tableCrestColour = Color(0xFF4FC08D);

/// One card on the table beside a field, a set order or a crest: its art, with its name along the
/// bottom the way a unit has its power, since the art alone is a small thing
/// to read a name off and an offline game may have no art at all.
class TableCard extends StatelessWidget {
  const TableCard({
    super.key,
    required this.card,
    required this.width,
    required this.onTap,
    this.accent,
    this.badge,
    this.rested = false,
  });

  final GameCard card;
  final double width;
  final VoidCallback onTap;

  /// A frame round the card, for a kind of card that wants telling apart
  /// from the orders beside it.
  final Color? accent;

  /// A short label in the corner, in the [accent] colour: "CR" for a crest,
  /// as the deck builder badges one.
  final String? badge;

  /// A rested set order, turned on its side as a rested unit is. It keeps
  /// the place an upright card would take, so resting one never moves the
  /// cards beside it.
  final bool rested;

  @override
  Widget build(BuildContext context) {
    final height = width / cardAspectRatio;
    final face = SizedBox(width: width, height: height, child: _face());
    return Tooltip(
      message: rested ? '${card.name} (rested)' : card.name,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: rested
              ? Center(
                  child: FittedBox(
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: Opacity(opacity: 0.75, child: face),
                    ),
                  ),
                )
              : face,
        ),
      ),
    );
  }

  Widget _face() => Stack(
    fit: StackFit.expand,
    children: [
      CardImage(url: card.imageUrl, width: width),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(4),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text(
            card.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 8, color: Colors.white),
          ),
        ),
      ),
      if (badge != null)
        Positioned(
          left: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: accent ?? Colors.black,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Text(
              badge!,
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
        ),
      if (accent != null)
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: accent!, width: 2),
            ),
          ),
        ),
    ],
  );
}

/// A run of table cards in a strip against the field, with what they are
/// read sideways down its edge, so it costs a few pixels of width rather
/// than a line of height. More cards than fit across scroll sideways.
///
/// A phone's board and the board of a game on two devices both draw their
/// table this way: each is a column that scrolls, with no room beside the
/// field, so the room is found above or below it instead.
class TableStrip extends StatelessWidget {
  const TableStrip({
    super.key,
    required this.caption,
    required this.tiles,
    required this.listKey,
    this.below = false,
  });

  /// What heads the strip, from [tableCaption].
  final String caption;

  /// The cards, [width] wide.
  final List<Widget> tiles;

  /// What a test finds the scrolling row by.
  final Key listKey;

  /// Whether the strip is under the field rather than over it, which only
  /// decides which side of it the gap goes.
  final bool below;

  /// About two thirds of the width of a card in hand: big enough to tell
  /// two cards apart by their art, and small enough that four fit across
  /// the narrowest phone.
  static const width = 46.0;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    const height = width / cardAspectRatio;
    return Padding(
      padding: EdgeInsets.only(top: below ? 8 : 0, bottom: below ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: height,
            child: RotatedBox(
              quarterTurns: 3,
              child: Center(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: _gap),
          Expanded(
            child: SizedBox(
              height: height,
              child: ListView.separated(
                key: listKey,
                scrollDirection: Axis.horizontal,
                itemCount: tiles.length,
                separatorBuilder: (_, _) => const SizedBox(width: _gap),
                itemBuilder: (context, i) => tiles[i],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
