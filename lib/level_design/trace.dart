// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'dart:math';

import 'package:theme_designer/domain/board.dart';
import 'package:theme_designer/domain/logical_hint.dart';
import 'package:theme_designer/domain/logical_solver.dart';

/// Advanced techniques a designed level can feature, in hint order.
const advancedTechniques = [
  'lockedPair', // Locked Pair / Triple (K = 2–3)
  'strongLink',
  'commonAttack',
  'lockedQuad', // K = 4–5
  'pairedAttack',
  'leftover',
  'branch',
];

String techniqueOf(LogicalReason reason) => switch (reason) {
  OnlyCandidateReason() => 'only',
  AlreadyHasCatReason() || AdjacentToCatReason() => 'propagate',
  LockedSetReason(:final sources) => switch (sources.length) {
    1 => 'locked1',
    2 || 3 => 'lockedPair',
    _ => 'lockedQuad',
  },
  StrongLinkReason() => 'strongLink',
  CommonAttackReason() => 'commonAttack',
  PairedAttackReason() => 'pairedAttack',
  LeftoverReason() => 'leftover',
  BranchConsensusReason() => 'branch',
  ContradictionFromAssumptionReason() => 'assumption',
  MistakenExclusionReason() => 'mistake',
};

/// Follows hints from a blank board. Returns technique → hint count, or
/// null when the hints get stuck or disagree with the solution.
Map<String, int>? traceHints(LevelDefinition level) {
  final steps = traceSteps(level);
  if (steps == null) return null;
  final counts = <String, int>{};
  for (final (t, _) in steps) {
    counts[t] = (counts[t] ?? 0) + 1;
  }
  return counts;
}

/// Every hint from a blank board as (technique, cats placed), or null when
/// the hints get stuck or disagree with the solution.
List<(String, int)>? traceSteps(LevelDefinition level) {
  final solution = level.solution.toSet();
  var puzzle = level.makePuzzle();
  final steps = <(String, int)>[];
  var cats = puzzle.catPositions.length;
  while (cats < level.catCount) {
    final outcome = LogicalHintEngine.nextHint(level, puzzle);
    if (outcome is! HintAvailable) return null;
    final hint = outcome.hint;
    var placed = 0;
    for (final action in hint.actions) {
      if (action.placesCat != solution.contains(action.position)) return null;
      if (action.placesCat) placed++;
      puzzle = puzzle.withState(
        action.position,
        action.placesCat ? CellState.cat : CellState.excluded,
      );
    }
    cats += placed;
    steps.add((techniqueOf(hint.reason), placed));
  }
  return steps;
}

/// The most pieces any Region's remaining candidates break into while the
/// hints solve the board (8-neighbour pieces), counting only candidates
/// spread over at least half the board. High values mean a player sees one
/// colour scattered far apart as isolated cells.
int maxCandidateFragments(LevelDefinition level) {
  final solution = level.solution.toSet();
  var puzzle = level.makePuzzle();
  var worst = 1;
  while (puzzle.catPositions.length < level.catCount) {
    final outcome = LogicalHintEngine.nextHint(level, puzzle);
    if (outcome is! HintAvailable) return worst;
    for (final action in outcome.hint.actions) {
      if (action.placesCat != solution.contains(action.position)) return worst;
      puzzle = puzzle.withState(
        action.position,
        action.placesCat ? CellState.cat : CellState.excluded,
      );
    }
    final n = level.size;
    final byRegion = <int, Set<(int, int)>>{};
    final solved = <int>{};
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final id = level.regionIDs[r][c];
        switch (puzzle.states[r * n + c]) {
          case CellState.cat:
            solved.add(id);
          case CellState.empty:
            (byRegion[id] ??= {}).add((r, c));
          case CellState.excluded:
            break;
        }
      }
    }
    for (final MapEntry(key: id, value: cells) in byRegion.entries) {
      if (solved.contains(id)) continue;
      final rows = cells.map((p) => p.$1), cols = cells.map((p) => p.$2);
      final span =
          [
            rows.reduce(max) - rows.reduce(min),
            cols.reduce(max) - cols.reduce(min),
          ].reduce(max) +
          1;
      if (span * 2 < n) continue;
      final pieces = _pieces(cells);
      if (pieces > worst) worst = pieces;
    }
  }
  return worst;
}

/// Spearman correlation between a Region's size and when the hints place
/// its cat, from a blank board. Near 1 means the board always solves
/// smallest Region first, biggest last; designed boards sit near 0.
double regionOrderCorrelation(LevelDefinition level) {
  final sizes = <int, int>{};
  for (final row in level.regionIDs) {
    for (final id in row) {
      sizes[id] = (sizes[id] ?? 0) + 1;
    }
  }
  final order = <int, int>{};
  var puzzle = level.makePuzzle();
  while (puzzle.catPositions.length < level.catCount) {
    final outcome = LogicalHintEngine.nextHint(level, puzzle);
    if (outcome is! HintAvailable) return 1;
    for (final action in outcome.hint.actions) {
      if (action.placesCat) {
        order[level.regionAt(action.position)] ??= order.length;
      }
      puzzle = puzzle.withState(
        action.position,
        action.placesCat ? CellState.cat : CellState.excluded,
      );
    }
  }
  // A preplaced cat is not a player deduction; compare only solved Regions.
  final givenRegions = {
    for (final p in level.givenPositions) level.regionAt(p),
  };
  final ids = sizes.keys.where((id) => !givenRegions.contains(id)).toList();
  return _spearman(
    [for (final id in ids) sizes[id]!.toDouble()],
    [for (final id in ids) (order[id] ?? ids.length).toDouble()],
  );
}

double _spearman(List<double> a, List<double> b) {
  List<double> ranks(List<double> x) {
    final idx = List.generate(x.length, (i) => i)
      ..sort((i, j) => x[i].compareTo(x[j]));
    final r = List<double>.filled(x.length, 0);
    for (var i = 0; i < idx.length;) {
      var j = i;
      while (j + 1 < idx.length && x[idx[j + 1]] == x[idx[i]]) {
        j++;
      }
      for (var k = i; k <= j; k++) {
        r[idx[k]] = (i + j) / 2;
      }
      i = j + 1;
    }
    return r;
  }

  final ra = ranks(a), rb = ranks(b);
  final ma = ra.reduce((x, y) => x + y) / ra.length;
  final mb = rb.reduce((x, y) => x + y) / rb.length;
  var cov = 0.0, va = 0.0, vb = 0.0;
  for (var i = 0; i < ra.length; i++) {
    cov += (ra[i] - ma) * (rb[i] - mb);
    va += (ra[i] - ma) * (ra[i] - ma);
    vb += (rb[i] - mb) * (rb[i] - mb);
  }
  return va == 0 || vb == 0 ? 0 : cov / sqrt(va * vb);
}

int _pieces(Set<(int, int)> cells) {
  final seen = <(int, int)>{};
  var pieces = 0;
  for (final start in cells) {
    if (!seen.add(start)) continue;
    pieces++;
    final stack = [start];
    while (stack.isNotEmpty) {
      final (r, c) = stack.removeLast();
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          final next = (r + dr, c + dc);
          if (cells.contains(next) && seen.add(next)) stack.add(next);
        }
      }
    }
  }
  return pieces;
}
