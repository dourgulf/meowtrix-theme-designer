// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'generator.dart';
import 'trace.dart';

/// Searches for a board whose hint trace uses exactly the target advanced
/// techniques, needs no depth-1 assumption and reads well:
///
/// - each technique at most 3 times (hard ones and `pairedAttack` less,
///   see [defaultCaps]); `cap=pairedAttack:1,...` overrides;
/// - `total=a-b`: advanced hints in total within [a, b];
/// - at most one single-cell Region;
/// - no Region's candidates scattered into more than 3 far-apart pieces
///   while solving ([maxCandidateFragments]);
/// - Regions no larger than a quarter of the board (the generator's cap).
///
/// `rules=2` (levels 21–100) adds, after studying LinkedIn Queens:
///
/// - no single-cell Region and at most one 2-cell Region, so the opening
///   is not a free cat;
/// - the first hint is not "only one cell left";
/// - the solve order does not simply follow Region size
///   ([regionOrderCorrelation] ≤ 0.3).
///
/// Without `rules=2` the search is exactly the one that made levels 11–20.
///
/// Usage: `design.dart size seed technique,... budget [total=a-b]
/// [cap=t:n,...] [superset] [rules=2] [kinds=3]`
void main(List<String> args) {
  final size = int.parse(args[0]);
  final seed = int.parse(args[1]);
  final target = args[2].split(',').toSet();
  final budget = args.length > 3 ? int.parse(args[3]) : 4000;
  var total = (1, 99);
  final caps = Map.of(defaultCaps);
  var superset = false;
  var rules = 1;
  int? maxAdvancedKinds;
  for (final option in args.skip(4)) {
    if (option == 'superset') superset = true;
    if (option == 'rules=2') rules = 2;
    if (option.startsWith('kinds=')) {
      maxAdvancedKinds = int.parse(option.substring(6));
    }
    if (option.startsWith('total=')) {
      final [lo, hi] = option.substring(6).split('-').map(int.parse).toList();
      total = (lo, hi);
    }
    if (option.startsWith('cap=')) {
      for (final pair in option.substring(4).split(',')) {
        final [t, n] = pair.split(':');
        caps[t] = int.parse(n);
      }
    }
  }
  final goal = Goal(
    target,
    total,
    caps,
    superset: superset,
    rules: rules,
    maxAdvancedKinds: maxAdvancedKinds,
  );
  print(
    jsonEncode(
      design(
        size,
        seed,
        goal,
        budget,
        onProgress: (steps, best) {
          if (steps % 5000 == 0) {
            stderr.writeln('seed $seed: $steps/$budget steps, best $best');
          }
        },
      ),
    ),
  );
}

const defaultCaps = {
  'lockedPair': 3,
  'strongLink': 3,
  'commonAttack': 3,
  'pairedAttack': 2,
  'lockedQuad': 1,
  'leftover': 1,
  'branch': 1,
};

/// Rules 2: Region order vs. size correlation allowed.
const maxOrderCorrelation = 0.3;

class Goal {
  Goal(
    this.target,
    this.total,
    this.caps, {
    this.superset = false,
    this.rules = 1,
    this.maxAdvancedKinds,
  });
  final Set<String> target;
  final (int, int) total;
  final Map<String, int> caps;

  /// Accept boards that use other advanced techniques too.
  final bool superset;

  /// Rule set: 1 = levels 11–20, 2 = levels 21–100 (see [main]).
  final int rules;

  /// Optional bound for flexible peak searches; null preserves historic seeds.
  final int? maxAdvancedKinds;
}

/// Hill-climbs from random boards until one meets [goal], or null after
/// [budget] steps. [generator] builds the board generator from the seeded
/// RNG (default: a plain [BoardGenerator]); [onProgress] gets every 500th
/// step with the best counts so far, and [cancelled] stops the search.
Map<String, Object?>? design(
  int size,
  int seed,
  Goal goal,
  int budget, {
  BoardGenerator Function(Random rng)? generator,
  void Function(int steps, Map<String, int>? best)? onProgress,
  bool Function()? cancelled,
}) {
  final rng = Random(seed);
  final gen =
      generator?.call(rng) ??
      BoardGenerator(size, rng, minRegionSize: goal.rules == 2 ? 3 : 1);
  var restarts = 0;
  var steps = 0;
  Map<String, Object?> found(
    List<List<int>> regions,
    List<int> solution,
    _Eval eval,
  ) => {
    'size': size,
    'seed': seed,
    'steps': steps,
    'restarts': restarts,
    'rules': goal.rules,
    'counts': eval.counts,
    'fragments': eval.fragments,
    if (goal.rules == 2) 'orderCorrelation': eval.orderCorrelation,
    'regionIDs': regions,
    'solution': [
      for (var r = 0; r < size; r++) [r, solution[r]],
    ],
  };
  while (steps < budget) {
    restarts++;
    final start = gen.generate('design');
    var regions = start.regionIDs;
    final solution = [for (final p in start.solution) p.column];
    var eval = _evaluate(gen, regions, solution, goal);
    // A custom generator (themed boards) may already start on a keeper.
    // The plain search keeps its original path so levels 11–100 reproduce.
    if (generator != null && eval.accepted) {
      return found(regions, solution, eval);
    }
    // Hill climb with sideways moves; restart when stale.
    var stale = 0;
    while (stale < 300 && steps < budget) {
      steps++;
      if (steps % 500 == 0) {
        onProgress?.call(steps, eval.counts);
        if (cancelled?.call() ?? false) return null;
      }
      final next = gen.mutate(regions, solution);
      if (next == null) {
        // On a themed board most moves hit painted cells; count them, or a
        // stuck start would never restart.
        if (generator != null) stale++;
        continue;
      }
      final e = _evaluate(gen, next, solution, goal);
      if (e.score >= eval.score) {
        if (e.score > eval.score) stale = 0;
        regions = next;
        eval = e;
      } else {
        stale++;
      }
      if (eval.accepted) return found(regions, solution, eval);
    }
  }
  return null;
}

