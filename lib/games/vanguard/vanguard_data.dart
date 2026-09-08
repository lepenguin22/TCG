import 'package:flutter/material.dart';

import '../game_definition.dart';

const zoneRide = 'ride';
const zoneMain = 'main';
const zoneG = 'gzone';

const formatStandard = 'standard';
const formatVPremium = 'vpremium';
const formatPremium = 'premium';
const formatCasual = 'casual';

/// Which printing eras each format accepts, keyed by the `series` attribute
/// letters the catalog stamps on a card.
///
///   d  D-series and Divinez, the current Standard pool
///   v  V-series
///   g  G-series
///   o  the original series
///   p  a pre-D-series card of an era the data does not pin down
///
/// A card carries one letter per era it has been printed in, so a V-series
/// card later reprinted into the D-series counts as Standard legal. A format
/// missing from this map does not restrict the card pool at all.
const formatSeries = <String, Set<String>>{
  formatStandard: {'d'},
  formatVPremium: {'v'},
  formatPremium: {'v', 'g', 'o', 'p'},
};

/// The tokens a game hands a player, which are not cards in anybody's deck.
///
/// The card list does not carry them -- neither the official one nor the
/// community mirror has a single ticket in it -- because they are not deck
/// cards: an ability makes one out of nothing and puts it into your hand. So
/// they are described here, and the board hands them out.
///
/// Their shield is what matters at the table, since it is what a guard adds
/// up to, so it is shown wherever one is offered rather than buried.
const vanguardTokens = <Map<String, String>>[
  {
    'name': 'Persona Shield ticket',
    'grade': '0',
    'cardType': 'order-blitz',
    'power': '0',
    'shield': '15000',
    'effect':
        '[CONT](Hand):This card can be played from hand during your '
        'opponent\'s guard step, and goes to the drop zone after it '
        'guards.\n'
        '(A token: it is not in the deck, and an ability puts it into hand)',
  },
  {
    'name': 'Quick Shield ticket',
    'grade': '0',
    'cardType': 'order-blitz',
    'power': '0',
    'shield': '15000',
    'effect':
        '[CONT](Hand):This card can be played from hand during your '
        'opponent\'s guard step, and goes to the drop zone after it '
        'guards.\n'
        '(A token: it is not in the deck, and an ability puts it into hand)',
  },
];

const vanguardZones = <ZoneDefinition>[
  ZoneDefinition(
    id: zoneRide,
    name: 'Ride Deck',
    shortName: 'Ride',
    description:
        'One unit of each grade 0, 1, 2 and 3, and up to one ride deck crest. '
        'No trigger units.',
  ),
  ZoneDefinition(
    id: zoneMain,
    name: 'Main Deck',
    shortName: 'Main',
    description:
        'Exactly fifty cards, at most four copies of any one card name.',
  ),
  ZoneDefinition(
    id: zoneG,
    name: 'G Zone',
    shortName: 'G',
    description:
        'Up to sixteen G units, at most four copies of any one card name. '
        'Only a deck that strides needs one.',
  ),
];

const gradeOptions = <FieldOption>[
  FieldOption('0', 'Grade 0', color: Color(0xFF6EA8FE)),
  FieldOption('1', 'Grade 1', color: Color(0xFF5BD6A8)),
  FieldOption('2', 'Grade 2', color: Color(0xFFF5C453)),
  FieldOption('3', 'Grade 3', color: Color(0xFFF58B54)),
  FieldOption('4', 'Grade 4 (G unit)', color: Color(0xFFC08BF5)),
];

const cardTypeOptions = <FieldOption>[
  FieldOption('normal', 'Normal Unit'),
  FieldOption('trigger', 'Trigger Unit'),
  FieldOption('sentinel', 'Sentinel (Normal Unit)'),
  FieldOption('order', 'Order'),
  FieldOption('order-blitz', 'Blitz Order'),
  FieldOption('order-set', 'Set Order'),
  FieldOption('g-unit', 'G Unit'),
  FieldOption('ride-deck-crest', 'Ride Deck Crest'),
  // The crest a Stride Deckset brings. Not a deck card -- an ability puts it
  // into the crest zone -- but a card the app has to know, since a deck built
  // around it does nothing without it.
  FieldOption('crest', 'Crest'),
  FieldOption('token', 'Token'),
];

const triggerOptions = <FieldOption>[
  FieldOption('critical', 'Critical', color: Color(0xFFF26D6D)),
  FieldOption('draw', 'Draw', color: Color(0xFF6EA8FE)),
  FieldOption('front', 'Front', color: Color(0xFFF5A25B)),
  FieldOption('heal', 'Heal', color: Color(0xFF5BD6A8)),
  FieldOption('stand', 'Stand', color: Color(0xFFF5DC5B)),
  FieldOption('over', 'Over', color: Color(0xFFC08BF5)),
];

