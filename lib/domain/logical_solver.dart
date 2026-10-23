// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'board.dart';
import 'logical_hint.dart';

/// Produces one deterministic deduction from the player's current board.
///
/// It deliberately receives no solution: a hint must be something the
/// player could have reasoned out. The board is diagnosed first, then the
/// easiest deterministic technique is tried, and only then a depth-1 proof
/// by contradiction.
///
/// With a `timeLimit`, a search still running when it passes stops and
/// returns [HintTimedOut]; without one the result depends on the board alone.
abstract final class LogicalHintEngine {
  static HintOutcome nextHint(
    LevelDefinition level,
    Puzzle puzzle, {
    Duration? timeLimit,
  }) {
    if (puzzle.size != level.size) return const HintUnavailable();
    final diagnosis = diagnoseContradiction(level, puzzle);
    if (diagnosis != null) return HintContradiction(diagnosis);
    final deadline = timeLimit == null ? null : _Deadline(timeLimit);
    try {
      final easiest = _SolveEngine(level, puzzle, deadline).easiestHintStep();
      if (easiest != null) return HintAvailable(easiest);
      final assumption = _assumptionHint(level, puzzle, deadline);
      if (assumption != null) return HintAvailable(assumption);
    } on _OutOfTime {
      return const HintTimedOut();
    }
    return const HintUnavailable();
  }

  static HintDiagnosis? diagnoseContradiction(
    LevelDefinition level,
    Puzzle puzzle,
  ) {
    final engine = _SolveEngine(level, puzzle);
    final clash = engine.clashingCats;
    if (clash != null) return ClashingCatsDiagnosis(clash.$1, clash.$2);
    final starved = engine.starvedConstraint;
    if (starved != null) return StarvedConstraintDiagnosis(starved);
    return null;
  }

  /// A hint only a depth-1 trial can produce: the first cell the solver
  /// rules out because assuming a cat there breaks the board.
  static LogicalHint? assumptionHint(LevelDefinition level, Puzzle puzzle) =>
      _assumptionHint(level, puzzle, null);

  static LogicalHint? _assumptionHint(
    LevelDefinition level,
    Puzzle puzzle,
    _Deadline? deadline,
  ) {
    final engine = _SolveEngine(level, puzzle, deadline)
      ..stopAtFirstContradiction = true;
    engine.solve(maxAssumptionDepth: 1);
    return engine.firstContradictionHint;
  }
}

/// Thrown out of a search whose time limit has passed.
class _OutOfTime implements Exception {
  const _OutOfTime();
}

class _Deadline {
  _Deadline(this.limit);
  final Duration limit;
  final Stopwatch _clock = Stopwatch()..start();

  void check() {
    if (_clock.elapsed > limit) throw const _OutOfTime();
  }
}

/// Ordered (source, target) family pairs scanned by locked-set deduction.
const _lockedSetFamilyPairs = [
  (ConstraintFamily.row, ConstraintFamily.column),
  (ConstraintFamily.column, ConstraintFamily.row),
  (ConstraintFamily.row, ConstraintFamily.region),
  (ConstraintFamily.region, ConstraintFamily.row),
  (ConstraintFamily.column, ConstraintFamily.region),
  (ConstraintFamily.region, ConstraintFamily.column),
];

const _maxLockedSetSize = 5;

/// Sandwich deduction only pairs constraints this small, so the player can
/// still picture every way the two cats could sit.
const _maxPairedCandidates = 4;

/// Largest almost locked set: this many sources in one more target.
const _maxLeftoverSources = 3;

enum _Outcome { solved, stuck, contradiction }

class _Step {
  const _Step(this.action, this.reason);
  final LogicalAction action;
  final LogicalReason reason;
}

class _AdvancedEvent {
  const _AdvancedEvent(this.reason, this.exclusions);
  final LogicalReason reason;
  final List<CellPosition> exclusions;
}

typedef _Masked = (_Constraint, int);

class _Constraint {
  const _Constraint(this.kind, this.candidates);
  final ConstraintKind kind;
  final List<CellPosition> candidates;
}

const _candidate = 0;
const _excluded = 1;
const _cat = 2;

