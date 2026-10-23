// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_designer/references.dart';

void main() {
  final level =
      (jsonDecode(File('test/fixtures/theme.json').readAsStringSync())
              as Map)['level']
          as Map;
  final boards = ReferenceBoard.parse(
    jsonEncode([
      {
        'id': 'authored-number-one',
        'size': level['size'],
        'regionIDs': level['regionIDs'],
        'solution': [for (final p in level['solution'] as List) (p as List)[1]],
        'themes': ['symmetric'],
      },
    ]),
  );

  test('every reference board is square, themed and solved', () {
    expect(boards, isNotEmpty);
    for (final b in boards) {
      expect(b.regionIDs, hasLength(b.size), reason: b.id);
      expect(b.regionIDs.every((row) => row.length == b.size), isTrue);
      expect(b.solution, hasLength(b.size), reason: b.id);
      expect(b.themes, isNotEmpty, reason: b.id);
      expect(b.themes.every(themeNames.containsKey), isTrue, reason: b.id);
    }
  });

  testWidgets('theme chips filter the grid', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ReferencePage(boards: boards)));
    expect(find.text('${boards.length} / ${boards.length}'), findsOneWidget);

    await tester.tap(find.text('近似对称'));
    await tester.pump();
    final symmetric = boards.where((b) => b.themes.contains('symmetric'));
    expect(find.text('${symmetric.length} / ${boards.length}'), findsOneWidget);
  });
}
