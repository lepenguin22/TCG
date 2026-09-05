/// Reading a card's printing era out of its card number.
///
/// A card number carries the set it came from, and a set belongs to an era:
/// `D-BT02/001` is a D-series card, `V-BT01/001EN` a V-series one. That is the
/// only part of dating a card that needs nothing but the number, which makes it
/// usable in two places -- the catalogue generator, which has the whole source
/// record to work from, and the app, which sometimes has a card number and
/// nothing else, because an imported card was not in the database at all.
library;

/// The era a card number belongs to, or null when the number does not say.
///
/// Returns one of the app's era letters: `d`, `v`, `g`, `o` or `p`.
String? seriesFromCardNumber(String number) {
  final no = number.trim().toUpperCase();
  if (no.isEmpty) return null;

  if (RegExp(r'^DZ?-').hasMatch(no)) return 'd';
  if (no.startsWith('V-')) return 'v';
  if (no.startsWith('G-')) return 'g';
  if (RegExp(r'^(BT|EB|TD|FC|MT|SP)\d').hasMatch(no)) return 'o';

  // Event promos carry the format they were printed for in their number:
  // VGD is D-series, VGV is V Premium and VGP is Premium. VGS is "Standard",
  // which meant the V-series before the D-series took the name over -- so it
  // is deliberately not answered here, since the number alone cannot say.
  final promo = RegExp(r'^[A-Z]+\d{4}\D*/VG([SVPD])').firstMatch(no);
  switch (promo?.group(1)) {
    case 'D':
      return 'd';
    case 'V':
      return 'v';
    case 'P':
      return 'p';
  }

  return null;
}

/// A card number reduced to what the Japanese and English printings share.
///
/// The two releases of a set number their cards identically apart from the EN
/// the English ones carry: `D-BT02/001` and `D-BT02/001EN` are the same card.
/// Dropping that marker is therefore the whole trick behind importing a deck
/// from the Japanese site and showing it in English -- the number bridges the
/// languages, where the name cannot.
String decklogNumberKey(String raw) =>
    raw.trim().toLowerCase().replaceFirst(RegExp(r'en(?=$|[^a-z0-9])'), '');

/// The same, reduced further to the set and the printed number, with every
/// letter after the digits dropped.
///
/// This is what bridges a Japanese number to an English one. Where the English
/// printing carries EN, the Japanese one carries its rarity in the same place:
/// `DZ-SS14/001R` and `DZ-SS14/001EN` are the same card, and only stripping
/// both down to `dz-ss14/001` finds it. Variant markers go too -- the `-W` of
/// an alternate art, the ` SGR` of a rarity.
///
/// Two printings can share this key, so it is only ever used where it picks
/// out a single card.
String decklogLooseNumberKey(String raw) => raw
    .trim()
    .toLowerCase()
    .replaceFirst(RegExp(r'\s+\S+$'), '')
    .replaceFirst(RegExp(r'-[a-z]$'), '')
    .replaceFirstMapped(RegExp(r'^(.*\d)[a-z]+$'), (match) => match[1]!);
