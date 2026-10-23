// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
/// Core board vocabulary: coordinates, cell values, levels and the mutable
/// puzzle. Pure Dart — nothing in `lib/domain` may import Flutter.
library;

/// A zero-based `[row, column]` board coordinate.
class CellPosition implements Comparable<CellPosition> {
  const CellPosition(this.row, this.column);

  final int row;
  final int column;

  /// Row-major order, matching every deterministic scan in the engine.
  @override
  int compareTo(CellPosition other) =>
      row == other.row ? column - other.column : row - other.row;

  bool isAdjacentTo(CellPosition other) =>
      (row - other.row).abs() <= 1 && (column - other.column).abs() <= 1;

  @override
  bool operator ==(Object other) =>
      other is CellPosition && other.row == row && other.column == column;

  @override
  int get hashCode => row * 1000 + column;

  @override
  String toString() => 'R${row + 1}C${column + 1}';
}

/// The three values a cell can hold.
enum CellState { empty, excluded, cat }

/// One shipped board: its Region layout, optional given cells and the unique
/// solution used by challenge mode to refuse a wrong cat.
class LevelDefinition {
  LevelDefinition({
    required this.id,
    required this.size,
    required this.catCount,
    required this.maxMistakes,
    required this.regionIDs,
    required this.solution,
    this.givenStates,
    this.themeCells = const {},
  }) : givenPositions = _givenPositions(givenStates);

  final String id;
  final int size;
  final int catCount;
  final int maxMistakes;
  final List<List<int>> regionIDs;
  final List<List<CellState>>? givenStates;
  final List<CellPosition> solution;

  /// Cells locked at level start because the level ships with a clue there.
  final Set<CellPosition> givenPositions;

  /// The cells that draw the level's picture, shown first when the board
  /// appears. Empty for a level without one. Presentation only: no rule
  /// reads it.
  final Set<CellPosition> themeCells;

  int regionAt(CellPosition position) =>
      regionIDs[position.row][position.column];

  /// Every Region ID on the board, ascending.
  late final List<int> sortedRegionIDs = ({
    for (final row in regionIDs) ...row,
  }.toList()..sort());

  Puzzle makePuzzle() => Puzzle(
    size: size,
    states: [
      for (var row = 0; row < size; row++)
        for (var column = 0; column < size; column++)
          givenStates?[row][column] ?? CellState.empty,
    ],
  );

  static Set<CellPosition> _givenPositions(List<List<CellState>>? given) {
    if (given == null) return const {};
    return {
      for (var row = 0; row < given.length; row++)
        for (var column = 0; column < given[row].length; column++)
          if (given[row][column] != CellState.empty) CellPosition(row, column),
    };
  }
}

/// The player's committed board: one [CellState] per cell, row-major.
class Puzzle {
  Puzzle({required this.size, required List<CellState> states})
    : states = List.unmodifiable(states) {
    if (states.length != size * size) {
      throw ArgumentError(
        'Expected ${size * size} states, got ${states.length}',
      );
    }
  }

  final int size;
  final List<CellState> states;

  bool contains(int row, int column) =>
      row >= 0 && row < size && column >= 0 && column < size;

  CellState? stateAt(CellPosition position) =>
      contains(position.row, position.column)
      ? states[position.row * size + position.column]
      : null;

  Puzzle withState(CellPosition position, CellState state) {
    final updated = List<CellState>.of(states);
    updated[position.row * size + position.column] = state;
    return Puzzle(size: size, states: updated);
  }

  Iterable<CellPosition> get positions sync* {
    for (var row = 0; row < size; row++) {
      for (var column = 0; column < size; column++) {
        yield CellPosition(row, column);
      }
    }
  }

  List<CellPosition> get catPositions => [
    for (final p in positions)
      if (stateAt(p) == CellState.cat) p,
  ];

  bool get isBlank => states.every((state) => state == CellState.empty);

  @override
  bool operator ==(Object other) {
    if (other is! Puzzle || other.size != size) return false;
    for (var i = 0; i < states.length; i++) {
      if (states[i] != other.states[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(size, Object.hashAll(states));
}
