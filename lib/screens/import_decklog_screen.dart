import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../games/card_catalog.dart';
import '../games/game_definition.dart';
import '../games/games.dart';
import '../games/vanguard/vanguard_data.dart';
import '../import/decklog.dart';
import '../store/deck_store.dart';
import '../store/decklog_import.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/option_picker.dart';

/// Imports a deck from Bushiroad's Deck Log, the site behind Fighter
/// Navigator, from a share link or deck code.
class ImportDecklogScreen extends StatefulWidget {
  const ImportDecklogScreen({super.key, this.fetch = fetchDecklogPayload});

  /// Overridden in tests so the screen can be driven without a network.
  final DecklogFetcher fetch;

  @override
  State<ImportDecklogScreen> createState() => _ImportDecklogScreenState();
}

class _ImportDecklogScreenState extends State<ImportDecklogScreen> {
  final _controller = TextEditingController();
  String _formatId = formatStandard;
  bool _busy = false;
  String _progress = '';
  String? _error;

  /// The decks brought across, and the codes that could not be, from the last
  /// run. Both are kept: a batch that half worked has to say so.
  List<DecklogImportResult> _results = const [];
  List<({String code, String message})> _failures = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = gameById('vanguard');
    final done = _results.isNotEmpty || _failures.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Import from Deck Log')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (done)
            _Summary(
              results: _results,
              failures: _failures,
              onImportMore: _reset,
            )
          else ...[
            const Text(
              'Deck Log is Bushiroad\'s official deck site, reached through '
              'Fighter Navigator. Open your deck there, share it, and paste '
              'the link or the deck code here. Paste several, one per line, to '
              'import them all at once.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            LabeledField(
              label: 'Deck Log links or codes',
              helper:
                  'For example decklog-en.bushiroad.com/view/ABC123, or just '
                  'ABC123. One per line for several decks.',
              child: TextField(
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 8,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  hintText: '$decklogViewUrl…',
                  suffixIcon: IconButton(
                    tooltip: 'Paste',
                    icon: const Icon(
                      Icons.content_paste,
                      color: AppColors.textFaint,
                    ),
                    onPressed: _pasteFromClipboard,
                  ),
                ),
              ),
            ),
            LabeledField(
              label: 'Import as',
              helper: game.format(_formatId).description,
              child: OptionPicker(
                options: [
                  for (final format in game.formats)
                    FieldOption(format.id, format.name),
                ],
                value: _formatId,
                onChanged: (value) => setState(() => _formatId = value),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 18,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: _busy ? null : _import,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(
                _busy
                    ? (_progress.isEmpty ? 'Importing…' : _progress)
                    : 'Import decks',
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'If Deck Log refuses the request, open the deck\'s API address '
              'in a browser and paste the JSON it returns here instead. That '
              'is read the same way.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    // Appended, not replaced: pasting a second link should add a deck to the
    // batch rather than throw away the first.
    final existing = _controller.text.trimRight();
    _controller.text = existing.isEmpty ? text : '$existing\n$text';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() => _error = null);
  }

  void _reset() {
    setState(() {
      _controller.clear();
      _results = const [];
      _failures = const [];
      _error = null;
    });
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _progress = '';
      _error = null;
    });

    final store = context.read<DeckStore>();
    final catalog = context.read<CardCatalog>();

    final results = <DecklogImportResult>[];
    final failures = <({String code, String message})>[];

    try {
      final loads = await loadDecklogBatch(
        _controller.text,
        fetch: (code) async {
          if (mounted) setState(() => _progress = 'Fetching $code…');
          return widget.fetch(code);
        },
      );

      for (final load in loads) {
        final source = load.deck;
        if (source == null) {
          failures.add((code: load.code!, message: load.error!));
          continue;
        }
        // One deck for another game does not spoil the rest of the batch.
        if (!source.isVanguard && source.gameTitleId.isNotEmpty) {
          failures.add((
            code: source.code,
            message:
                'This is for one of Bushiroad\'s other games, not '
                'Cardfight!! Vanguard.',
          ));
          continue;
        }
        results.add(
          await importDecklogDeck(store, catalog, source, formatId: _formatId),
        );
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = '';
        _results = results;
        _failures = failures;
      });
    } on DecklogException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = '';
        _error = error.message;
      });
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.results,
    required this.failures,
    required this.onImportMore,
  });

  final List<DecklogImportResult> results;
  final List<({String code, String message})> failures;
  final VoidCallback onImportMore;

  @override
  Widget build(BuildContext context) {
    final cards = results.fold<int>(0, (sum, r) => sum + r.cardsAdded);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              results.isEmpty ? Icons.error_outline : Icons.check_circle,
              color: results.isEmpty ? AppColors.danger : AppColors.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                results.isEmpty
                    ? 'Nothing imported'
                    : '${results.length} deck${results.length == 1 ? '' : 's'} '
                          'imported, $cards cards',
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        for (final result in results) ...[
          const SizedBox(height: 20),
          _DeckSummary(result: result),
        ],
        if (failures.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${failures.length} deck${failures.length == 1 ? '' : 's'} '
                  'could not be imported',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                for (final failure in failures)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${failure.code} — ${failure.message}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (results.length == 1)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(results.single.deck.id),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Open the deck'),
          )
        else if (results.isNotEmpty)
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check),
            label: Text('Done — ${results.length} decks added'),
          ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: onImportMore,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Import more'),
        ),
      ],
    );
  }
}

/// One imported deck: what came across, where it went, and what could not be
/// matched to the card database.
class _DeckSummary extends StatelessWidget {
  const _DeckSummary({required this.result});

  final DecklogImportResult result;

  @override
  Widget build(BuildContext context) {
    final game = gameById(result.deck.gameId);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.deck.name,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${result.cardsAdded} cards, '
            '${result.matched} matched to the card database.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          // Where the cards landed, so a zone that came out wrong is visible
          // here rather than being discovered later on the deck screen.
          for (final zone in game.zones)
            if ((result.zoneCounts[zone.id] ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${result.zoneCounts[zone.id]} in the ${zone.name}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
          if (!result.rideDeckFound &&
              (result.zoneCounts[zoneRide] ?? 0) == 0 &&
              game.format(result.deck.formatId).zoneIds.contains(zoneRide)) ...[
            const SizedBox(height: 8),
            const Text(
              'Deck Log sent this deck as a single list, so there was no ride '
              'deck to separate out. Move the ride deck\'s four units across '
              'on the deck screen.',
              style: TextStyle(
                color: AppColors.warning,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (result.unmatched.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${result.unmatched.length} card'
              '${result.unmatched.length == 1 ? '' : 's'} not in the database: '
              '${result.unmatched.join(', ')}. '
              'Added with the name and count Deck Log gave, so the deck is '
              'complete, but their details are blank until you fill them in.',
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