/// Candidate board: every cell is a candidate, excluded, or a confirmed cat.
/// Stored as a flat row-major list so "sorted" scans are simple loops.
class _CandidateBoard {
  _CandidateBoard(LevelDefinition level, Puzzle puzzle)
    : size = level.size,
      regionIDsByCell = level.regionIDs,
      regionIDs = level.sortedRegionIDs,
      _regionCells = _buildRegionCells(level),
      _regionOrdinals = {
        for (final (i, id) in level.sortedRegionIDs.indexed) id: i,
      },
      _cells = [
        for (final state in puzzle.states)
          switch (state) {
            CellState.cat => _cat,
            CellState.excluded => _excluded,
            CellState.empty => _candidate,
          },
      ];

  _CandidateBoard._copy(_CandidateBoard other)
    : size = other.size,
      regionIDsByCell = other.regionIDsByCell,
      regionIDs = other.regionIDs,
      _regionCells = other._regionCells,
      _regionOrdinals = other._regionOrdinals,
      _cells = List.of(other._cells);

  final int size;
  final List<List<int>> regionIDsByCell;
  final List<int> regionIDs;
  final Map<int, List<CellPosition>> _regionCells;
  final Map<int, int> _regionOrdinals;
  final List<int> _cells;

  _CandidateBoard copy() => _CandidateBoard._copy(this);

  static Map<int, List<CellPosition>> _buildRegionCells(LevelDefinition l) {
    final map = <int, List<CellPosition>>{};
    for (var row = 0; row < l.size; row++) {
      for (var column = 0; column < l.size; column++) {
        map
            .putIfAbsent(l.regionIDs[row][column], () => [])
            .add(CellPosition(row, column));
      }
    }
    return map;
  }

  int _at(CellPosition p) => _cells[p.row * size + p.column];

  bool isCandidate(CellPosition p) => _at(p) == _candidate;
  bool isCat(CellPosition p) => _at(p) == _cat;
  bool isExcluded(CellPosition p) => _at(p) == _excluded;

  List<CellPosition> _where(int value) => [
    for (var i = 0; i < _cells.length; i++)
      if (_cells[i] == value) CellPosition(i ~/ size, i % size),
  ];

  List<CellPosition> get sortedCandidates => _where(_candidate);
  List<CellPosition> get sortedConfirmedCats => _where(_cat);
  int get confirmedCatCount => _cells.where((c) => c == _cat).length;

  bool confirmCat(CellPosition p) {
    if (!isCandidate(p)) return false;
    _cells[p.row * size + p.column] = _cat;
    return true;
  }

  bool exclude(CellPosition p) {
    if (!isCandidate(p)) return false;
    _cells[p.row * size + p.column] = _excluded;
    return true;
  }

  Iterable<CellPosition> cellsOf(ConstraintKind kind) sync* {
    switch (kind.family) {
      case ConstraintFamily.row:
        for (var c = 0; c < size; c++) {
          yield CellPosition(kind.index, c);
        }
      case ConstraintFamily.column:
        for (var r = 0; r < size; r++) {
          yield CellPosition(r, kind.index);
        }
      case ConstraintFamily.region:
        yield* _regionCells[kind.index] ?? const [];
    }
  }

  bool hasCat(ConstraintKind kind) => cellsOf(kind).any((p) => _at(p) == _cat);

  List<CellPosition> candidates(ConstraintKind kind) => [
    for (final p in cellsOf(kind))
      if (_at(p) == _candidate) p,
  ];

  /// Bit for the `family` constraint containing `p`: its row, column or
  /// Region ordinal.
  int targetBit(CellPosition p, ConstraintFamily family) => switch (family) {
    ConstraintFamily.row => p.row,
    ConstraintFamily.column => p.column,
    ConstraintFamily.region =>
      _regionOrdinals[regionIDsByCell[p.row][p.column]]!,
  };

  ConstraintKind constraintKind(CellPosition p, ConstraintFamily family) =>
      switch (family) {
        ConstraintFamily.row => ConstraintKind.row(p.row),
        ConstraintFamily.column => ConstraintKind.column(p.column),
        ConstraintFamily.region => ConstraintKind.region(
          regionIDsByCell[p.row][p.column],
        ),
      };

  List<ConstraintKind> allConstraintKinds(ConstraintFamily family) =>
      switch (family) {
        ConstraintFamily.row => [
          for (var i = 0; i < size; i++) ConstraintKind.row(i),
        ],
        ConstraintFamily.column => [
          for (var i = 0; i < size; i++) ConstraintKind.column(i),
        ],
        ConstraintFamily.region => [
          for (final id in regionIDs) ConstraintKind.region(id),
        ],
      };

  List<_Constraint> unresolvedConstraints(ConstraintFamily family) => [
    for (final kind in allConstraintKinds(family))
      if (!hasCat(kind)) _Constraint(kind, candidates(kind)),
  ];

