// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
// Author: lidawen
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theme_designer/main.dart';
import 'package:theme_designer/storage.dart';

void main() {
  testWidgets(
    'opens a draft, generates a unique board, saves and reopens it with caps intact',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('theme-ui-flow-');
      addTearDown(() => temp.deleteSync(recursive: true));
      tester.view.physicalSize = const Size(1600, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final raw = jsonDecode(
        File('test/fixtures/theme.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final level = raw['level'] as Map;
      final store = DesignStore(temp);
      store.save('existing-pattern', {
        'size': level['size'],
        'theme': level['regionIDs'],
        'options': {
          'targets': <String>[],
          'superset': true,
          'total': [0, 10],
          'rules': 1,
          'grows': false,
          'caps': {'branch': 0},
        },
      });
      await tester.pumpWidget(MaterialApp(home: DesignerPage(store: store)));
      await tester.tap(find.text('打开草稿…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('existing-pattern.json'));
      await tester.pumpAndSettle();
      expect(find.text('高级提示总次数：0–10'), findsOneWidget);
      await tester.ensureVisible(find.text('生成'));
      await tester.tap(find.text('生成'));
      for (
        var i = 0;
        i < 50 && find.textContaining('找到了').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.textContaining('找到了'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'saved-pattern');
      await tester.ensureVisible(find.text('保存'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final saved = store.load(File('${temp.path}/saved-pattern.json'));
      expect((saved['options'] as Map)['caps'], {'branch': 0});
      expect((saved['level'] as Map)['regionIDs'], level['regionIDs']);
      expect((saved['level'] as Map)['solution'], level['solution']);
      await tester.tap(find.text('打开草稿…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('saved-pattern.json'));
      await tester.pumpAndSettle();
      expect(find.text('复制关卡 JSON'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
