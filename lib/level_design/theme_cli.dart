// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'design.dart';
import 'themed.dart';

/// Generates the board of a theme designer draft from the command line and
/// saves it into the draft, as the designer's own "生成" and "保存" do.
///
/// Usage: `theme_cli.dart <design.json> [seeds=20] [budget=30000]`
///
/// The draft's `options` are the designer's (`targets`, `superset`, `total`,
/// `rules`, `grows`) plus an optional `caps` map of technique to the most
/// times it may be used, which the designer itself does not offer. Seeds 1,
/// 2, … are tried in turn; the first board that meets the goal is written
/// back as `seed`, `counts`, `fragments`, `orderCorrelation` and `level`,
/// with the file's name as the level's ID. Exits with status 1 when the
/// painting cannot be generated or no seed finds a board.
void main(List<String> args) {
  final file = File(args[0]);
  final seeds = args.length > 1 ? int.parse(args[1]) : 20;
  final budget = args.length > 2 ? int.parse(args[2]) : 30000;
  final draft = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final size = draft['size'] as int;
  final theme = [
    for (final row in draft['theme'] as List)
      [for (final id in row as List) id as int?],
  ];
  final options = draft['options'] as Map<String, Object?>;
  final grows = options['grows'] as bool? ?? false;
  final problems = themeProblems(size, theme, grows);
  if (problems.isNotEmpty) {
    stderr.writeln('${file.path}: ${problems.join('; ')}');
    exit(1);
  }
  final [lo, hi] = (options['total'] as List).cast<int>();
  final goal = Goal(
    {...(options['targets'] as List).cast<String>()},
    (lo, hi),
    {...defaultCaps, ...?(options['caps'] as Map?)?.cast<String, int>()},
    superset: options['superset'] as bool? ?? false,
    rules: options['rules'] as int? ?? 1,
  );
  final name = file.uri.pathSegments.last.replaceAll('.json', '');
  for (var seed = 1; seed <= seeds; seed++) {
    final ThemeResult? result;
    try {
      result = generateThemed(
        ThemeRequest(
          size: size,
          theme: theme,
          goal: goal,
          grows: grows,
          budget: budget,
          seed: seed,
        ),
      );
    } on StateError catch (error) {
      stderr.writeln('${file.path}: ${error.message}');
      exit(1);
    }
    if (result == null) continue;
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'size': size, 'theme': theme, 'options': options, 'seed': seed, 'counts': result.counts, 'fragments': result.fragments, 'orderCorrelation': result.orderCorrelation, 'level': levelJson(name, result)})}\n',
    );
    print('$name seed $seed ${result.steps} steps ${result.counts}');
    return;
  }
  stderr.writeln('${file.path}: no board in $seeds seeds');
  exit(1);
}