  /// Whether two distinct positions can never both be cats.
  bool conflicts(CellPosition a, CellPosition b) {
    if (a == b) return false;
    if (a.row == b.row || a.column == b.column) return true;
    if (regionIDsByCell[a.row][a.column] == regionIDsByCell[b.row][b.column]) {
      return true;
    }
    return a.isAdjacentTo(b);
  }
}

/// The deduction engine behind hints: candidates, constraints and the
/// techniques in priority order.
class _SolveEngine {
  _SolveEngine(this.level, Puzzle puzzle, [this._deadline])
    : board = _CandidateBoard(level, puzzle);

  _SolveEngine._branch(_SolveEngine other)
    : level = other.level,
      board = other.board.copy(),
      _deadline = other._deadline;

  final LevelDefinition level;
  final _CandidateBoard board;
  final _Deadline? _deadline;
  final List<_Step> steps = [];

  bool stopAtFirstContradiction = false;
  LogicalHint? firstContradictionHint;

  _Outcome solve({required int maxAssumptionDepth}) {
    for (final cat in board.sortedConfirmedCats) {
      _propagateConstraints(cat);
    }
    return _resolve(0, maxAssumptionDepth);
  }

  _Outcome _resolve(int depth, int maxDepth) {
    while (true) {
      _deadline?.check();
      if (_hasContradiction) return _Outcome.contradiction;
      if (_isSolved) return _Outcome.solved;

      final deduction = _nextDeduction();
      if (deduction != null) {
        _placeCat(deduction.$1);
        continue;
      }

      final event = _nextAdvancedDeduction();
      if (event != null) {
        for (final position in event.exclusions) {
          _exclude(position, event.reason);
        }
        continue;
      }

      if (depth >= maxDepth) return _Outcome.stuck;

      var excludedByContradiction = false;
      for (final position in board.sortedCandidates) {
        final branch = _SolveEngine._branch(this);
        branch._forceAssumedCat(position);
        final outcome = branch._resolve(depth + 1, maxDepth);
        if (outcome == _Outcome.contradiction) {
          final reason = ContradictionFromAssumptionReason(
            position,
            branch.starvedConstraint,
          );
          if (_exclude(position, reason)) {
            firstContradictionHint ??= LogicalHint([
              LogicalAction.exclude(position),
            ], reason);
            excludedByContradiction = true;
            break;
          }
        }
      }
      if (!excludedByContradiction) return _Outcome.stuck;
      if (stopAtFirstContradiction) return _Outcome.stuck;
    }
  }

  /// One deduction, preferring what a player would spot first: cross off
  /// what a placed cat forbids, then a single candidate, then single-object
  /// locks, locked pair/triple, strong link, common attack, higher-order
  /// locked sets, sandwich, leftover and finally branch consensus.
  LogicalHint? easiestHintStep() {
    if (_hasContradiction) return null;

    for (final cat in board.sortedConfirmedCats) {
      final start = steps.length;
      _propagateConstraints(cat);
      final hint = _hintFromSteps(start);
      if (hint != null) return hint;
    }

    final deduction = _nextDeduction();
    if (deduction != null) {
      return LogicalHint([LogicalAction.placeCat(deduction.$1)], deduction.$2);
    }

    final event = _easiestAdvancedDeduction();
    if (event != null) {
      final actions = [
        for (final p in _hintExclusions(event))
          if (board.isCandidate(p)) LogicalAction.exclude(p),
      ];
      if (actions.isNotEmpty) return LogicalHint(actions, event.reason);
    }
    return _leftoverHint() ?? _branchConsensusHint();
  }

  /// Every cell the event's reasoning rules out, not just the first one.
  List<CellPosition> _hintExclusions(_AdvancedEvent event) {
    final reason = event.reason;
    if (reason is StrongLinkReason) {
      final link = reason.link;
      return [
        for (final p in board.sortedCandidates)
          if (p != link.first &&
              p != link.second &&
              board.conflicts(p, link.first) &&
              board.conflicts(p, link.second))
            p,
      ];
    }
    if (reason is CommonAttackReason) {
      final cands = reason.candidatePositions;
      return [
        for (final p in board.sortedCandidates)
          if (!cands.contains(p) && cands.every((c) => board.conflicts(p, c)))
            p,
      ];
    }
    return event.exclusions;
  }

