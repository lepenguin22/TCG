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
