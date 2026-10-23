// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'dart:async';
import 'dart:isolate';

import 'level_design/themed.dart';

export 'level_design/design.dart' show Goal, defaultCaps;
export 'level_design/themed.dart';

sealed class SearchEvent {}

class SearchProgress extends SearchEvent {
  SearchProgress(this.steps, this.best);
  final int steps;
  final Map<String, int>? best;
}

class SearchDone extends SearchEvent {
  SearchDone(this.result);

  /// Null when the step budget ran out.
  final ThemeResult? result;
}

class SearchFailed extends SearchEvent {
  SearchFailed(this.message);
  final String message;
}

/// Runs [generateThemed] in its own isolate so the window stays responsive
/// and [cancel] can stop it at once.
class ThemeSearch {
  ThemeSearch._(this._isolate, this._port, this.events);

  final Isolate _isolate;
  final ReceivePort _port;
  final Stream<SearchEvent> events;

  static Future<ThemeSearch> start(ThemeRequest request) async {
    final port = ReceivePort();
    final isolate = await Isolate.spawn(_run, (port.sendPort, request));
    final events = port.cast<SearchEvent>().asBroadcastStream();
    final search = ThemeSearch._(isolate, port, events);
    events.listen((e) {
      if (e is SearchDone || e is SearchFailed) search._close();
    });
    return search;
  }

  void cancel() {
    _isolate.kill(priority: Isolate.immediate);
    _close();
  }

  void _close() => _port.close();

  static void _run((SendPort, ThemeRequest) message) {
    final (send, request) = message;
    try {
      final result = generateThemed(
        request,
        onProgress: (steps, best) => send.send(
          SearchProgress(steps, best == null ? null : Map.of(best)),
        ),
      );
      send.send(SearchDone(result));
    } on StateError catch (e) {
      send.send(SearchFailed(e.message));
    }
  }
}
