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
  String? _error;
  DecklogImportResult? _result;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = gameById('vanguard');
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Import from Deck Log')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (result != null)
            _Summary(result: result)
          else ...[
            const Text(
              'Deck Log is Bushiroad\'s official deck site, reached through '
              'Fighter Navigator. Open your deck there, share it, and paste '
              'the link or the deck code here.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            LabeledField(
              label: 'Deck Log link or code',
              helper:
                  'For example decklog-en.bushiroad.com/view/ABC123, or just '
                  'ABC123.',
              child: TextField(
                controller: _controller,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
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
              label: Text(_busy ? 'Importing…' : 'Import deck'),
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
    _controller.text = text;
    setState(() => _error = null);
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final store = context.read<DeckStore>();
    final catalog = context.read<CardCatalog>();

    try {
      final source = await loadDecklog(_controller.text, fetch: widget.fetch);
      if (!source.isVanguard && source.gameTitleId.isNotEmpty) {
        throw const DecklogException(
          'That Deck Log entry is for one of Bushiroad\'s other games, not '
          'Cardfight!! Vanguard.',
        );
      }

      final result = await importDecklogDeck(
        store,
        catalog,
        source,
        formatId: _formatId,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } on DecklogException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.result});

  final DecklogImportResult result;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.deck.name,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${result.cardsAdded} cards imported, '
          '${result.matched} matched to the card database.',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
        if (result.unmatched.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.unmatched.length} card'
                  '${result.unmatched.length == 1 ? '' : 's'} not in the '
                  'database',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'They were added with the name and count Deck Log gave, so '
                  'the deck is complete, but their details are blank until you '
                  'fill them in.',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                for (final name in result.unmatched)
                  Text(
                    '· $name',
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(result.deck.id),
          icon: const Icon(Icons.arrow_forward),
          label: const Text('Open the deck'),
        ),
      ],
    );
  }
}