  _AdvancedEvent? _easiestAdvancedDeduction() =>
      _lockedSetDeduction(const [1]) ??
      _lockedSetDeduction(const [2]) ??
      _lockedSetDeduction(const [3]) ??
      _nextStrongLinkDeduction() ??
      _nextCommonAttackDeduction() ??
      _nextHigherOrderLockedSetDeduction() ??
      _nextPairedAttackDeduction();

  /// Frozen scan order used by `solve`. Single-object locks add nothing
  /// here (strong link and common attack already cover them), and the
  /// sandwich, leftover and branch-consensus techniques stay hint-only so
  /// the depth-1 trial, and the constraint it names, keep their behavior.
  _AdvancedEvent? _nextAdvancedDeduction() =>
      _lockedSetDeduction(const [2, 3]) ??
      _nextCommonAttackDeduction() ??
      _nextStrongLinkDeduction() ??
      _nextHigherOrderLockedSetDeduction();

  _AdvancedEvent? _nextHigherOrderLockedSetDeduction() => _lockedSetDeduction([
    for (var size = 4; size <= _maxLockedSetSize; size++) size,
  ]);

  /// A single placement, or every exclusion sharing the first step's reason.
  LogicalHint? _hintFromSteps(int index) {
    final produced = steps.sublist(index);
    for (final step in produced) {
      if (step.action.placesCat) return LogicalHint([step.action], step.reason);
    }
    if (produced.isEmpty) return null;
    final first = produced.first.reason;
    final actions = [
      for (final step in produced)
        if (step.reason == first) step.action,
    ];
    return actions.isEmpty ? null : LogicalHint(actions, first);
  }

  void _placeCat(CellPosition position) {
    if (!board.confirmCat(position)) return;
    _propagateConstraints(position);
  }

  void _forceAssumedCat(CellPosition position) {
    if (!board.confirmCat(position)) return;
    _propagateConstraints(position);
  }

  bool _exclude(CellPosition position, LogicalReason reason) {
    if (!board.exclude(position)) return false;
    steps.add(_Step(LogicalAction.exclude(position), reason));
    return true;
  }

  void _propagateConstraints(CellPosition cat) {
    final catRegion = level.regionAt(cat);
    for (final p in board.sortedCandidates) {
      final LogicalReason? reason;
      if (p.row == cat.row) {
        reason = AlreadyHasCatReason(ConstraintKind.row(cat.row));
      } else if (p.column == cat.column) {
        reason = AlreadyHasCatReason(ConstraintKind.column(cat.column));
      } else if (level.regionAt(p) == catRegion) {
        reason = AlreadyHasCatReason(ConstraintKind.region(catRegion));
      } else if (p.isAdjacentTo(cat)) {
        reason = AdjacentToCatReason(cat);
      } else {
        reason = null;
      }
      if (reason != null) _exclude(p, reason);
    }
  }

  (CellPosition, LogicalReason)? _nextDeduction() {
    for (final family in ConstraintFamily.values) {
      for (final kind in board.allConstraintKinds(family)) {
        if (board.hasCat(kind)) continue;
        final candidates = board.candidates(kind);
        if (candidates.length == 1) {
          return (candidates.first, OnlyCandidateReason(kind));
        }
      }
    }
    return null;
  }

  _AdvancedEvent? _lockedSetDeduction(List<int> sizes) {
    final masks = <(ConstraintFamily, ConstraintFamily), List<_Masked>>{};
    for (final size in sizes) {
      for (final pair in _lockedSetFamilyPairs) {
        final sources = masks[pair] ??= _targetMasks(pair.$1, pair.$2);
        final event = _lockedSetFor(sources, pair.$2, size);
        if (event != null) return event;
      }
    }
    return null;
  }

  /// Unresolved `source` constraints, each with the bitmask of `target`
  /// constraints its candidates touch.
  List<_Masked> _targetMasks(
    ConstraintFamily source,
    ConstraintFamily target,
  ) => [
    for (final c in board.unresolvedConstraints(source))
      (
        c,
        c.candidates.fold(
          0,
          (mask, p) => mask | 1 << board.targetBit(p, target),
        ),
      ),
  ];