Set<String> advancedIn(Map<String, int> counts) => {
  for (final t in advancedTechniques)
    if (counts.containsKey(t)) t,
};

class _Eval {
  _Eval(
    this.score,
    this.counts, {
    this.fragments,
    this.orderCorrelation,
    this.accepted = false,
  });
  final double score;
  final Map<String, int>? counts;
  final int? fragments;
  final double? orderCorrelation;
  final bool accepted;
}

_Eval _evaluate(
  BoardGenerator gen,
  List<List<int>> regions,
  List<int> solution,
  Goal goal,
) {
  final level = gen.levelOf('design', regions, solution);
  final steps = traceSteps(level);
  if (steps == null) return _Eval(-1e9, null);
  final counts = <String, int>{};
  for (final (t, _) in steps) {
    counts[t] = (counts[t] ?? 0) + 1;
  }
  final present = advancedIn(counts);
  final assumptions = counts['assumption'] ?? 0;
  if (!present.containsAll(goal.target)) {
    // Phase 1: reward any advanced reasoning so rare techniques can surface.
    var s = 20.0 * present.intersection(goal.target).length;
    for (final t in advancedTechniques) {
      s += min(counts[t] ?? 0, 4) * (goal.target.contains(t) ? 2 : 1);
    }
    return _Eval(s - 3.0 * assumptions, counts);
  }
  // Phase 2: keep every target, strip everything else, meet the limits.
  var s = 1000.0;
  var violations = 0;
  if (goal.maxAdvancedKinds != null &&
      present.length > goal.maxAdvancedKinds!) {
    s -= 12.0 * (present.length - goal.maxAdvancedKinds!);
    violations++;
  }
  final extras = goal.superset ? <String>{} : present.difference(goal.target);
  for (final t in extras) {
    s -= 10 + min(counts[t]!, 4);
    violations++;
  }
  for (final t in present) {
    final over = counts[t]! - (goal.caps[t] ?? 3);
    if (over > 0) {
      s -= 4.0 * over;
      violations++;
    }
  }
  final hints = [for (final t in present) counts[t]!].fold(0, (a, b) => a + b);
  final (lo, hi) = goal.total;
  if (hints < lo || hints > hi) {
    s -= 3.0 * (hints < lo ? lo - hints : hints - hi);
    violations++;
  }
  if (goal.rules == 1) {
    final singles = _smallRegions(regions, 1);
    if (singles > 1) {
      s -= 6.0 * (singles - 1);
      violations++;
    }
  } else {
    final singles = _smallRegions(regions, 1);
    final pairs = _smallRegions(regions, 2);
    final excess = singles + max(0, pairs - 1);
    if (excess > 0) {
      s -= 6.0 * excess;
      violations++;
    }
    if (steps.first.$1 == 'only') {
      s -= 8;
      violations++;
    }
  }
  s -= 15.0 * assumptions;
  if (assumptions > 0) violations++;
  // Scattering needs a second pass, so only near-final boards pay for it.
  int? fragments;
  double? correlation;
  if (violations == 0) {
    fragments = maxCandidateFragments(level);
    if (fragments > 3) {
      s -= 5.0 * (fragments - 3);
      violations++;
    }
  }
  if (violations == 0 && goal.rules == 2) {
    correlation = regionOrderCorrelation(level);
    if (correlation > maxOrderCorrelation) {
      s -= 2 + 10 * (correlation - maxOrderCorrelation);
      violations++;
    }
  }
  return _Eval(
    s,
    counts,
    fragments: fragments,
    orderCorrelation: correlation,
    accepted: violations == 0,
  );
}

/// Regions of exactly [cells] cells.
int _smallRegions(List<List<int>> regions, int cells) {
  final sizes = <int, int>{};
  for (final row in regions) {
    for (final id in row) {
      sizes[id] = (sizes[id] ?? 0) + 1;
    }
  }
  return sizes.values.where((n) => n == cells).length;
}
