// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
// Author: lidawen
import 'dart:convert';
import 'dart:io';

/// Repository-authored drafts are shared with the active Cocos content tools.
class DesignStore {
  DesignStore(this.directory);

  final Directory directory;

  /// Optional connection to another Meowtrix checkout; never a package dependency.
  static Directory? workspaceRoot({Directory? start}) {
    final configured = Platform.environment['MEOWTRIX_WORKSPACE'];
    if (configured != null && configured.isNotEmpty) {
      final root = Directory(configured).absolute;
      if (!Directory('${root.path}/shared/level-design').existsSync()) {
        throw StateError('MEOWTRIX_WORKSPACE 中没有 shared/level-design');
      }
      return root;
    }
    for (final origin in [
      ?start,
      File(Platform.resolvedExecutable).parent,
      Directory.current,
    ]) {
      var dir = origin.absolute;
      while (true) {
        if (File('${dir.path}/shared/app.json').existsSync() &&
            Directory('${dir.path}/shared/level-design').existsSync()) {
          return dir;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  static DesignStore locate({Directory? start}) {
    final override = Platform.environment['MEOWTRIX_DESIGNS_DIR'];
    if (override != null && override.isNotEmpty) {
      return DesignStore(Directory(override));
    }
    final workspace = workspaceRoot(start: start);
    if (workspace != null) {
      return DesignStore(
        Directory('${workspace.path}/shared/level-design/designs'),
      );
    }
    // Outside Meowtrix, drafts belong to the standalone project's working directory.
    return DesignStore(
      Directory('${(start ?? Directory.current).absolute.path}/designs'),
    );
  }

  List<File> list() {
    if (!directory.existsSync()) return [];
    return directory
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  File save(String name, Map<String, Object?> data) {
    if (name.trim().isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains(RegExp(r'[/\\\x00-\x1f]'))) {
      throw ArgumentError.value(name, 'name', '需要不含路径分隔符的文件名');
    }
    directory.createSync(recursive: true);
    final file = File('${directory.path}/$name.json');
    file.writeAsStringSync('${encode(data)}\n');
    return file;
  }

  /// Indented JSON with arrays of plain values on one line, so a board
  /// reads as a grid.
  static String encode(Object? data) => const JsonEncoder.withIndent('  ')
      .convert(data)
      .replaceAllMapped(
        RegExp(r'\[([^\[\]{}]*)\]'),
        (m) => '[${m[1]!.trim().split(RegExp(r',\s*')).join(', ')}]',
      );

  Map<String, Object?> load(File file) =>
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
}
