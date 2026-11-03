/// Ready-made decks the app ships with, added to My Decks in one tap.
///
/// Each is a list of card numbers, read through the same matching a Deck Log
/// import uses, so a deck here gets exactly the cards an imported one would.
library;

import '../../import/decklog.dart';

/// One card of a start deck: its number, how many, whether it sits in the
/// ride deck rather than the main deck, and -- for a trigger unit -- which
/// trigger, since the card database does not say for most of them.
class StartDeckCard {
  const StartDeckCard(
    this.number,
    this.quantity, {
    this.ride = false,
    this.trigger,
  });

  final String number;
  final int quantity;
  final bool ride;
  final String? trigger;
}

class StartDeck {
  const StartDeck({
    required this.id,
    required this.name,
    required this.description,
    required this.cards,
  });

  final String id;
  final String name;
  final String description;
  final List<StartDeckCard> cards;

  int count({required bool ride}) => cards
      .where((card) => card.ride == ride)
      .fold(0, (sum, card) => sum + card.quantity);

  /// The deck as a Deck Log deck, for the importer.
  DecklogDeck toDecklog() => DecklogDeck(
    code: id,
    gameTitleId: decklogVanguardTitleId,
    name: name,
    cards: [
      for (final card in cards)
        DecklogCard(
          name: card.number,
          cardNumber: card.number,
          quantity: card.quantity,
          isRideDeck: card.ride,
          trigger: card.trigger,
          section: card.ride ? 'ride' : 'main',
        ),
    ],
  );
}

/// The decks, newest first.
const startDecks = <StartDeck>[
  StartDeck(
    id: 'dz-ss19',
    name: 'Ghost Meets Gal! (DZ-SS19)',
    description:
        'Built from the DZ-SS19 start deck "Ghost Meets Gal!" alone. Ride '
        'Aiming to Be Idols! into Days of Lessons, Santi, then Road to the '
        'Live, Lubna, then Lubna, and D-Legion with Santi once their vanguard '
        'is grade 3. The new cards are unofficial translations of the Japanese '
        'set until the English one is out.',
    cards: [
      // Ride deck: one of each grade, and the Energy Generator crest.
      StartDeckCard('DZ-SS19/004', 1, ride: true),
      StartDeckCard('DZ-SS19/003', 1, ride: true),
      StartDeckCard('DZ-SS19/002', 1, ride: true),
      StartDeckCard('DZ-SS19/001', 1, ride: true),
      StartDeckCard('DZ-SS19/005', 1, ride: true),
      // Grade 3: Lubna, three more beside the ride deck's, and the Regalis
      // Piece.
      StartDeckCard('DZ-SS19/001', 3),
      StartDeckCard('DZ-SS19/018', 1),
      // Grade 2: four Santi for the D-Legion to find.
      StartDeckCard('DZ-SS19/002', 3),
      StartDeckCard('DZ-SS19/006', 4),
      StartDeckCard('DZ-SS19/007', 3),
      StartDeckCard('DZ-SS19/008', 4),
      StartDeckCard('DZ-SS19/017', 1),
      // Grade 1.
      StartDeckCard('DZ-SS19/003', 3),
      StartDeckCard('DZ-SS19/009', 4),
      StartDeckCard('DZ-SS19/010', 4),
      StartDeckCard('DZ-SS19/011', 4),
      // Sixteen triggers: one over, four critical, four draw, three front
      // and four heal.
      StartDeckCard('DZ-SS19/012', 1, trigger: 'over'),
      StartDeckCard('DZ-SS19/013', 4, trigger: 'critical'),
      StartDeckCard('DZ-SS19/014', 4, trigger: 'draw'),
      StartDeckCard('DZ-SS19/015', 3, trigger: 'front'),
      StartDeckCard('DZ-SS19/016', 4, trigger: 'heal'),
    ],
  ),
];
