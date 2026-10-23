// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'dart:math';

import 'package:theme_designer/domain/board.dart';

/// Random board with a unique solution: a random non-touching permutation,
/// connected Regions grown from each cat, then cells moved between Regions
/// until every other solution is broken.
///
/// With a [theme], the painted cells are fixed: each painted Region gets
/// its cat inside its painted cells, only unpainted cells are grown and
/// moved, and painted Regions take no extra cells unless [themeGrows].
/// Without one, the search is exactly the one that made levels 11–100.
class BoardGenerator {
  BoardGenerator(
    this.size,
    this.rng, {
    this.minRegionSize = 1,
    this.theme,
    this.themeGrows = false,
  });
  final int size;
  final Random rng;

  /// [mutate] never shrinks a Region below this size (Regions already
  /// smaller may still grow). 1 keeps the rules-1 search unchanged.
  final int minRegionSize;

  /// Painted Region ID per cell, null for cells left to the generator.
  final List<List<int?>>? theme;

  /// Whether painted Regions may also take unpainted cells.
  final bool themeGrows;

  late final Set<int> _themeIDs = {
    for (final row in theme ?? const <List<int?>>[])
      for (final id in row) ?id,
  };

  bool _locked(int r, int c) => theme != null && theme![r][c] != null;

  /// Whether Region [id] may take an unpainted cell.
  bool _accepts(int id) => themeGrows || !_themeIDs.contains(id);

  /// Themed boards give up after this many failed starts.
  static const themedAttempts = 300;

  LevelDefinition generate(String id) {
    for (
      var attempt = 0;
      theme == null || attempt < themedAttempts;
      attempt++
    ) {
      final level = _tryGenerate(id);
      if (level != null) return level;
    }
    throw StateError('no board fits this theme');
  }

  LevelDefinition? _tryGenerate(String id) {
    final solution = theme == null ? _solution() : _themedSolution();
    if (solution == null) return null;
    final regions = theme == null ? _grow(solution) : _themedGrow(solution);
    if (regions == null) return null;
    if (theme != null) {
      return _reduceSolutions(regions, solution)
          ? levelOf(id, regions, solution)
          : null;
    }
    for (var attempt = 0; attempt < 200; attempt++) {
      final other = _otherSolution(regions, solution);
      if (other == null) {
        return levelOf(id, regions, solution);
      }
      if (!_breakSolution(regions, solution, other)) return null;
    }
    return null;
  }

  /// Themed boards: breaks the other solutions greedily. Each step takes
  /// one other solution and, of the moves that break it (an unpainted cat
  /// of it handed to a neighbouring Region), makes the one that leaves the
  /// fewest solutions. When no such move is allowed (its cats sit inside
  /// their Regions), a neighbouring Region's border advances towards one of
  /// them instead. False when it gives up.
  bool _reduceSolutions(List<List<int>> regions, List<int> solution) {
    const cap = 256;
    for (var step = 0; step < 300; step++) {
      final other = _otherSolution(regions, solution);
      if (other == null) return true;
      final moves = <(int, int, int)>[];
      final kills = <(int, int)>[];
      for (var r = 0; r < size; r++) {
        final c = other[r];
        if (c == solution[r] || _locked(r, c)) continue;
        kills.add((r, c));
        for (final to in _targets(regions, r, c)) {
          moves.add((r, c, to));
        }
      }
      if (moves.isEmpty) {
        if (!_advance(regions, solution, kills)) return false;
        continue;
      }
      moves.shuffle(rng);
      (int, int, int)? best;
      var fewest = cap + 1;
      for (final (r, c, to) in moves) {
        final from = regions[r][c];
        regions[r][c] = to;
        final count = _countSolutions(regions, cap);
        regions[r][c] = from;
        if (count < fewest) {
          fewest = count;
          best = (r, c, to);
        }
      }
      final (r, c, to) = best!;
      regions[r][c] = to;
    }
    return false;
  }

  /// Regions an unpainted cell may join: accepting neighbours below the
  /// size cap, and only when its own Region stays connected without it.
  List<int> _targets(List<List<int>> regions, int r, int c) {
    final from = regions[r][c];
    final targets = <int>{};
    for (final (dr, dc) in _dirs) {
      final nr = r + dr, nc = c + dc;
      if (nr < 0 || nc < 0 || nr >= size || nc >= size) continue;
      final to = regions[nr][nc];
      if (to != from && _accepts(to) && _sizeOf(regions, to) < maxRegionSize) {
        targets.add(to);
      }
    }
    if (targets.isEmpty) return const [];
    regions[r][c] = -2;
    final connected = _connected(regions, from);
    regions[r][c] = from;
    return connected ? targets.toList() : const [];
  }

