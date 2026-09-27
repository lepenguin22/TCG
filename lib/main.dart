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

/// Holds the app to a column no wider than a page of text.
///
/// The board is laid out for a phone held upright, and a desktop window is
/// several phones wide: left to fill it, six circles and a hand of cards
/// stretch into something nobody would deal out on a table. Below the width
/// this caps at, which is every phone and most tablets, it does nothing at
/// all.
class _Readable extends StatelessWidget {
  const _Readable({required this.child});

  static const maxWidth = 1100.0;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (child == null || width <= maxWidth) return child ?? const SizedBox();
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: SizedBox(
          width: maxWidth,
          // The app is told it has the narrower window, so anything that asks
          // how wide the screen is gets the answer it is being drawn into.
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(size: Size(maxWidth, MediaQuery.sizeOf(context).height)),
            child: child!,
          ),
        ),
      ),
    );
  }
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
        title: 'Vanguard Simulator',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        // Everything, sheets and dialogs included, inside the same column of
        // readable width.
        builder: (context, child) => _Readable(child: child),
        home: const DeckListScreen(),
      ),
    );
  }
}
