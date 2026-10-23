// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'package:equatable/equatable.dart';

import 'board.dart';

enum ConstraintFamily { row, column, region }

/// One of the puzzle's "exactly one cat" constraints.
class ConstraintKind extends Equatable implements Comparable<ConstraintKind> {
  const ConstraintKind(this.family, this.index);
  const ConstraintKind.row(int row) : this(ConstraintFamily.row, row);
  const ConstraintKind.column(int column)
    : this(ConstraintFamily.column, column);
  const ConstraintKind.region(int regionID)
    : this(ConstraintFamily.region, regionID);

  final ConstraintFamily family;

  /// Row, column or Region ID, depending on [family].
  final int index;

  @override
  int compareTo(ConstraintKind other) => family == other.family
      ? index - other.index
      : family.index - other.family.index;

  /// Every cell of this row, column or Region on [level]'s board.
  Iterable<CellPosition> cellsIn(LevelDefinition level) sync* {
    for (var row = 0; row < level.size; row++) {
      for (var column = 0; column < level.size; column++) {
        final position = CellPosition(row, column);
        final member = switch (family) {
          ConstraintFamily.row => row == index,
          ConstraintFamily.column => column == index,
          ConstraintFamily.region => level.regionAt(position) == index,
        };
        if (member) yield position;
      }
    }
  }

  @override
  List<Object?> get props => [family, index];
}

/// Exactly one of `first`/`second` must be a cat because they are the only
/// two remaining candidates for `constraint`.
class StrongLink extends Equatable {
  const StrongLink(this.constraint, this.first, this.second);
  final ConstraintKind constraint;
  final CellPosition first;
  final CellPosition second;

  @override
  List<Object?> get props => [constraint, first, second];
}

class LogicalAction extends Equatable {
  const LogicalAction.placeCat(this.position) : state = CellState.cat;
  const LogicalAction.exclude(this.position) : state = CellState.excluded;

  /// Takes a mistaken mark off; only [MistakenExclusionReason] uses it.
  const LogicalAction.clear(this.position) : state = CellState.empty;

  final CellPosition position;

  /// What the cell becomes when the hint is applied.
  final CellState state;

  bool get placesCat => state == CellState.cat;

  @override
  List<Object?> get props => [position, state];
}

/// Why a hint's actions follow. Structured rather than pre-rendered so the
/// UI can phrase it in the current language and Region-icon setting.
sealed class LogicalReason extends Equatable {
  const LogicalReason();
}

class OnlyCandidateReason extends LogicalReason {
  const OnlyCandidateReason(this.constraint);
  final ConstraintKind constraint;
  @override
  List<Object?> get props => [constraint];
}

class AlreadyHasCatReason extends LogicalReason {
  const AlreadyHasCatReason(this.constraint);
  final ConstraintKind constraint;
  @override
  List<Object?> get props => [constraint];
}

class AdjacentToCatReason extends LogicalReason {
  const AdjacentToCatReason(this.cat);
  final CellPosition cat;
  @override
  List<Object?> get props => [cat];
}

/// Assuming a cat at `assumed` broke the board. `contradicting` names the
/// constraint that ran out of candidates, or is null when two cats clashed.
class ContradictionFromAssumptionReason extends LogicalReason {
  const ContradictionFromAssumptionReason(this.assumed, this.contradicting);
  final CellPosition assumed;
  final ConstraintKind? contradicting;
  @override
  List<Object?> get props => [assumed, contradicting];
}

/// A Hall set: the candidates of `sources` fall entirely within `targets`.
class LockedSetReason extends LogicalReason {
  const LockedSetReason(this.sources, this.targets);
  final List<ConstraintKind> sources;
  final List<ConstraintKind> targets;
  @override
  List<Object?> get props => [sources, targets];
}

class CommonAttackReason extends LogicalReason {
  const CommonAttackReason(this.constraint, this.candidatePositions);
  final ConstraintKind constraint;
  final List<CellPosition> candidatePositions;
  @override
  List<Object?> get props => [constraint, candidatePositions];
}

class StrongLinkReason extends LogicalReason {
  const StrongLinkReason(this.link);
  final StrongLink link;
  @override
  List<Object?> get props => [link];
}

/// Sandwich: `first` and `second` each need a cat, and every way to place
/// both of them together conflicts with the excluded cells.
class PairedAttackReason extends LogicalReason {
  const PairedAttackReason(this.first, this.second, this.candidatePositions);
  final ConstraintKind first;
  final ConstraintKind second;

  /// Where the two cats may go: both constraints' candidates.
  final List<CellPosition> candidatePositions;
  @override
  List<Object?> get props => [first, second, candidatePositions];
}

