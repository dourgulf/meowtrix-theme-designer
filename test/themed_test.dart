// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'package:theme_designer/domain/board.dart';
import 'package:theme_designer/domain/logical_hint.dart';
import 'package:theme_designer/domain/logical_solver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_designer/search.dart';
import 'package:theme_designer/storage.dart';

List<List<int?>> heart() {
  final theme = List.generate(9, (_) => List<int?>.filled(9, null));
  for (final (r, c) in [
    (2, 2), (2, 3), (3, 1), (3, 2), (3, 3), (3, 4), //
    (4, 2), (4, 3), (4, 4), (5, 3), (5, 4), (6, 4),
  ]) {
    theme[r][c] = 0;
    theme[r][8 - c] = 0;
  }
  for (var c = 0; c < 9; c++) {
    theme[8][c] = 3;
  }
  return theme;
}

Goal anyGoal() => Goal({}, (0, 10), Map.of(defaultCaps), superset: true);

void main() {
  test(
    'a themed board keeps the painted cells and has one logical solution',
    () {
      final theme = heart();
      final result = generateThemed(
        ThemeRequest(size: 9, theme: theme, goal: anyGoal(), seed: 1),
      )!;
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          if (theme[r][c] != null) expect(result.regionIDs[r][c], theme[r][c]);
        }
      }
      // Painted Regions take no blank cells unless allowed to grow.
      expect(
        result.regionIDs.expand((row) => row).where((id) => id == 0),
        hasLength(theme.expand((row) => row).where((id) => id == 0).length),
      );

      final level = LevelDefinition(
        id: 'theme',
        size: 9,
        catCount: 9,
        maxMistakes: 3,
        regionIDs: result.regionIDs,
        solution: [
          for (var r = 0; r < 9; r++) CellPosition(r, result.solution[r]),
        ],
      );
      var puzzle = level.makePuzzle();
      while (puzzle.catPositions.length < 9) {
        final hint =
            (LogicalHintEngine.nextHint(level, puzzle) as HintAvailable).hint;
        expect(hint.reason, isNot(isA<ContradictionFromAssumptionReason>()));
        for (final action in hint.actions) {
          expect(action.placesCat, level.solution.contains(action.position));
          puzzle = puzzle.withState(action.position, action.state);
        }
      }
    },
  );

  test('reports themes that cannot be generated', () {
    final split = List.generate(6, (_) => List<int?>.filled(6, null));
    split[0][0] = 1;
    split[5][5] = 1;
    expect(themeProblems(6, split, false), ['颜色 2 没有连成一片']);

    final full = List.generate(6, (r) => List<int?>.generate(6, (c) => c));
    full[0][0] = null;
    expect(themeProblems(6, full, false), hasLength(1));
    expect(themeProblems(6, full, true), isEmpty);
  });

  test('a fully painted board is only checked', () {
    // Six columns: many solutions.
    final columns = List.generate(6, (r) => List<int?>.generate(6, (c) => c));
    expect(
      () => generateThemed(
        ThemeRequest(size: 6, theme: columns, goal: anyGoal(), seed: 1),
      ),
      throwsStateError,
    );
  });

  test('saved boards keep one row per line', () {
    expect(
      DesignStore.encode({
        'theme': [
          [0, null],
          [1, 2],
        ],
      }),
      '''
{
  "theme": [
    [0, null],
    [1, 2]
  ]
}''',
    );
  });
}
