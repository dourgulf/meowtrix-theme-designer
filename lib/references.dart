// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import 'storage.dart';

import 'board_canvas.dart';

/// Window argument that marks the pattern reference window.
const referenceWindow = 'references';

/// Brings the reference window to the front, creating it on first use.
Future<void> showReferenceWindow() async {
  for (final window in await WindowController.getAll()) {
    if (window.arguments == referenceWindow) return window.show();
  }
  final window = await WindowController.create(
    const WindowConfiguration(arguments: referenceWindow, hiddenAtLaunch: true),
  );
  await window.show();
}

/// A LinkedIn Queens board with a composition theme, picked by
/// tool/extract_references.py.
class ReferenceBoard {
  ReferenceBoard.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      date = json['date'] as String?,
      size = json['size'] as int,
      themes = [for (final t in json['themes'] as List) t as String],
      regionIDs = [
        for (final row in json['regionIDs'] as List)
          [for (final id in row as List) id as int],
      ],
      solution = [for (final c in json['solution'] as List) c as int];

  final String id;
  final String? date;
  final int size;
  final List<String> themes;
  final List<List<int>> regionIDs;
  final List<int> solution;

  static List<ReferenceBoard> parse(String source) => [
    for (final raw in jsonDecode(source) as List)
      ReferenceBoard.fromJson(raw as Map<String, dynamic>),
  ];
}

/// Reference research stays external so this project can be distributed independently.
Future<List<ReferenceBoard>> loadReferenceBoards({File? source}) async {
  final configured = Platform.environment['THEME_DESIGNER_REFERENCES'];
  final workspace = DesignStore.workspaceRoot();
  final file =
      source ??
      (configured != null && configured.isNotEmpty
          ? File(configured)
          : workspace == null
          ? null
          : File('${workspace.path}/shared/level-design/linkedin_themes.json'));
  if (file == null) return [];
  return ReferenceBoard.parse(await file.readAsString());
}

const themeNames = {'symmetric': '近似对称', 'repeated': '重复形状', 'backdrop': '大底色'};

class ReferenceApp extends StatelessWidget {
  const ReferenceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LinkedIn 图案参考',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF38AA70),
        scaffoldBackgroundColor: const Color(0xFFF7F4EE),
      ),
      home: FutureBuilder(
        future: loadReferenceBoards(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(child: Text('读取参考数据失败：${snapshot.error}')),
            );
          }
          final boards = snapshot.data;
          if (boards == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (boards.isEmpty) {
            return const Scaffold(
              body: Center(
                child: Text(
                  '未配置外部参考数据，可设置 MEOWTRIX_WORKSPACE 或 THEME_DESIGNER_REFERENCES',
                ),
              ),
            );
          }
          return ReferencePage(boards: boards);
        },
      ),
    );
  }
}

/// Grid of reference boards, filtered by theme and size; clicking one
/// shows it large.
class ReferencePage extends StatefulWidget {
  const ReferencePage({super.key, required this.boards});

  final List<ReferenceBoard> boards;

  @override
  State<ReferencePage> createState() => _ReferencePageState();
}

class _ReferencePageState extends State<ReferencePage> {
  final _themes = <String>{};
  final _sizes = <int>{};
  bool _showCats = false;
  ReferenceBoard? _selected;

  late final _allSizes = {for (final b in widget.boards) b.size}.toList()
    ..sort();

  List<ReferenceBoard> get _visible => [
    for (final b in widget.boards)
      if (_themes.every(b.themes.contains) &&
          (_sizes.isEmpty || _sizes.contains(b.size)))
        b,
  ];

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final selected = _selected;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final MapEntry(key: t, value: name) in themeNames.entries)
                  FilterChip(
                    label: Text(name),
                    selected: _themes.contains(t),
                    onSelected: (on) =>
                        setState(() => on ? _themes.add(t) : _themes.remove(t)),
                  ),
                const SizedBox(width: 12),
                for (final n in _allSizes)
                  FilterChip(
                    label: Text('$n×$n'),
                    selected: _sizes.contains(n),
                    onSelected: (on) =>
                        setState(() => on ? _sizes.add(n) : _sizes.remove(n)),
                  ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('显示猫'),
                  selected: _showCats,
                  onSelected: (on) => setState(() => _showCats = on),
                ),
                const SizedBox(width: 12),
                Text('${visible.length} / ${widget.boards.length}'),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GridView.extent(
                    padding: const EdgeInsets.all(20),
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.82,
                    children: [
                      for (final b in visible)
                        _Thumbnail(
                          board: b,
                          selected: b == selected,
                          showCats: _showCats,
                          onTap: () => setState(() => _selected = b),
                        ),
                    ],
                  ),
                ),
                if (selected != null)
                  SizedBox(
                    width: 420,
                    child: _Detail(board: selected, showCats: _showCats),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.board,
    required this.selected,
    required this.showCats,
    required this.onTap,
  });

  final ReferenceBoard board;
  final bool selected;
  final bool showCats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('reference-${board.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Expanded(child: _board(board, showCats)),
            const SizedBox(height: 4),
            Text(
              board.id.replaceFirst('linkedin-', '#'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.board, required this.showCats});

  final ReferenceBoard board;
  final bool showCats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(board.id, style: text.titleMedium),
          Text(
            [
              '${board.size}×${board.size}',
              ?board.date,
              for (final t in board.themes) themeNames[t] ?? t,
            ].join(' · '),
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          AspectRatio(aspectRatio: 1, child: _board(board, showCats)),
        ],
      ),
    );
  }
}

Widget _board(ReferenceBoard board, bool showCats) => BoardCanvas(
  cells: board.regionIDs,
  solution: showCats ? board.solution : null,
);
