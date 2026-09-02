import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../games/game_definition.dart';
import '../games/games.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/action_sheet.dart';
import '../widgets/common.dart';
import '../widgets/option_picker.dart';

class DeckSettingsScreen extends StatefulWidget {
  const DeckSettingsScreen({super.key, required this.deckId});

  final String deckId;

  @override
  State<DeckSettingsScreen> createState() => _DeckSettingsScreenState();
}

class _DeckSettingsScreenState extends State<DeckSettingsScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late String _formatId;
  late String _accent;
  late final String _originalFormatId;

  @override
  void initState() {
    super.initState();
    final deck = context.read<DeckStore>().deckById(widget.deckId);
    _nameController = TextEditingController(text: deck?.name ?? '');
    _descriptionController = TextEditingController(
      text: deck?.description ?? '',
    );
    _formatId = deck?.formatId ?? '';
    _originalFormatId = _formatId;
    _accent = deck?.accent ?? accents.first.key;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeckStore>();
    final deck = store.deckById(widget.deckId);

    if (deck == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Deck Settings')),
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
    final format = game.format(_formatId);

    return Scaffold(
      appBar: AppBar(title: const Text('Deck Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          LabeledField(
            label: 'Deck name',
            child: TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          LabeledField(
            label: 'Format',
            helper: format.description,
            child: OptionPicker(
              options: [
                for (final f in game.formats) FieldOption(f.id, f.name),
              ],
              value: _formatId,
              onChanged: (value) => setState(() => _formatId = value),
            ),
          ),
          if (_formatId != _originalFormatId)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                'Changing format keeps every card. Cards in a zone the new format does not use stay saved but stop counting.',
                style: const TextStyle(
                  color: AppColors.warning,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          LabeledField(
            label: 'Colour',
            child: AccentPicker(
              value: _accent,
              onChanged: (value) => setState(() => _accent = value),
            ),
          ),
          LabeledField(
            label: 'Notes',
            child: TextField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: _delete,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
              ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete deck'),
            ),
          ),
        ],
      ),
    );
  }

  void _save() {
    context.read<DeckStore>().updateDeck(
      widget.deckId,
      name: _nameController.text.trim().isEmpty
          ? null
          : _nameController.text.trim(),
      description: _descriptionController.text,
      formatId: _formatId,
      accent: _accent,
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final store = context.read<DeckStore>();
    final deck = store.deckById(widget.deckId);
    if (deck == null) return;
    final ok = await confirm(
      context,
      title: 'Delete deck?',
      message: '"${deck.name}" will be removed. This cannot be undone.',
    );
    if (!ok || !mounted) return;
    store.deleteDeck(deck.id);
    if (!mounted) return;
    // Leave both this screen and the deck screen behind it.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}
