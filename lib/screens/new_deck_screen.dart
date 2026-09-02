import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../games/game_definition.dart';
import '../games/games.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/option_picker.dart';

/// Pops the new deck's id, or null when the user backs out.
class NewDeckScreen extends StatefulWidget {
  const NewDeckScreen({super.key});

  @override
  State<NewDeckScreen> createState() => _NewDeckScreenState();
}

class _NewDeckScreenState extends State<NewDeckScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _gameId = defaultGameId;
  late String _formatId = gameById(_gameId).defaultFormatId;
  String _accent = accents.first.key;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = gameById(_gameId);
    final format = game.format(_formatId);

    return Scaffold(
      appBar: AppBar(title: const Text('New Deck')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          LabeledField(
            label: 'Deck name',
            child: TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Dragon Empire aggro',
              ),
            ),
          ),
          if (games.length > 1)
            LabeledField(
              label: 'Game',
              child: OptionPicker(
                options: [
                  for (final g in games)
                    FieldOption(g.id, g.name, color: g.accent),
                ],
                value: _gameId,
                onChanged: (value) => setState(() {
                  _gameId = value;
                  _formatId = gameById(value).defaultFormatId;
                }),
              ),
            )
          else
            LabeledField(
              label: 'Game',
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
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
                    const SizedBox(height: 2),
                    Text(
                      game.tagline,
                      style: const TextStyle(
                        color: AppColors.textFaint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
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
          LabeledField(
            label: 'Colour',
            child: AccentPicker(
              value: _accent,
              onChanged: (value) => setState(() => _accent = value),
            ),
          ),
          LabeledField(
            label: 'Notes',
            helper: 'Optional. Match-ups, tech choices, anything you want to remember.',
            child: TextField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What this deck is trying to do…',
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: _nameController.text.trim().isEmpty ? null : _create,
            icon: const Icon(Icons.add),
            label: const Text('Create deck'),
          ),
        ],
      ),
    );
  }

  void _create() {
    final deck = context.read<DeckStore>().createDeck(
      name: _nameController.text,
      gameId: _gameId,
      formatId: _formatId,
      description: _descriptionController.text,
      accent: _accent,
    );
    Navigator.of(context).pop(deck.id);
  }
}