  /// Hands a movable cell to a neighbouring Region, picking the cell
  /// closest to one of [kills] inside the same Region, so that Region's
  /// border creeps towards the cat it must eventually take. False when no
  /// cell can move.
  bool _advance(
    List<List<int>> regions,
    List<int> solution,
    List<(int, int)> kills,
  ) {
    var best = <(int, int, int)>[];
    var nearest = size * 2;
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (solution[r] == c || _locked(r, c)) continue;
        var d = size * 2;
        for (final (kr, kc) in kills) {
          if (regions[kr][kc] != regions[r][c]) continue;
          d = min(d, (kr - r).abs() + (kc - c).abs());
        }
        if (d > nearest) continue;
        final targets = _targets(regions, r, c);
        if (targets.isEmpty) continue;
        if (d < nearest) {
          nearest = d;
          best = [];
        }
        for (final to in targets) {
          best.add((r, c, to));
        }
      }
    }
    if (best.isEmpty) return false;
    final (r, c, to) = best[rng.nextInt(best.length)];
    regions[r][c] = to;
    return true;
  }

  /// Solutions of [regions], counted up to [limit].
  int _countSolutions(List<List<int>> regions, int limit) {
    var count = 0;
    var usedCols = 0, usedRegions = 0;
    final cols = <int>[];
    void search(int row) {
      if (count >= limit) return;
      if (row == size) {
        count++;
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
    return count;
  }

  /// Region IDs stay as generated (a random permutation), so each level
  /// gets its own colour layout. The hint engine scans constraints by ID,
  /// so traces are always taken on these final IDs.
  LevelDefinition levelOf(
    String id,
    List<List<int>> regions,
    List<int> solution,
  ) => LevelDefinition(
    id: id,
    size: size,
    catCount: size,
    maxMistakes: 3,
    regionIDs: [for (final row in regions) List.of(row)],
    solution: [for (var r = 0; r < size; r++) CellPosition(r, solution[r])],
  );

  /// Largest Region allowed: a quarter of the board.
  late final int maxRegionSize = size * size ~/ 4;

  int _sizeOf(List<List<int>> regions, int id) {
    var count = 0;
    for (final row in regions) {
      for (final cell in row) {
        if (cell == id) count++;
      }
    }
    return count;
  }

  /// Moves one random boundary cell (never a cat) into a neighbouring
  /// Region, keeping both connected and the solution unique. Returns the
  /// new layout, or null when the random move was not allowed.
  List<List<int>>? mutate(List<List<int>> regions, List<int> solution) {
    final next = [for (final row in regions) List.of(row)];
    final r = rng.nextInt(size), c = rng.nextInt(size);
    if (solution[r] == c || _locked(r, c)) return null;
    final from = next[r][c];
    final targets = <int>[];
    for (final (dr, dc) in _dirs) {
      final nr = r + dr, nc = c + dc;
      if (nr < 0 || nc < 0 || nr >= size || nc >= size) continue;
      if (next[nr][nc] != from && _accepts(next[nr][nc])) {
        targets.add(next[nr][nc]);
      }
    }
    if (targets.isEmpty) return null;
    final to = targets[rng.nextInt(targets.length)];
    if (_sizeOf(next, to) >= maxRegionSize) return null;
    if (minRegionSize > 1) {
      final donor = _sizeOf(next, from);
      if (donor >= minRegionSize && donor - 1 < minRegionSize) return null;
    }
    next[r][c] = -2;
    if (!_connected(next, from)) return null;
    next[r][c] = to;
    if (_otherSolution(next, solution) != null) return null;
    return next;
  }

  List<int> _solution() {
    while (true) {
      final cols = <int>[];
      bool place(int row) {
        if (row == size) return true;
        final order = List.generate(size, (i) => i)..shuffle(rng);
        for (final c in order) {
          if (cols.contains(c)) continue;
          if (row > 0 && (cols[row - 1] - c).abs() < 2) continue;
          cols.add(c);
          if (place(row + 1)) return true;
          cols.removeLast();
        }
        return false;
      }

      if (place(0)) return cols;
    }
  }

  static const _dirs = [(0, 1), (1, 0), (0, -1), (-1, 0)];

  List<List<int>> _grow(List<int> solution) {
    final regions = List.generate(size, (_) => List.filled(size, -1));
    // Shuffle IDs so region colours are not ordered by row.
    final ids = List.generate(size, (i) => i)..shuffle(rng);
    for (var r = 0; r < size; r++) {
      regions[r][solution[r]] = ids[r];
    }
    // Per-region growth weight gives uneven sizes: some regions stay tiny,
    // which is what makes locking and sandwiches appear.
    final weight = {for (final id in ids) id: 0.3 + rng.nextDouble() * 1.4};
    final grown = {for (final id in ids) id: 1};
    var left = size * size - size;
    while (left > 0) {
      final frontier = <(int, int, int)>[];
      final weights = <double>[];
      for (var r = 0; r < size; r++) {
        for (var c = 0; c < size; c++) {
          if (regions[r][c] != -1) continue;
          for (final (dr, dc) in _dirs) {
            final nr = r + dr, nc = c + dc;
            if (nr < 0 || nc < 0 || nr >= size || nc >= size) continue;
            final id = regions[nr][nc];
            if (id == -1) continue;
            frontier.add((r, c, id));
            // A full Region only grows when nothing else can.
            weights.add(grown[id]! >= maxRegionSize ? 1e-6 : weight[id]!);
          }
        }
      }
      var pick = rng.nextDouble() * weights.fold(0.0, (a, b) => a + b);
      var i = 0;
      while (pick > weights[i]) {
        pick -= weights[i];
        i++;
      }
      final (r, c, id) = frontier[i];
      regions[r][c] = id;
      grown[id] = grown[id]! + 1;
      left--;
    }
    return regions;
  }

  /// A solution other than [solution], or null when it is unique.
  List<int>? _otherSolution(List<List<int>> regions, List<int> solution) {
    final cols = <int>[];
    var usedCols = 0, usedRegions = 0;
    List<int>? found;
    bool search(int row) {
      if (row == size) {
        for (var r = 0; r < size; r++) {
          if (cols[r] != solution[r]) {
            found = List.of(cols);
            return true;
          }
        }
        return false;
      }
      for (var c = 0; c < size; c++) {
        if (usedCols & (1 << c) != 0) continue;
        final reg = regions[row][c];
        if (usedRegions & (1 << reg) != 0) continue;
        if (row > 0 && (cols[row - 1] - c).abs() < 2) continue;
        cols.add(c);
        usedCols |= 1 << c;
        usedRegions |= 1 << reg;
        if (search(row + 1)) return true;
        cols.removeLast();
        usedCols &= ~(1 << c);
        usedRegions &= ~(1 << reg);
      }
      return false;
    }

    search(0);
    return found;
  }

  /// Moves one of [other]'s cats (not a real cat) into a neighbouring
  /// Region, keeping the donor Region connected.
  bool _breakSolution(
    List<List<int>> regions,
    List<int> solution,
    List<int> other,
  ) {
    final cells = [
      for (var r = 0; r < size; r++)
        if (other[r] != solution[r] && !_locked(r, other[r])) (r, other[r]),
    ]..shuffle(rng);
    for (final (r, c) in cells) {
      final from = regions[r][c];
      final targets = <int>{};
      for (final (dr, dc) in _dirs) {
        final nr = r + dr, nc = c + dc;
        if (nr < 0 || nc < 0 || nr >= size || nc >= size) continue;
        if (regions[nr][nc] != from) targets.add(regions[nr][nc]);
      }
      targets.removeWhere(
        (id) => _sizeOf(regions, id) >= maxRegionSize || !_accepts(id),
      );
      if (targets.isEmpty) continue;
      regions[r][c] = -2;
      if (!_connected(regions, from)) {
        regions[r][c] = from;
        continue;
      }
      regions[r][c] = (targets.toList()..shuffle(rng)).first;
      return true;
    }
    return false;
  }

  /// A random non-touching permutation with exactly one cat in each
  /// painted Region, the rest on unpainted cells, whose painted cats cannot
  /// be rearranged among the painted cells alone (no unpainted cell could
  /// break that second solution). Null when none is found.
  List<int>? _themedSolution() {
    for (var attempt = 0; attempt < 50; attempt++) {
      final solution = _themedPermutation();
      if (solution == null) return null;
      if (_paintedArrangements(solution) == 1) return solution;
    }
    return null;
  }

  /// Ways to place the painted Regions' cats with the unpainted cats of
  /// [solution] kept in place, counted up to 2.
  int _paintedArrangements(List<int> solution) {
    final theme = this.theme!;
    var count = 0;
    var usedCols = 0;
    for (var r = 0; r < size; r++) {
      if (theme[r][solution[r]] == null) usedCols |= 1 << solution[r];
    }
    final cols = <int>[];
    final used = <int>{};
    void search(int row) {
      if (count >= 2) return;
      if (row == size) {
        count++;
        return;
      }
      final fixed = theme[row][solution[row]] == null;
      for (var c = 0; c < size; c++) {
        final id = theme[row][c];
        if (fixed ? c != solution[row] : id == null) continue;
        if (!fixed && (usedCols & (1 << c) != 0 || used.contains(id))) continue;
        if (row > 0 && (cols[row - 1] - c).abs() < 2) continue;
        cols.add(c);
        if (!fixed) {
          usedCols |= 1 << c;
          used.add(id!);
        }
        search(row + 1);
        cols.removeLast();
        if (!fixed) {
          usedCols &= ~(1 << c);
          used.remove(id);
        }
      }
    }

    search(0);
    return count;
  }

  List<int>? _themedPermutation() {
    final theme = this.theme!;
    final cols = <int>[];
    final used = <int>{};
    var free = 0;
    final freeCats = size - _themeIDs.length;
    var nodes = 0;
    bool place(int row) {
      if (row == size) return true;
      if (++nodes > 200000) return false;
      final order = List.generate(size, (i) => i)..shuffle(rng);
      for (final c in order) {
        if (cols.contains(c)) continue;
        if (row > 0 && (cols[row - 1] - c).abs() < 2) continue;
        final id = theme[row][c];
        if (id == null ? free >= freeCats : used.contains(id)) continue;
        cols.add(c);
        id == null ? free++ : used.add(id);
        if (place(row + 1)) return true;
        cols.removeLast();
        id == null ? free-- : used.remove(id);
      }
      return false;
    }

    return place(0) ? cols : null;
  }

  /// Painted cells keep their Regions; each cat on an unpainted cell seeds
  /// one of the unused IDs, and unpainted cells are grown from the Regions
  /// that [_accepts]. Null when some unpainted cells cannot be reached.
  List<List<int>>? _themedGrow(List<int> solution) {
    final theme = this.theme!;
    final regions = [
      for (final row in theme) [for (final id in row) id ?? -1],
    ];
    final spare = [
      for (var id = 0; id < size; id++)
        if (!_themeIDs.contains(id)) id,
    ]..shuffle(rng);
    for (var r = 0; r < size; r++) {
      if (regions[r][solution[r]] == -1) {
        regions[r][solution[r]] = spare.removeLast();
      }
    }
    final ids = {for (final row in regions) ...row}..remove(-1);
    final weight = {for (final id in ids) id: 0.3 + rng.nextDouble() * 1.4};
    final grown = {for (final id in ids) id: _sizeOf(regions, id)};
    var left = regions.expand((row) => row).where((id) => id == -1).length;
    while (left > 0) {
      final frontier = <(int, int, int)>[];
      final weights = <double>[];
      for (var r = 0; r < size; r++) {
        for (var c = 0; c < size; c++) {
          if (regions[r][c] != -1) continue;
          for (final (dr, dc) in _dirs) {
            final nr = r + dr, nc = c + dc;
            if (nr < 0 || nc < 0 || nr >= size || nc >= size) continue;
            final id = regions[nr][nc];
            if (id == -1 || !_accepts(id)) continue;
            frontier.add((r, c, id));
            weights.add(grown[id]! >= maxRegionSize ? 1e-6 : weight[id]!);
          }
        }
      }
      if (frontier.isEmpty) return null;
      var pick = rng.nextDouble() * weights.fold(0.0, (a, b) => a + b);
      var i = 0;
      while (i < weights.length - 1 && pick > weights[i]) {
        pick -= weights[i];
        i++;
      }
      final (r, c, id) = frontier[i];
      regions[r][c] = id;
      grown[id] = grown[id]! + 1;
      left--;
    }
    return regions;
  }

  /// Whether [regions] has exactly one solution, [solution].
  bool isUnique(List<List<int>> regions, List<int> solution) =>
      _otherSolution(regions, solution) == null;

  bool _connected(List<List<int>> regions, int id) {
    final cells = <(int, int)>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (regions[r][c] == id) cells.add((r, c));
      }
    }
    if (cells.isEmpty) return false;
    final seen = {cells.first};
    final stack = [cells.first];
    while (stack.isNotEmpty) {
      final (r, c) = stack.removeLast();
      for (final (dr, dc) in _dirs) {
        final n = (r + dr, c + dc);
        if (n.$1 < 0 || n.$2 < 0 || n.$1 >= size || n.$2 >= size) continue;
        if (regions[n.$1][n.$2] == id && seen.add(n)) stack.add(n);
      }
    }
    return seen.length == cells.length;
  }
}
