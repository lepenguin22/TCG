import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../games/games.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/action_sheet.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeckStore>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(label: 'Decks', value: store.decks.length),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  label: 'Cards in library',
                  value: store.cards.length,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'Backup',
            caption: 'Everything lives on this device only.',
          ),
          OutlinedButton.icon(
            onPressed: () => _export(context, store),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy backup to clipboard'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _import(context, store),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Import from clipboard'),
          ),
          const SizedBox(height: 24),
          const SectionHeader(
            title: 'Deck building rules',
            caption: 'What the app checks for you.',
          ),
          for (final game in games)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final format in game.formats)
                    _Rule(title: format.name, text: format.description),
                  for (final zone in game.zones)
                    _Rule(title: zone.name, text: zone.description),
                  const _Rule(
                    title: 'Triggers',
                    text: 'Exactly 16 trigger units in the main deck, at most 4 heal triggers and at most 1 over trigger.',
                  ),
                  const _Rule(
                    title: 'Ride deck crest',
                    text:
                        'Divinez added a fifth, optional ride deck card. A '
                        'ride deck may hold one crest alongside its four '
                        'units, and no more than one.',
                  ),
                  const _Rule(
                    title: 'Card pool',
                    text:
                        'Each format draws from one era. Standard is D-series '
                        'only, V Premium is V-series only, and Premium is '
                        'everything older. A card reprinted into a newer era '
                        'counts as legal there.',
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          const SectionHeader(title: 'Danger zone'),
          OutlinedButton.icon(
            onPressed: () => _reset(context, store),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete all data'),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Vanguard Simulator · offline decklist tracker',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          ),
          // Which build this is. Android's own app info reports the version
          // out of the pubspec, which never moves, so "is the fix in the copy
          // on my phone?" had no answer anywhere until here. The release
          // build passes the tag in; a build made by hand says so instead.
          const Center(
            child: Text(
              String.fromEnvironment(
                'APP_VERSION',
                defaultValue: 'Local build',
              ),
              style: TextStyle(color: AppColors.textFaint, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, DeckStore store) async {
    final payload = store.exportBackup();
    await Clipboard.setData(
      ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${store.decks.length} decks and ${store.cards.length} cards copied as JSON.',
        ),
      ),
    );
  }

  Future<void> _import(BuildContext context, DeckStore store) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text ?? '';
    if (!context.mounted) return;

    if (raw.trim().isEmpty) {
      _say(context, 'Clipboard is empty. Copy a backup as JSON first.');
      return;
    }

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      payload = decoded;
    } on FormatException {
      _say(context, 'The clipboard does not contain a valid backup.');
      return;
    }

    if (payload['app'] != 'tcg-decks' || payload['decks'] is! List) {
      _say(context, 'That JSON was not exported by this app.');
      return;
    }

    final deckCount = (payload['decks'] as List).length;
    final cardCount = (payload['cards'] as List? ?? []).length;
    final ok = await confirm(
      context,
      title: 'Import backup?',
      message:
          'Adds $deckCount decks and $cardCount cards. Anything already on this device is kept.',
      confirmLabel: 'Import',
      destructive: false,
    );
    if (!ok || !context.mounted) return;

    final result = store.importBackup(payload);
    _say(context, '${result.decks} decks and ${result.cards} cards added.');
  }

  Future<void> _reset(BuildContext context, DeckStore store) async {
    final ok = await confirm(
      context,
      title: 'Delete everything?',
      message: 'Every deck and every card in your library will be erased from this device.',
      confirmLabel: 'Delete all',
    );
    if (!ok || !context.mounted) return;
    store.resetAll();
    if (context.mounted) Navigator.of(context).pop();
  }

  void _say(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textFaint,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
