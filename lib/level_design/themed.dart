// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'dart:math';

import 'design.dart';
import 'generator.dart';
import 'trace.dart';

/// Generating a board around a hand-painted theme: painted cells keep
/// their Regions, the generator fills in the rest (see [BoardGenerator]).
///
/// [theme] holds a Region ID (0 … size − 1) per painted cell and null for
/// cells left to the generator.
class ThemeRequest {
  ThemeRequest({
    required this.size,
    required this.theme,
    required this.goal,
    this.grows = false,
    this.budget = 30000,
    required this.seed,
  });
  final int size;
  final List<List<int?>> theme;
  final Goal goal;
  final bool grows;
  final int budget;
  final int seed;
}

class ThemeResult {
  ThemeResult({
    required this.regionIDs,
    required this.solution,
    required this.counts,
    this.fragments,
    this.orderCorrelation,
    this.steps = 0,
  });
  final List<List<int>> regionIDs;

  /// Cat column per row.
  final List<int> solution;
  final Map<String, int> counts;
  final int? fragments;
  final double? orderCorrelation;
  final int steps;
}

/// Why [theme] cannot be generated, empty when it can be tried.
List<String> themeProblems(int size, List<List<int?>> theme, bool grows) {
  final problems = <String>[];
  final cells = <int, List<(int, int)>>{};
  var blank = 0;
  for (var r = 0; r < size; r++) {
    for (var c = 0; c < size; c++) {
      final id = theme[r][c];
      if (id == null) {
        blank++;
      } else {
        (cells[id] ??= []).add((r, c));
      }
    }
  }
  for (final id in cells.keys) {
    if (id < 0 || id >= size) problems.add('颜色 ${id + 1} 超出了 $size 种颜色');
  }
  for (final MapEntry(key: id, value: region) in cells.entries) {
    if (_components(region.toSet()) > 1) {
      problems.add('颜色 ${id + 1} 没有连成一片');
    }
  }
  final spare = size - cells.length;
  if (blank > 0 && !grows) {
    final free = {
      for (var r = 0; r < size; r++)
        for (var c = 0; c < size; c++)
          if (theme[r][c] == null) (r, c),
    };
    final pieces = _components(free);
    if (spare == 0) {
      problems.add('$size 种颜色都用上了，剩下的空白格没有区域可以归属；涂满，或者允许涂色区域扩展');
    } else if (pieces > spare) {
      problems.add('空白被分成了 $pieces 块，但只剩 $spare 种颜色；允许涂色区域扩展，或者少用几种颜色');
    }
  }
  return problems;
}

/// A board that keeps [ThemeRequest.theme] and meets its goal, or null when
/// the budget runs out. Throws [StateError] when no board fits the theme
/// at all.
ThemeResult? generateThemed(
  ThemeRequest request, {
  void Function(int steps, Map<String, int>? best)? onProgress,
  bool Function()? cancelled,
}) {
  final size = request.size;
  final painted = request.theme.every((row) => row.every((id) => id != null));
  if (painted) return _checkPainted(request);
  final result = design(
    size,
    request.seed,
    request.goal,
    request.budget,
    generator: (rng) => BoardGenerator(
      size,
      rng,
      minRegionSize: request.goal.rules == 2 ? 3 : 1,
      theme: request.theme,
      themeGrows: request.grows,
    ),
    onProgress: onProgress,
    cancelled: cancelled,
  );
  if (result == null) return null;
  return ThemeResult(
    regionIDs: [
      for (final row in result['regionIDs'] as List<List<int>>) List.of(row),
    ],
    solution: [
      for (final p in result['solution'] as List) (p as List)[1] as int,
    ],
    counts: result['counts'] as Map<String, int>,
    fragments: result['fragments'] as int?,
    orderCorrelation: result['orderCorrelation'] as double?,
    steps: result['steps'] as int,
  );
}

/// A fully painted board has nothing to generate: it must already have one
/// solution, and the hints must reach it without an assumption.
ThemeResult _checkPainted(ThemeRequest request) {
  final size = request.size;
  final regions = [
    for (final row in request.theme) [for (final id in row) id!],
  ];
  final solutions = _solutions(regions, 2);
  if (solutions.isEmpty) throw StateError('这个盘面无解');
  if (solutions.length > 1) throw StateError('这个盘面不止一个解');
  final solution = solutions.single;
  final level = BoardGenerator(
    size,
    Random(0),
  ).levelOf('theme', regions, solution);
  final counts = traceHints(level);
  if (counts == null) throw StateError('提示引擎解不出这个盘面');
  return ThemeResult(
    regionIDs: regions,
    solution: solution,
    counts: counts,
    fragments: maxCandidateFragments(level),
    orderCorrelation: regionOrderCorrelation(level),
  );
}

/// Up to [limit] solutions of [regions], each as a cat column per row.
List<List<int>> _solutions(List<List<int>> regions, int limit) {
  final size = regions.length;
  final found = <List<int>>[];
  final cols = <int>[];
  var usedCols = 0, usedRegions = 0;
  void search(int row) {
    if (found.length >= limit) return;
    if (row == size) {
      found.add(List.of(cols));
      return;
    }
    for (var c = 0; c < size; c++) {
      final reg = regions[row][c];
      if (usedCols & (1 << c) != 0 || usedRegions & (1 << reg) != 0) continue;
      if (row > 0 && (cols[row - 1] - c).abs() < 2) continue;
      cols.add(c);
      usedCols |= 1 << c;
      usedRegions |= 1 << reg;
      search(row + 1);
      cols.removeLast();
      usedCols &= ~(1 << c);
      usedRegions &= ~(1 << reg);
    }
  }

  search(0);
  return found;
}

int _components(Set<(int, int)> cells) {
  final seen = <(int, int)>{};
  var pieces = 0;
  for (final start in cells) {
    if (!seen.add(start)) continue;
    pieces++;
    final stack = [start];
    while (stack.isNotEmpty) {
      final (r, c) = stack.removeLast();
      for (final n in [(r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)]) {
        if (cells.contains(n) && seen.add(n)) stack.add(n);
      }
    }
  }
  return pieces;
}

/// The level entry in `game-content.json` layout.
Map<String, Object?> levelJson(String id, ThemeResult result) => {
  'catCount': result.regionIDs.length,
  'givenStates': null,
  'id': id,
  'maxMistakes': 3,
  'regionIDs': result.regionIDs,
  'size': result.regionIDs.length,
  'solution': [
    for (var r = 0; r < result.solution.length; r++) [r, result.solution[r]],
  ],
};
