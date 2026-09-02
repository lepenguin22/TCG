import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../games/game_definition.dart';
import '../games/games.dart';
import '../store/deck_store.dart';
import '../theme.dart';
import '../widgets/action_sheet.dart';
import '../widgets/common.dart';
import '../widgets/option_picker.dart';

/// Creates or edits a card in the personal library. The form is generated from
/// the game's `cardFields`, so it fits whatever TCG the deck belongs to.
class CardEditorScreen extends StatefulWidget {
  const CardEditorScreen({
    super.key,
    required this.gameId,
    this.cardId,
    this.addToDeckId,
    this.addToZoneId,
  });

  final String gameId;
  final String? cardId;

  /// When set, saving a new card also drops one copy into this deck zone.
  final String? addToDeckId;
  final String? addToZoneId;

  @override
  State<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends State<CardEditorScreen> {
  late final GameDefinition _game = gameById(widget.gameId);
  late final TextEditingController _nameController;
  final Map<String, TextEditingController> _textControllers = {};
  final Map<String, String> _attributes = {};
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.cardId == null
        ? null
        : context.read<DeckStore>().cardById(widget.cardId!);
    _isEditing = existing != null;
    _nameController = TextEditingController(text: existing?.name ?? '');

    if (existing != null) {
      _attributes.addAll(existing.attributes);
    } else {
      // Required select fields start on their first option.
      for (final field in _game.cardFields) {
        if (field.isRequired && field.options.isNotEmpty) {
          _attributes[field.key] = field.options.first.value;
        }
      }
    }

    for (final field in _game.cardFields) {
      if (field.type != FieldType.select) {
        _textControllers[field.key] = TextEditingController(
          text: _attributes[field.key] ?? '',
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canSave {
    if (_nameController.text.trim().isEmpty) return false;
    for (final field in _game.cardFields) {
      if (field.isRequired &&
          field.isVisible(_attributes) &&
          (_attributes[field.key] ?? '').isEmpty) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final visibleFields = _game.cardFields.where(
      (field) => field.isVisible(_attributes),
    );

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Card' : 'New Card')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          LabeledField(
            label: 'Card name',
            child: TextField(
              controller: _nameController,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Dragontree Maiden, Sharlka',
              ),
            ),
          ),
          for (final field in visibleFields)
            LabeledField(
              label: field.label,
              helper: field.helper,
              child: field.type == FieldType.select
                  ? OptionPicker(
                      options: field.options,
                      value: _attributes[field.key],
                      allowClear: !field.isRequired,
                      onChanged: (value) => setState(() {
                        if (value.isEmpty) {
                          _attributes.remove(field.key);
                        } else {
                          _attributes[field.key] = value;
                        }
                      }),
                    )
                  : TextField(
                      controller: _textControllers[field.key],
                      keyboardType: field.type == FieldType.number
                          ? TextInputType.number
                          : TextInputType.text,
                      minLines: field.type == FieldType.multiline ? 3 : 1,
                      maxLines: field.type == FieldType.multiline ? 6 : 1,
                      onChanged: (value) => _attributes[field.key] = value,
                      decoration: InputDecoration(hintText: field.placeholder),
                    ),
            ),
          if (!_isEditing && widget.addToDeckId != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Saving adds one copy to the deck you came from.',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12),
              ),
            ),
          FilledButton.icon(
            onPressed: _canSave ? _save : null,
            icon: const Icon(Icons.check),
            label: Text(_isEditing ? 'Save changes' : 'Save card'),
          ),
          if (_isEditing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton.icon(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete card'),
              ),
            ),
        ],
      ),
    );
  }

  void _save() {
    final store = context.read<DeckStore>();
    final cleaned = <String, String>{};
    for (final field in _game.cardFields) {
      final value = _attributes[field.key];
      if (field.isVisible(_attributes) && value != null && value.isNotEmpty) {
        cleaned[field.key] = value.trim();
      }
    }

    final card = store.saveCard(
      id: widget.cardId,
      gameId: widget.gameId,
      name: _nameController.text,
      attributes: cleaned,
    );

    final deckId = widget.addToDeckId;
    final zoneId = widget.addToZoneId;
    if (!_isEditing && deckId != null && zoneId != null) {
      store.addToDeck(deckId, card.id, zoneId);
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final cardId = widget.cardId;
    if (cardId == null) return;
    final store = context.read<DeckStore>();
    final ok = await confirm(
      context,
      title: 'Delete card?',
      message:
          '"${_nameController.text}" will be removed from your library and from every deck that uses it.',
    );
    if (!ok || !mounted) return;
    store.deleteCard(cardId);
    if (mounted) Navigator.of(context).pop();
  }
}