  /// Visits every `size`-combination of `sources`, in lexicographic order,
  /// whose candidates touch exactly `targetCount` targets, and returns the
  /// first non-null result of `visit`. Branches that already touch more
  /// targets are cut, which keeps the order of the combinations that remain.
  static T? _firstCombination<T>(
    List<_Masked> sources,
    int size,
    int targetCount,
    T? Function(List<_Constraint> combo) visit,
  ) {
    final chosen = <_Constraint>[];
    T? extend(int start, int mask) {
      if (chosen.length == size) {
        return _bitCount(mask) == targetCount ? visit(chosen) : null;
      }
      for (var i = start; i <= sources.length - (size - chosen.length); i++) {
        final next = mask | sources[i].$2;
        if (_bitCount(next) > targetCount) continue;
        chosen.add(sources[i].$1);
        final found = extend(i + 1, next);
        chosen.removeLast();
        if (found != null) return found;
      }
      return null;
    }

    return extend(0, 0);
  }

  static int _bitCount(int mask) {
    var count = 0;
    for (var m = mask; m != 0; m &= m - 1) {
      count++;
    }
    return count;
  }

  /// If `size` source constraints have candidates confined to exactly `size`
  /// target constraints, every other candidate in those targets is ruled out.
  _AdvancedEvent? _lockedSetFor(
    List<_Masked> sources,
    ConstraintFamily targetFamily,
    int size,
  ) => _firstCombination(sources, size, size, (combo) {
    final union = {for (final c in combo) ...c.candidates};
    final sortedTargets = {
      for (final p in union) board.constraintKind(p, targetFamily),
    }.toList()..sort();
    final affected = <CellPosition>[
      for (final kind in sortedTargets)
        for (final p in board.candidates(kind))
          if (!union.contains(p)) p,
    ];
    if (affected.isEmpty) return null;

    return _AdvancedEvent(
      LockedSetReason([for (final c in combo) c.kind]..sort(), sortedTargets),
      affected..sort(),
    );
  });

  _AdvancedEvent? _nextCommonAttackDeduction() {
    for (final family in ConstraintFamily.values) {
      for (final constraint in board.unresolvedConstraints(family)) {
        if (constraint.candidates.length < 3) continue;
        for (final candidate in board.sortedCandidates) {
          if (!constraint.candidates.contains(candidate) &&
              constraint.candidates.every(
                (c) => board.conflicts(candidate, c),
              )) {
            return _AdvancedEvent(
              CommonAttackReason(constraint.kind, constraint.candidates),
              [candidate],
            );
          }
        }
      }
    }
    return null;
  }

  _AdvancedEvent? _nextStrongLinkDeduction() {
    for (final family in ConstraintFamily.values) {
      for (final constraint in board.unresolvedConstraints(family)) {
        if (constraint.candidates.length != 2) continue;
        _deadline?.check();
        final link = StrongLink(
          constraint.kind,
          constraint.candidates[0],
          constraint.candidates[1],
        );
        for (final candidate in board.sortedCandidates) {
          if (candidate != link.first &&
              candidate != link.second &&
              board.conflicts(candidate, link.first) &&
              board.conflicts(candidate, link.second)) {
            return _AdvancedEvent(StrongLinkReason(link), [candidate]);
          }
        }
      }
    }
    return null;
  }

  /// Two constraints must each take a cat. A candidate is ruled out when
  /// every compatible pair of their candidates (one cell may serve both)
  /// conflicts with it.
  _AdvancedEvent? _nextPairedAttackDeduction() {
    final constraints = [
      for (final family in ConstraintFamily.values)
        for (final c in board.unresolvedConstraints(family))
          if (c.candidates.length <= _maxPairedCandidates) c,
    ];
    final candidates = board.sortedCandidates;
    for (var i = 0; i < constraints.length; i++) {
      for (var j = i + 1; j < constraints.length; j++) {
        final first = constraints[i];
        final second = constraints[j];
        final placements = [
          for (final p in first.candidates)
            for (final q in second.candidates)
              if (p == q || !board.conflicts(p, q)) (p, q),
        ];
        if (placements.isEmpty) continue;
        final affected = [
          for (final x in candidates)
            if (placements.every(
              (pair) =>
                  board.conflicts(x, pair.$1) || board.conflicts(x, pair.$2),
            ))
              x,
        ];
        if (affected.isNotEmpty) {
          return _AdvancedEvent(
            PairedAttackReason(
              first.kind,
              second.kind,
              [
                ...{...first.candidates, ...second.candidates},
              ]..sort(),
            ),
            affected,
          );
        }
      }
    }
    return null;
  }

