/// What the CPU could play out of a given set of cards, and what it could not.
///
/// Widening the ability reader is only worth doing where it buys something, so
/// this says what a particular deck actually needs: which of its clauses the
/// reader already follows, and what shapes the rest fall into. Run it before
/// touching ability_reader.dart, and again afterwards to see what moved.
///
///     dart run tool/ability_coverage.dart DZ-SS03          # a set
///     dart run tool/ability_coverage.dart --name Nightrose # a card name
///     dart run tool/ability_coverage.dart D-PR/1020EN ...  # card numbers
library;

import 'dart:convert';
import 'dart:io';

import 'package:tcg_decks/playtest/ability_reader.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/ability_coverage.dart '
      '[--name TEXT] [SET-PREFIX | CARD-NUMBER ...]',
    );
    exit(2);
  }

  final names = <String>[];
  final numbers = <String>[];
  for (var i = 0; i < args.length; i += 1) {
    if (args[i] == '--name' && i + 1 < args.length) {
      names.add(args[i += 1].toLowerCase());
    } else {
      numbers.add(args[i].toLowerCase());
    }
  }

  // The catalog is read straight off disk rather than through the app's
  // loader, which needs Flutter: this is a command line tool, and the ability
  // reader it is measuring needs nothing but Dart.
  final decoded = jsonDecode(
    File('assets/cards/vanguard.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cards = (decoded['cards'] as List).cast<Map<String, dynamic>>();

  final wanted =
      cards.where((card) {
        final name = (card['n'] as String? ?? '').toLowerCase();
        if (names.any(name.contains)) return true;
        final printed = <String>[
          card['no'] as String? ?? '',
          ...?(card['no2'] as List?)?.cast<String>(),
        ];
        return printed.any(
          (no) => numbers.any((asked) => no.toLowerCase().startsWith(asked)),
        );
      }).toList()..sort(
        (a, b) => (a['n'] as String? ?? '').compareTo(b['n'] as String? ?? ''),
      );

  if (wanted.isEmpty) {
    stderr.writeln('no cards matched');
    exit(1);
  }

  var offered = 0;
  var text = 0;
  final unreadClauses = <String, int>{};
  stdout.writeln('${wanted.length} cards\n');

  for (final card in wanted) {
    final read = readAbilities(card['e'] as String? ?? '');
    if (read.prompted.isEmpty && read.unread.isEmpty) continue;
    stdout.writeln('${card['no']}  ${card['n']}');
    for (final ability in read.prompted) {
      offered += 1;
      stdout.writeln('  ✓ ${ability.text}');
    }
    for (final clause in read.unread) {
      text += 1;
      unreadClauses[clause] = (unreadClauses[clause] ?? 0) + 1;
      stdout.writeln('  ✗ $clause');
    }
    stdout.writeln('');
  }

  stdout.writeln('--- $offered offered to the player, $text text only');
  if (unreadClauses.isEmpty) return;

  // Which phrase stopped each one, so the next pattern to write is the one
  // that buys the most. This is the reader's own answer rather than a guess
  // made from keywords: it is the part it actually refused.
  final refusals = <String, int>{};
  for (final entry in unreadClauses.entries) {
    final part = refusedPart(entry.key) ?? '(unknown)';
    refusals[part] = (refusals[part] ?? 0) + entry.value;
  }
  final ranked = refusals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  stdout.writeln('\n--- what stopped the unread clauses');
  for (final refusal in ranked.take(25)) {
    stdout.writeln('  ${refusal.value.toString().padLeft(3)}  ${refusal.key}');
  }
}
