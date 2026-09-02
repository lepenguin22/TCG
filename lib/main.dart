import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'games/card_catalog.dart';
import 'screens/deck_list_screen.dart';
import 'store/catalog_backfill.dart';
import 'store/deck_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DeckStore();
  await store.load();
  final catalog = CardCatalog();

  runApp(TcgDecksApp(store: store, catalog: catalog));

  // Cards saved before the card database existed are missing the details it
  // now supplies. Repair them once, after the first frame, so startup is not
  // waiting on a multi-megabyte asset.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    backfillLibraryFromCatalog(store, catalog).ignore();
  });
}

class TcgDecksApp extends StatelessWidget {
  TcgDecksApp({super.key, required this.store, CardCatalog? catalog})
    : catalog = catalog ?? CardCatalog();

  final DeckStore store;

  /// The bundled card database. Loaded lazily, the first time a deck's
  /// "add cards" screen opens.
  final CardCatalog catalog;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DeckStore>.value(value: store),
        Provider<CardCatalog>.value(value: catalog),
      ],
      child: MaterialApp(
        title: 'TCG Decks',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const DeckListScreen(),
      ),
    );
  }
}
