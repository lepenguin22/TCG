import '../games/card_catalog.dart';
import '../games/games.dart';
import 'deck_store.dart';

/// Fills the card database's details into library cards saved before it
/// existed, or before it carried something a card is missing.
///
/// Cards added by hand, or added from an older build of the app, have no
/// series, card text or image. Without a series the rules engine cannot tell
/// which format they belong to, so a deck full of them reports "could not be
/// checked" rather than a verdict. This repairs that in place.
///
/// It runs at most once per [cardBackfillVersion], after the first frame, and
/// does not touch the catalog at all when there is nothing to repair -- an
/// empty library costs nothing. Returns how many cards were filled in.
Future<int> backfillLibraryFromCatalog(
  DeckStore store,
  CardCatalog catalog,
) async {
  if (!store.needsCardBackfill) return 0;

  // An empty library still marks the job done, so the catalog is never read
  // just to discover there was nothing to do.
  if (store.cards.isEmpty) {
    store.markCardBackfillDone();
    return 0;
  }

  var filled = 0;
  for (final game in games) {
    final asset = game.catalogAsset;
    if (asset == null) continue;
    if (store.cardsForGame(game.id).isEmpty) continue;

    final cards = await catalog.load(asset);
    if (cards.isEmpty) {
      // The catalog could not be read. Leave the marker alone so the repair is
      // tried again next launch rather than being silently skipped forever.
      return filled;
    }
    filled += store.backfillFromCatalog(gameId: game.id, catalog: cards);
  }

  store.markCardBackfillDone();
  return filled;
}
