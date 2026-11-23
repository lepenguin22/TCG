import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tcg_decks/games/card_catalog.dart';
import 'package:tcg_decks/games/vanguard/vanguard_data.dart';
import 'package:tcg_decks/games/vanguard/vanguard_game.dart';
import 'package:tcg_decks/import/decklog.dart';
import 'package:tcg_decks/store/deck_store.dart';
import 'package:tcg_decks/store/decklog_import.dart';

/// The Varga Dragres "Tensei" deck at decklog.bushiroad.com/view/1TRSFE, as
/// the Japanese Deck Log sends it: Japanese names, Japanese numbers.
const _deck = <(String, int, String, String)>[
  ('list', 3, 'DZ-BT17/001', '無双の羅刹竜 ヴァルガ・ドラグレス “天醒”'),
  ('list', 4, 'DZ-BT17/002', '燼華のドラグリッター シュウラ'),
  ('list', 2, 'DZ-BT17/049', 'ドラグリッター ナビーラ'),
  ('list', 4, 'DZ-BT12/003', '旋虐竜 ベリジェアクロ'),
  ('list', 4, 'DZ-BT01/002', 'ドラグリッター シュウラ'),
  ('list', 4, 'D-PR/1386', '祭砲竜 ディノフェスト'),
  ('list', 4, 'DZ-SS15/010', 'ドラゴンモンク ゴジョー'),
  ('list', 3, 'DZ-SS15/012', 'ワイバーンガード バリィ'),
  ('list', 4, 'DZ-BT02/003', '猛炎の武僧 ロクセイ'),
  ('list', 3, 'DZ-BT16/024', 'ドラグリッター ミスバーフ'),
  ('list', 3, 'DZ-SS01/Re06', '忍妖 アマヴィエラ'),
  ('list', 1, 'D-SS05/002', '水界の精霊王 イドスファロ'),
  ('list', 4, 'D-SS05/Re05', 'バーニングフレイル・ドラゴン'),
  ('list', 1, 'D-BT05/022', '忍妖 アマヴィエラ'),
  ('list', 4, 'D-BT01/H07', 'コンダクトスパーク・ドラゴン'),
  ('list', 1, 'DZ-BT06/020', '煌結晶'),
  ('list', 1, 'D-SS08/023', '四精織り成す清浄の盾'),
  ('p_list', 1, 'DZ-BT17/001', '無双の羅刹竜 ヴァルガ・ドラグレス “天醒”'),
  ('p_list', 1, 'DZ-BT17/074', 'ボルダーアクス・ドラゴン “斧巌”'),
  ('p_list', 1, 'DZ-BT17/079', 'ブレイズザンバー・ドラゴン “灯焔”'),
  ('p_list', 1, 'DZ-SS07/004', 'ヴァージルア'),
  ('p_list', 1, 'DZ-SS14/005R', 'エネルギージェネレーター'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a Japanese deck comes in whole, with the right reprints', () async {
    const game = VanguardGame();
    final path = game.catalogAsset!;
    final catalog = CardCatalog()
      ..seed(path, parseCatalog(File(path).readAsStringSync()));
    final store = DeckStore();
    await store.load();

    final result = await importDecklogDeck(
      store,
      catalog,
      DecklogDeck(
        code: '1TRSFE',
        gameTitleId: decklogVanguardTitleId,
        name: 'ドラグレス',
        cards: [
          for (final (section, quantity, number, name) in _deck)
            DecklogCard(
              name: name,
              quantity: quantity,
              cardNumber: number,
              section: section,
            ),
        ],
      ),
    );

    expect(result.unmatched, isEmpty);
    expect(result.zoneCounts[zoneMain], 50);
    expect(result.zoneCounts[zoneRide], 5);

    final view = store.viewOf(result.deck);
    String nameOf(String number) => view.items
        .firstWhere((item) => item.card.attributes['cardNo'] == number)
        .card
        .name;

    // Japanese numbers that name another card in English find the right one,
    // and are recorded under the English number.
    expect(nameOf('DZ-SS14/010EN'), 'Dragon Monk, Gojo');
    expect(nameOf('DZ-SS14/012EN'), 'Wyvern Guard, Barri');
    expect(nameOf('DZ-SS01/Re05EN'), 'Stealth Fiend, Amaviera');
    expect(nameOf('DZ-BT02/074EN'), 'Vyrgilla');
    expect(
      view.items.where((i) => i.card.name.contains('Magnides')),
      isEmpty,
      reason: 'English DZ-SS15/010 is not in this deck',
    );

    // And the new cards, translated.
    expect(
      nameOf('DZ-BT17/001'),
      'Unparalleled Drekasleif, Varga Dragres "Tensei"',
    );
    expect(nameOf('D-PR/1386JP'), 'Festival Cannon Dragon, Dinofest');
    expect(
      view.items.every((i) => !i.card.attributes.containsKey('jp')),
      isTrue,
    );

    final errors = [
      for (final issue in game.validate(view))
        if (issue.level.name == 'error') issue.message,
    ];
    expect(errors, isEmpty);
  });

  test('an English deck still reads its numbers as English', () async {
    const game = VanguardGame();
    final path = game.catalogAsset!;
    final catalog = CardCatalog()
      ..seed(path, parseCatalog(File(path).readAsStringSync()));
    final store = DeckStore();
    await store.load();
    final result = await importDecklogDeck(
      store,
      catalog,
      const DecklogDeck(
        code: 'EN',
        gameTitleId: decklogVanguardTitleId,
        cards: [
          DecklogCard(
            name: 'Magnetism Monster, Magnides',
            quantity: 1,
            cardNumber: 'DZ-SS15/010EN',
            section: 'list',
          ),
        ],
      ),
    );
    expect(
      store.viewOf(result.deck).items.single.card.name,
      'Magnetism Monster, Magnides',
    );
  });

  test(
    'a Japanese promo with no English printing comes in translated',
    () async {
      const game = VanguardGame();
      final path = game.catalogAsset!;
      final catalog = CardCatalog()
        ..seed(path, parseCatalog(File(path).readAsStringSync()));
      final store = DeckStore();
      await store.load();
      final result = await importDecklogDeck(
        store,
        catalog,
        DecklogDeck(
          code: 'JP',
          gameTitleId: decklogVanguardTitleId,
          cards: [
            for (final number in ['D-PR/1862', 'D-PR/1863'])
              DecklogCard(
                name: '星輝兵 バァドスパイラル・ドラゴン',
                quantity: 2,
                cardNumber: number,
                section: 'list',
              ),
          ],
        ),
      );
      expect(result.unmatched, isEmpty);
      final items = store.viewOf(result.deck).items;
      expect(items.map((i) => i.card.name).toSet(), {
        'Star-vader, Bad Spiral Dragon',
      });
      expect(items.first.card.attributes['effect'], contains('Unofficial'));
    },
  );
}