/// An almost locked set: the candidates of `sources` fall within one more
/// `targets` than there are sources, so exactly one of the targets' cats is
/// left over, and it must be one of `leftovers`.
class LeftoverReason extends LogicalReason {
  const LeftoverReason(this.sources, this.targets, this.leftovers);
  final List<ConstraintKind> sources;
  final List<ConstraintKind> targets;
  final List<CellPosition> leftovers;
  @override
  List<Object?> get props => [sources, targets, leftovers];
}

/// Exactly one of `link`'s two cells is a cat, and following either choice
/// through the deterministic techniques reaches the same result.
class BranchConsensusReason extends LogicalReason {
  const BranchConsensusReason(this.link);
  final StrongLink link;
  @override
  List<Object?> get props => [link];
}

/// The player crossed out cells the solution needs. Found from the level's
/// solution before any deduction, so the hint engine itself never sees it.
class MistakenExclusionReason extends LogicalReason {
  const MistakenExclusionReason();
  @override
  List<Object?> get props => [];
}

class LogicalHint extends Equatable {
  const LogicalHint(this.actions, this.reason);
  final List<LogicalAction> actions;
  final LogicalReason reason;

  List<CellPosition> get positions => [for (final a in actions) a.position];

  /// The cells the reason says may still hold a cat, which the board marks
  /// as possible cats while the hint is shown. Reasons that name a whole
  /// constraint count its empty cells on [puzzle].
  Set<CellPosition> possibleCats(LevelDefinition level, Puzzle puzzle) {
    Iterable<CellPosition> empty(Iterable<ConstraintKind> kinds) => kinds
        .expand((kind) => kind.cellsIn(level))
        .where((p) => puzzle.stateAt(p) == CellState.empty);
    return switch (reason) {
      StrongLinkReason(:final link) ||
      BranchConsensusReason(:final link) => {link.first, link.second},
      CommonAttackReason(:final candidatePositions) ||
      PairedAttackReason(
        :final candidatePositions,
      ) => candidatePositions.toSet(),
      LockedSetReason(:final sources) => empty(sources).toSet(),
      LeftoverReason(:final leftovers) => leftovers.toSet(),
      _ => const {},
    };
  }

  /// A leftover first shows only where its last cat may go; its details show
  /// how the sources fill the targets.
  bool get hasDetails => reason is LeftoverReason;

  /// The cells a player looks at to follow this hint: the action cells, the
  /// [possibleCats] and the other cells the reasoning rests on. Only a sole
  /// candidate lights its whole constraint, whose other cells are the
  /// evidence. With [details] a leftover also lights its sources' empty
  /// cells.
  Set<CellPosition> spotlight(
    LevelDefinition level,
    Puzzle puzzle, {
    bool details = false,
  }) {
    Iterable<CellPosition> cats(ConstraintKind kind) =>
        kind.cellsIn(level).where((p) => puzzle.stateAt(p) == CellState.cat);
    Iterable<CellPosition> empty(ConstraintKind kind) =>
        kind.cellsIn(level).where((p) => puzzle.stateAt(p) == CellState.empty);
    return {
      ...positions,
      ...possibleCats(level, puzzle),
      ...switch (reason) {
        OnlyCandidateReason(:final constraint) => constraint.cellsIn(level),
        AlreadyHasCatReason(:final constraint) => cats(constraint),
        AdjacentToCatReason(:final cat) => [cat],
        LeftoverReason(:final sources) when details => sources.expand(empty),
        ContradictionFromAssumptionReason(
          :final assumed,
          :final contradicting,
        ) =>
          [assumed, ...?contradicting == null ? null : empty(contradicting)],
        _ => const <CellPosition>[],
      },
    };
  }

  @override
  List<Object?> get props => [actions, reason];
}

/// Why a board can no longer be finished.
sealed class HintDiagnosis extends Equatable {
  const HintDiagnosis();
}

class StarvedConstraintDiagnosis extends HintDiagnosis {
  const StarvedConstraintDiagnosis(this.constraint);
  final ConstraintKind constraint;
  @override
  List<Object?> get props => [constraint];
}

class ClashingCatsDiagnosis extends HintDiagnosis {
  const ClashingCatsDiagnosis(this.first, this.second);
  final CellPosition first;
  final CellPosition second;
  @override
  List<Object?> get props => [first, second];
}

/// What the hint button can offer for the current board.
sealed class HintOutcome {
  const HintOutcome();
}

class HintAvailable extends HintOutcome {
  const HintAvailable(this.hint);
  final LogicalHint hint;
}

class HintContradiction extends HintOutcome {
  const HintContradiction(this.diagnosis);
  final HintDiagnosis diagnosis;
}

class HintUnavailable extends HintOutcome {
  const HintUnavailable();
}

/// The search ran past its time limit before finding a step.
class HintTimedOut extends HintOutcome {
  const HintTimedOut();
}
