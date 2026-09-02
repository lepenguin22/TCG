import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../games/game_definition.dart';
import '../games/games.dart';
import '../models/card_definition.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/card_row.dart';
import '../widgets/common.dart';
import '../widgets/option_picker.dart';
import 'card_editor_screen.dart';

/// Pick cards out of the personal library and drop them into one zone.
class AddCardsScreen extends StatefulWidget {
  const AddCardsScreen({super.key, required this.deckId, required this.zoneId});

  final String deckId;
  final String zoneId;

  @override
  State<AddCardsScreen> createState() => _AddCardsScreenState();
}

class _AddCardsScreenState extends State<AddCardsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  final Map<String, String> _filters = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeckStore>();
    final deck = store.deckById(widget.deckId);

    if (deck == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Add Cards')),
        body: EmptyState(
          icon: Icons.help_outline,
          title: 'Deck not found',
          message: 'It may have been deleted.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back'),
          ),
        ),
      );
    }

    final game = gameById(deck.gameId);
    final zone = game.zone(widget.zoneId);
    final needle = _query.trim().toLowerCase();

    final library =
        store
            .cardsForGame(deck.gameId)
            .where(
              (card) =>
                  needle.isEmpty || card.name.toLowerCase().contains(needle),
            )
            .where(
              (card) => _filters.entries.every(
                (filter) =>
                    filter.value.isEmpty ||
                    card.attributes[filter.key] == filter.value,
              ),
            )
            .toList()
          ..sort(game.compareCards);

    final inZone = {
      for (final entry in deck.entries)
        if (entry.zoneId == widget.zoneId) entry.cardId: entry.quantity,
    };

    // Select fields with a handful of options make good one-tap filters.
    final quickFilters = game.cardFields.where(
      (field) =>
          field.type == FieldType.select &&
          field.options.isNotEmpty &&
          field.options.length <= 6,
    );

    return Scaffold(
      appBar: AppBar(title: Text('Add to ${zone?.name ?? 'deck'}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'Search your card library',
                    prefixIcon: Icon(Icons.search, color: AppColors.textFaint),
                  ),
                ),
                for (final field in quickFilters)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OptionPicker(
                      options: field.options,
                      value: _filters[field.key],
                      allowClear: true,
                      labelBuilder: (option) =>
                          option.label.replaceFirst('Grade ', 'G'),
                      onChanged: (value) => setState(() {
                        if (value.isEmpty) {
                          _filters.remove(field.key);
                        } else {
                          _filters[field.key] = value;
                        }
                      }),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: library.isEmpty
                ? EmptyState(
                    icon: Icons.layers_outlined,
                    title: _query.isEmpty
                        ? 'Your card library is empty'
                        : 'No matching cards',
                    message: _query.isEmpty
                        ? 'Cards you enter are saved to a personal library, so you only ever type a card in once and can reuse it in every deck.'
                        : 'Nothing in your library matches. Create it as a new card instead.',
                    action: FilledButton.icon(
                      onPressed: () => _createCard(deck.gameId),
                      icon: const Icon(Icons.add),
                      label: const Text('Create a card'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: library.length,
                    itemBuilder: (context, index) {
                      final card = library[index];
                      final quantity = inZone[card.id] ?? 0;
                      return CardRow(
                        game: game,
                        card: card,
                        onTap: () => _add(card),
                        trailing: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (quantity > 0)
                              Text(
                                '$quantity in deck',
                                style: const TextStyle(
                                  color: AppColors.textFaint,
                                  fontSize: 11,
                                ),
                              ),
                            const Text(
                              'Add',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createCard(deck.gameId),
        icon: const Icon(Icons.add),
        label: const Text('New card'),
      ),
    );
  }

  void _add(CardDefinition card) {
    context.read<DeckStore>().addToDeck(widget.deckId, card.id, widget.zoneId);
    HapticFeedback.selectionClick();
  }

  Future<void> _createCard(String gameId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CardEditorScreen(
          gameId: gameId,
          addToDeckId: widget.deckId,
          addToZoneId: widget.zoneId,
        ),
      ),
    );
  }
}