const nationOptions = <FieldOption>[
  FieldOption('dragon-empire', 'Dragon Empire', color: Color(0xFFE4573D)),
  FieldOption('dark-states', 'Dark States', color: Color(0xFF8C6BD1)),
  FieldOption('brandt-gate', 'Brandt Gate', color: Color(0xFF4FB3E8)),
  FieldOption('keter-sanctuary', 'Keter Sanctuary', color: Color(0xFFF0C24B)),
  FieldOption('stoicheia', 'Stoicheia', color: Color(0xFF4FC08D)),
  FieldOption(
    'lyrical-monasterio',
    'Lyrical Monasterio',
    color: Color(0xFFEE85B5),
  ),
  FieldOption(
    'united-sanctuary',
    'United Sanctuary (legacy)',
    color: Color(0xFFD8C48A),
  ),
  FieldOption('star-gate', 'Star Gate (legacy)', color: Color(0xFF7FA8D8)),
  FieldOption('magallanica', 'Magallanica (legacy)', color: Color(0xFF6BC7D1)),
  FieldOption('zoo', 'Zoo (legacy)', color: Color(0xFF9BC26B)),
  FieldOption('dark-zone', 'Dark Zone (legacy)', color: Color(0xFFA0729B)),
  FieldOption('cray-elemental', 'Cray Elemental', color: Color(0xFF9AA5B1)),
  FieldOption('none', 'No nation', color: Color(0xFF7A8794)),
];

const vanguardFields = <CardField>[
  CardField(
    key: 'grade',
    label: 'Grade',
    type: FieldType.select,
    options: gradeOptions,
    isRequired: true,
  ),
  CardField(
    key: 'cardType',
    label: 'Card type',
    type: FieldType.select,
    options: cardTypeOptions,
    isRequired: true,
  ),
  CardField(
    key: 'trigger',
    label: 'Trigger',
    type: FieldType.select,
    options: triggerOptions,
    visibleWhenKey: 'cardType',
    visibleWhenValues: ['trigger'],
    promptWhenMissing: true,
    helper: 'Heal is capped at four copies and Over at one per deck.',
  ),
  CardField(
    key: 'nation',
    label: 'Nation',
    type: FieldType.select,
    options: nationOptions,
  ),
  CardField(
    key: 'clan',
    label: 'Clan / sub-clan',
    type: FieldType.text,
    placeholder: 'Kagero, Royal Paladin, Nova Grappler…',
    helper: 'Optional. Handy for Premium decks built around a clan.',
  ),
  CardField(
    key: 'power',
    label: 'Power',
    type: FieldType.number,
    placeholder: '13000',
  ),
  CardField(
    key: 'shield',
    label: 'Shield',
    type: FieldType.number,
    placeholder: '10000',
  ),
  CardField(
    key: 'critical',
    label: 'Critical',
    type: FieldType.number,
    placeholder: '1',
  ),
  CardField(
    key: 'cardNo',
    label: 'Card number',
    type: FieldType.text,
    placeholder: 'D-BT01/001EN',
  ),
  CardField(
    key: 'effect',
    label: 'Card text',
    type: FieldType.multiline,
    placeholder: 'The card\'s abilities…',
    helper: 'Filled in from the card database.',
  ),
  CardField(
    key: 'imageUrl',
    label: 'Image URL',
    type: FieldType.text,
    placeholder: 'https://…',
    helper: 'Filled in from the card database. Needs internet the first time.',
  ),
  CardField(
    key: 'notes',
    label: 'Your notes',
    type: FieldType.multiline,
    placeholder: 'Combo notes, match-up reminders…',
  ),
];

const vanguardFormats = <FormatDefinition>[
  FormatDefinition(
    id: formatStandard,
    name: 'Standard',
    description:
        'D-series cards only. 50 card main deck, a ride deck of four units '
        'plus an optional crest, and a G zone if the deck strides.',
    zoneIds: [zoneRide, zoneMain, zoneG],
    targets: {
      // Four units, plus a ride deck crest when the deck runs one.
      zoneRide: ZoneTarget(max: 5),
      zoneMain: ZoneTarget(exact: 50),
      zoneG: ZoneTarget(max: 16),
    },
  ),
  FormatDefinition(
    id: formatVPremium,
    name: 'V Premium',
    description: 'V-series cards only. 50 card main deck, no ride deck.',
    zoneIds: [zoneMain],
    targets: {zoneMain: ZoneTarget(exact: 50)},
  ),
  FormatDefinition(
    id: formatPremium,
    name: 'Premium',
    description:
        'Everything from before the D-series. 50 card main deck plus a G zone '
        'of up to 16 G units.',
    zoneIds: [zoneMain, zoneG],
    targets: {zoneMain: ZoneTarget(exact: 50), zoneG: ZoneTarget(max: 16)},
  ),
  FormatDefinition(
    id: formatCasual,
    name: 'Casual / brew',
    description:
        'No size limits enforced. Use this while a list is still taking shape.',
    zoneIds: [zoneRide, zoneMain, zoneG],
  ),
];