  /// If `size` source constraints have candidates confined to `size + 1`
  /// target constraints, the targets' one remaining cat must come from the
  /// targets' other candidates, so whatever conflicts with all of them is
  /// ruled out. A lone leftover never gets here: the targets would then be
  /// a locked set of `size + 1`, which clears its constraint down to a
  /// single candidate first.
  LogicalHint? _leftoverHint() {
    for (var size = 1; size <= _maxLeftoverSources; size++) {
      for (final (source, target) in _lockedSetFamilyPairs) {
        final hint = _firstCombination(
          _targetMasks(source, target),
          size,
          size + 1,
          (combo) => _leftoverHintFor(combo, source, target),
        );
        if (hint != null) return hint;
      }
    }
    return null;
  }

  LogicalHint? _leftoverHintFor(
    List<_Constraint> combo,
    ConstraintFamily source,
    ConstraintFamily target,
  ) {
    final targets = {
      for (final c in combo)
        for (final p in c.candidates) board.constraintKind(p, target),
    };
    if (targets.any(board.hasCat)) return null;
    final sourceKinds = {for (final c in combo) c.kind};
    final sortedTargets = targets.toList()..sort();
    final leftovers = [
      for (final kind in sortedTargets)
        for (final p in board.candidates(kind))
          if (!sourceKinds.contains(board.constraintKind(p, source))) p,
    ]..sort();
    if (leftovers.length < 2) return null;

    final actions = [
      for (final x in board.sortedCandidates)
        if (!leftovers.contains(x) &&
            leftovers.every((l) => board.conflicts(x, l)))
          LogicalAction.exclude(x),
    ];
    if (actions.isEmpty) return null;
    return LogicalHint(
      actions,
      LeftoverReason(sourceKinds.toList()..sort(), sortedTargets, leftovers),
    );
  }

  /// For a constraint with two candidates, follows each through the
  /// deterministic techniques. A cat both branches place, or else the
  /// cells both branches exclude, hold whichever one is true.
  LogicalHint? _branchConsensusHint() {
    for (final family in ConstraintFamily.values) {
      for (final constraint in board.unresolvedConstraints(family)) {
        if (constraint.candidates.length != 2) continue;
        final link = StrongLink(
          constraint.kind,
          constraint.candidates[0],
          constraint.candidates[1],
        );
        final first = _closureAssuming(link.first);
        if (first == null) continue;
        final second = _closureAssuming(link.second);
        if (second == null) continue;

        final reason = BranchConsensusReason(link);
        final candidates = board.sortedCandidates;
        for (final p in candidates) {
          if (first.isCat(p) && second.isCat(p)) {
            return LogicalHint([LogicalAction.placeCat(p)], reason);
          }
        }
        final actions = [
          for (final p in candidates)
            if (first.isExcluded(p) && second.isExcluded(p))
              LogicalAction.exclude(p),
        ];
        if (actions.isNotEmpty) return LogicalHint(actions, reason);
      }
    }
    return null;
  }

  /// The board after assuming a cat at `position` and applying every
  /// deterministic technique, or null if that breaks the board (the depth-1
  /// trial explains those cases).
  _CandidateBoard? _closureAssuming(CellPosition position) {
    final branch = _SolveEngine._branch(this).._forceAssumedCat(position);
    final outcome = branch._resolve(0, 0);
    return outcome == _Outcome.contradiction ? null : branch.board;
  }

  /// The first constraint with no cat and no candidate left, if any.
  ConstraintKind? get starvedConstraint {
    for (final family in ConstraintFamily.values) {
      for (final kind in board.allConstraintKinds(family)) {
        if (!board.hasCat(kind) && board.candidates(kind).isEmpty) return kind;
      }
    }
    return null;
  }

  (CellPosition, CellPosition)? get clashingCats {
    final cats = board.sortedConfirmedCats;
    for (var i = 0; i < cats.length; i++) {
      for (var j = i + 1; j < cats.length; j++) {
        final a = cats[i];
        final b = cats[j];
        if (a.row == b.row ||
            a.column == b.column ||
            level.regionAt(a) == level.regionAt(b) ||
            a.isAdjacentTo(b)) {
          return (a, b);
        }
      }
    }
    return null;
  }

  bool get _hasContradiction {
    if (board.confirmedCatCount > level.catCount) return true;
    return clashingCats != null || starvedConstraint != null;
  }

  bool get _isSolved {
    if (board.confirmedCatCount != level.catCount) return false;
    for (final family in ConstraintFamily.values) {
      for (final kind in board.allConstraintKinds(family)) {
        if (!board.hasCat(kind)) return false;
      }
    }
    return !_hasContradiction;
  }
}
