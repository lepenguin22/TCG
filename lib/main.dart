import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/deck_list_screen.dart';
import 'store/deck_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DeckStore();
  await store.load();
  runApp(TcgDecksApp(store: store));
}

class TcgDecksApp extends StatelessWidget {
  const TcgDecksApp({super.key, required this.store});

  final DeckStore store;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DeckStore>.value(
      value: store,
      child: MaterialApp(
        title: 'TCG Decks',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const DeckListScreen(),
      ),
    );
  }
}
