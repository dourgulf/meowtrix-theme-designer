// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
// Author: lidawen
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:theme_designer/storage.dart';

void main() {
  test(
    'finds shared drafts from a nested workspace directory and writes there',
    () {
      final temp = Directory.systemTemp.createTempSync('theme-workspace-');
      addTearDown(() => temp.deleteSync(recursive: true));
      File('${temp.path}/shared/app.json').createSync(recursive: true);
      Directory('${temp.path}/shared/level-design/designs')
          .createSync(recursive: true);
      final nested = Directory('${temp.path}/tool/theme_designer/build/nested')
        ..createSync(recursive: true);
      final store = DesignStore.locate(start: nested);
      expect(store.directory.path, '${temp.path}/shared/level-design/designs');
      final file = store.save('heart', {
        'size': 6,
        'options': {
          'caps': {'branch': 0},
        },
      });
      expect(store.load(file)['options'], {
        'caps': {'branch': 0},
      });
      expect(store.list().map((f) => f.path), contains(file.path));
    },
  );
  test('saves standalone drafts without a parent repository and rejects directory traversal', () {
    final temp = Directory.systemTemp.createTempSync('theme-standalone-');
    addTearDown(() => temp.deleteSync(recursive: true));
    // Use an explicit standalone directory so executable/cwd auto-detection is irrelevant.
    final store = DesignStore(Directory('${temp.path}/designs'));
    expect(store.load(store.save('爱心', {'size': 9}))['size'], 9);
    for (final name in ['../escape', r'..\escape', '']) {
      expect(() => store.save(name, {}), throwsArgumentError);
    }
  });
}
