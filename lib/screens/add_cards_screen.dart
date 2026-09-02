import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../games/card_catalog.dart';
import '../games/game_definition.dart';
import '../games/games.dart';
import '../models/card_definition.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/card_row.dart';
import '../widgets/common.dart';
import '../widgets/field_prompt.dart';
import '../widgets/option_picker.dart';
import 'card_editor_screen.dart';

enum _Source { database, library }

/// Search the bundled card database or your own library, and drop cards into
/// one zone of a deck.
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
  _Source _source = _Source.database;

  GameDefinition? _game;
  bool _requestedCatalog = false;
  List<CatalogCard>? _catalogCards;

  /// Attribute values the catalog actually holds, so the filter chips only
  /// offer choices that can return something.
  final Map<String, Set<String>> _catalogValues = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deck = context.read<DeckStore>().deckById(widget.deckId);
    if (deck == null) return;
    final game = gameById(deck.gameId);
    _game = game;
    final asset = game.catalogAsset;
    if (asset == null) {
      _source = _Source.library;
      return;
    }
    if (_requestedCatalog) return;
    _requestedCatalog = true;
    context.read<CardCatalog>().load(asset).then((cards) {
      if (!mounted) return;
      setState(() {
        _catalogCards = cards;
        _catalogValues.clear();
        for (final card in cards) {
          for (final attribute in card.attributes.entries) {
            _catalogValues
                .putIfAbsent(attribute.key, () => <String>{})
                .add(attribute.value);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeckStore>();
    final deck = store.deckById(widget.deckId);
    final game = _game;

    if (deck == null || game == null) {
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

    final zone = game.zone(widget.zoneId);
    final hasCatalog = game.catalogAsset != null;

    // Select fields with a handful of options make good one-tap filters. On
    // the database tab an option is only offered when some card carries it --
    // the catalog has no trigger icons, for instance, so filtering by
    // "Critical" there could only ever come back empty.
    final quickFilters = <(CardField, List<FieldOption>)>[];
    for (final field in game.cardFields) {
      if (field.type != FieldType.select || field.options.isEmpty) continue;
      if (field.options.length > 6) continue;
      final options = _source == _Source.library
          ? field.options
          : [
              for (final option in field.options)
                if (_catalogValues[field.key]?.contains(option.value) ?? false)
                  option,
            ];
      if (options.length > 1) quickFilters.add((field, options));
    }

    return Scaffold(
      appBar: AppBar(title: Text('Add to ${zone?.name ?? 'deck'}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                if (hasCatalog)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SegmentedButton<_Source>(
                      segments: const [
                        ButtonSegment(
                          value: _Source.database,
                          icon: Icon(Icons.search, size: 18),
                          label: Text('Card database'),
                        ),
                        ButtonSegment(
                          value: _Source.library,
                          icon: Icon(Icons.bookmark_border, size: 18),
                          label: Text('My library'),
                        ),
                      ],
                      selected: {_source},
                      onSelectionChanged: (value) =>
                          setState(() => _source = value.first),
                      style: SegmentedButton.styleFrom(
                        backgroundColor: AppColors.surfaceAlt,
                        foregroundColor: AppColors.textMuted,
                        selectedBackgroundColor: AppColors.accent.withValues(
                          alpha: 0.16,
                        ),
                        selectedForegroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: _source == _Source.database
                        ? 'Search every card by name or number'
                        : 'Search your card library',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.textFaint,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: AppColors.textFaint,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
                for (final (field, options) in quickFilters)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OptionPicker(
                      options: options,
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
            child: _source == _Source.database
                ? _buildCatalogResults(game)
                : _buildLibraryResults(game, store),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createCard(game.id),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Enter by hand'),
      ),
    );
  }

  Widget _buildCatalogResults(GameDefinition game) {
    final cards = _catalogCards;
    if (cards == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (cards.isEmpty) {
      return const EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Card database unavailable',
        message:
            'The bundled catalogue could not be read. You can still enter '
            'cards by hand.',
      );
    }

    final results = CardCatalog.search(cards, _query, filters: _filters);
    final browsing = _query.trim().isEmpty && _filters.isEmpty;

    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search,
        title: browsing ? '${cards.length} cards ready' : 'No matching cards',
        message: browsing
            ? 'Type a card name or number, or tap a grade to browse.'
            : 'Nothing in the database matches. Check the spelling, or enter '
                  'the card by hand.',
      );
    }

    final store = context.read<DeckStore>();
    final deck = store.deckById(widget.deckId);
    final inZone = <String, int>{
      for (final entry in deck?.entries ?? const [])
        if (entry.zoneId == widget.zoneId) entry.cardId: entry.quantity,
    };

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final entry = results[index];
        // Show a count when this card is already in the zone.
        final known = store.findCard(
          gameId: game.id,
          cardNo: entry.cardNo,
          name: entry.name,
        );
        final quantity = known == null ? 0 : inZone[known.id] ?? 0;
        return _CatalogRow(
          game: game,
          entry: entry,
          quantity: quantity,
          onTap: () => _addFromCatalog(game, entry),
        );
      },
    );
  }

  Widget _buildLibraryResults(GameDefinition game, DeckStore store) {
    final needle = _query.trim().toLowerCase();
    final library =
        store
            .cardsForGame(game.id)
            .where(
              (card) =>
                  needle.isEmpty || card.name.toLowerCase().contains(needle),
            )
            .where(
              (card) => _filters.entries.every(
                (filter) => card.attributes[filter.key] == filter.value,
              ),
            )
            .toList()
          ..sort(game.compareCards);

    if (library.isEmpty) {
      return EmptyState(
        icon: Icons.bookmark_border,
        title: needle.isEmpty ? 'Your library is empty' : 'No matching cards',
        message: needle.isEmpty
            ? 'Cards you add from the database or enter by hand are kept here, '
                  'ready to reuse in your next deck.'
            : 'Nothing in your library matches. Try the card database.',
        action: game.catalogAsset == null
            ? null
            : FilledButton.icon(
                onPressed: () => setState(() => _source = _Source.database),
                icon: const Icon(Icons.search),
                label: const Text('Search the database'),
              ),
      );
    }

    final deck = store.deckById(widget.deckId);
    final inZone = <String, int>{
      for (final entry in deck?.entries ?? const [])
        if (entry.zoneId == widget.zoneId) entry.cardId: entry.quantity,
    };

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      itemCount: library.length,
      itemBuilder: (context, index) {
        final card = library[index];
        final quantity = inZone[card.id] ?? 0;
        return CardRow(
          game: game,
          card: card,
          onTap: () => _add(card),
          trailing: _AddTrailing(quantity: quantity),
        );
      },
    );
  }

  /// Adds a catalogue card, creating its library entry the first time and
  /// asking for anything the catalogue could not supply.
  Future<void> _addFromCatalog(GameDefinition game, CatalogCard entry) async {
    final store = context.read<DeckStore>();
    final attributes = Map<String, String>.from(entry.attributes);

    final existing = store.findCard(
      gameId: game.id,
      cardNo: entry.cardNo,
      name: entry.name,
    );

    if (existing == null) {
      for (final field in game.cardFields) {
        if (!field.promptWhenMissing) continue;
        if (!field.isVisible(attributes)) continue;
        if ((attributes[field.key] ?? '').isNotEmpty) continue;

        final answer = await promptForField(
          context,
          field: field,
          cardName: entry.name,
        );
        if (answer == null || answer.isEmpty) return; // Cancelled.
        attributes[field.key] = answer;
      }
    }

    if (!mounted) return;
    final card =
        existing ??
        store.ensureCard(
          gameId: game.id,
          name: entry.name,
          attributes: attributes,
        );
    _add(card);
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

/// A catalogue result. It has no library id yet, so it renders from the
/// game's describe/badge helpers on a throwaway [CardDefinition].
class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.game,
    required this.entry,
    required this.quantity,
    required this.onTap,
  });

  final GameDefinition game;
  final CatalogCard entry;
  final int quantity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = CardDefinition(
      id: 'catalog',
      gameId: game.id,
      name: entry.name,
      attributes: entry.attributes,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    return CardRow(
      game: game,
      card: preview,
      onTap: onTap,
      trailing: _AddTrailing(quantity: quantity),
    );
  }
}

class _AddTrailing extends StatelessWidget {
  const _AddTrailing({required this.quantity});

  final int quantity;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (quantity > 0)
          Text(
            '$quantity in deck',
            style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
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
    );
  }
}
