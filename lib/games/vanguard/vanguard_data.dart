import 'package:flutter/material.dart';

import '../game_definition.dart';

const zoneRide = 'ride';
const zoneMain = 'main';
const zoneG = 'gzone';

const formatStandard = 'standard';
const formatPremium = 'premium';
const formatCasual = 'casual';

const vanguardZones = <ZoneDefinition>[
  ZoneDefinition(
    id: zoneRide,
    name: 'Ride Deck',
    shortName: 'Ride',
    description: 'Exactly four cards: one each of grade 0, 1, 2 and 3. No trigger units.',
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
    description: 'Up to sixteen G units, at most four copies of any one card name. Premium only.',
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
    key: 'notes',
    label: 'Notes',
    type: FieldType.multiline,
    placeholder: 'Skill reminder, combo notes…',
  ),
];

const vanguardFormats = <FormatDefinition>[
  FormatDefinition(
    id: formatStandard,
    name: 'Standard',
    description: '50 card main deck plus a 4 card ride deck. D-series and V-series cards.',
    zoneIds: [zoneRide, zoneMain],
    targets: {zoneRide: ZoneTarget(exact: 4), zoneMain: ZoneTarget(exact: 50)},
  ),
  FormatDefinition(
    id: formatPremium,
    name: 'Premium',
    description: '50 card main deck plus a G zone of up to 16 G units. Every era is legal.',
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
