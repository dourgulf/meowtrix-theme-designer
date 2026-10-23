// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'palette.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'board_canvas.dart';
import 'references.dart';
import 'search.dart';
import 'storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final window = await WindowController.fromCurrentEngine();
  runApp(
    window.arguments == referenceWindow
        ? const ReferenceApp()
        : const ThemeDesignerApp(),
  );
}

class ThemeDesignerApp extends StatelessWidget {
  const ThemeDesignerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CatPuzzle 主题关卡设计',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF38AA70),
        scaffoldBackgroundColor: const Color(0xFFF7F4EE),
      ),
      home: const DesignerPage(),
    );
  }
}

/// Advanced techniques in hint order, with their names in docs/HumanReasoning.md.
const _techniques = {
  'lockedPair': '锁定对/三元',
  'strongLink': '强链',
  'commonAttack': '共同攻击',
  'lockedQuad': '四元锁定',
  'pairedAttack': '邻接夹击',
  'leftover': '余数计数',
  'branch': '双分支',
};

const _basicNames = {
  'only': '只剩一格',
  'propagate': '排除',
  'locked1': '单对象锁定',
  'assumption': '假设',
};

enum Mirror {
  none('无'),
  horizontal('左右'),
  vertical('上下'),
  both('四向'),
  rotate('中心');

  const Mirror(this.label);
  final String label;

  Iterable<(int, int)> cells(int r, int c, int n) sync* {
    yield (r, c);
    if (this == horizontal || this == both) yield (r, n - 1 - c);
    if (this == vertical || this == both) yield (n - 1 - r, c);
    if (this == both || this == rotate) yield (n - 1 - r, n - 1 - c);
  }
}

class DesignerPage extends StatefulWidget {
  const DesignerPage({super.key, this.store});

  final DesignStore? store;

  @override
  State<DesignerPage> createState() => _DesignerPageState();
}

class _DesignerPageState extends State<DesignerPage> {
  late final _store = widget.store ?? DesignStore.locate();
  final _name = TextEditingController(text: 'theme-01');

  int _size = 8;
  late List<List<int?>> _theme = _blank(8);

  /// Selected colour, or null for the eraser.
  int? _brush = 0;
  Mirror _mirror = Mirror.none;

  final Set<String> _targets = {};
  bool _superset = true;
  RangeValues _total = const RangeValues(1, 4);
  bool _rules2 = false;
  bool _grows = false;
  int _budget = 30000;
  Map<String, Object?> _loadedOptions = {};

  ThemeSearch? _search;
  String? _status;
  ThemeResult? _result;
  int? _resultSeed;
  bool _showResult = true;
  bool _showCats = false;

  static List<List<int?>> _blank(int n) =>
      List.generate(n, (_) => List<int?>.filled(n, null));

  List<String> get _problems => themeProblems(_size, _theme, _grows);

  void _setSize(int n) {
    setState(() {
      _theme = [
        for (var r = 0; r < n; r++)
          [
            for (var c = 0; c < n; c++)
              r < _size && c < _size && (_theme[r][c] ?? n) < n
                  ? _theme[r][c]
                  : null,
          ],
      ];
      _size = n;
      if ((_brush ?? 0) >= n) _brush = 0;
      _clearResult();
    });
  }

  void _clearResult() {
    _result = null;
    _status = null;
  }

  void _paint(int r, int c, {required bool erase}) {
    final value = erase ? null : _brush;
    setState(() {
      for (final (mr, mc) in _mirror.cells(r, c, _size)) {
        _theme[mr][mc] = value;
      }
      _clearResult();
    });
  }

  Future<void> _generate() async {
    final seed = Random().nextInt(1 << 31);
    final request = ThemeRequest(
      size: _size,
      theme: [for (final row in _theme) List.of(row)],
      goal: Goal(
        Set.of(_targets),
        (_total.start.round(), _total.end.round()),
        {
          ...defaultCaps,
          ...?(_loadedOptions['caps'] as Map?)?.cast<String, int>(),
        },
        superset: _superset,
        rules: _rules2 ? 2 : 1,
      ),
      grows: _grows,
      budget: _budget,
      seed: seed,
    );
    final search = await ThemeSearch.start(request);
    setState(() {
      _search = search;
      _result = null;
      _status = '搜索中…';
    });
    await for (final event in search.events) {
      if (!mounted) return;
      setState(() {
        switch (event) {
          case SearchProgress(:final steps, :final best):
            _status = '搜索中… $steps / $_budget 步\n当前最好：${_describe(best)}';
          case SearchDone(:final result):
            _search = null;
            _result = result;
            _resultSeed = seed;
            _showResult = true;
            _status = result == null
                ? '$_budget 步内没找到符合设置的盘面。可以再试一次，或放宽技巧和次数'
                : '找到了（第 ${result.steps} 步，种子 $seed）';
          case SearchFailed(:final message):
            _search = null;
            _status = message == 'no board fits this theme'
                ? '生成不出唯一解的盘面。试试打开“涂色区域可扩展”，或减少涂色的限制'
                : message;
        }
      });
    }
  }

  void _stop() {
    _search?.cancel();
    setState(() {
      _search = null;
      _status = '已停止';
    });
  }

  String _describe(Map<String, int>? counts) {
    if (counts == null) return '—';
    final parts = [
      for (final MapEntry(key: t, value: n) in counts.entries)
        '${_techniques[t] ?? _basicNames[t] ?? t} ×$n',
    ];
    return parts.join('，');
  }

  Map<String, Object?> _levelJson() => levelJson(
    _name.text.trim().isEmpty ? 'theme' : _name.text.trim(),
    _result!,
  );

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: DesignStore.encode(_levelJson())),
    );
    _toast('已复制关卡 JSON');
  }

  void _save() {
    final name = _name.text.trim().isEmpty ? 'theme' : _name.text.trim();
    final result = _result;
    final file = _store.save(name, {
      'size': _size,
      'theme': _theme,
      'options': {
        ..._loadedOptions,
        'targets': _targets.toList(),
        'superset': _superset,
        'total': [_total.start.round(), _total.end.round()],
        'rules': _rules2 ? 2 : 1,
        'grows': _grows,
      },
      if (result != null) ...{
        'seed': _resultSeed,
        'counts': result.counts,
        'fragments': result.fragments,
        'orderCorrelation': result.orderCorrelation,
        'level': _levelJson(),
      },
    });
    _toast('已保存到 ${file.path}');
  }

  Future<void> _open() async {
    final files = _store.list();
    final file = await showDialog<File>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('打开草稿'),
        children: [
          if (files.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('还没有保存过草稿')),
          for (final f in files)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, f),
              child: Text(f.uri.pathSegments.last),
            ),
        ],
      ),
    );
    if (file == null) return;
    final data = _store.load(file);
    final size = data['size'] as int;
    setState(() {
      _size = size;
      _theme = [
        for (final row in data['theme'] as List)
          [for (final id in row as List) id as int?],
      ];
      final options = data['options'] as Map<String, Object?>? ?? {};
      _loadedOptions = Map.of(options);
      _targets
        ..clear()
        ..addAll((options['targets'] as List? ?? []).cast<String>());
      _superset = options['superset'] as bool? ?? true;
      final total = (options['total'] as List? ?? [1, 4]).cast<int>();
      _total = RangeValues(total[0].toDouble(), total[1].toDouble());
      _rules2 = options['rules'] == 2;
      _grows = options['grows'] as bool? ?? false;
      _name.text = file.uri.pathSegments.last.replaceAll('.json', '');
      _clearResult();
      final level = data['level'] as Map<String, Object?>?;
      if (level != null) {
        _result = ThemeResult(
          regionIDs: [
            for (final row in level['regionIDs'] as List)
              (row as List).cast<int>(),
          ],
          solution: [
            for (final p in level['solution'] as List) (p as List)[1] as int,
          ],
          counts: (data['counts'] as Map).cast<String, int>(),
          fragments: data['fragments'] as int?,
          orderCorrelation: (data['orderCorrelation'] as num?)?.toDouble(),
        );
        _resultSeed = data['seed'] as int?;
        _showResult = true;
      }
    });
  }

  /// Takes the generated board as the new drawing, to touch it up by hand.
  void _adopt() {
    setState(() {
      _theme = [
        for (final row in _result!.regionIDs) [for (final id in row) id],
      ];
      _clearResult();
      _status = '已把结果转为草稿；整盘涂满时，“生成”只检查唯一解和提示能否解出';
    });
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final showing = result != null && _showResult;
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: BoardCanvas(
                  cells: showing ? result.regionIDs : _theme,
                  themeMask: showing
                      ? [
                          for (final row in _theme)
                            [for (final id in row) id != null],
                        ]
                      : null,
                  solution: showing && _showCats ? result.solution : null,
                  hasBrushColour: (r, c) =>
                      _brush != null && _theme[r][c] == _brush,
                  onPaint: (r, c, {required erase}) {
                    if (_search != null) return;
                    if (showing) setState(() => _showResult = false);
                    _paint(r, c, erase: erase);
                  },
                ),
              ),
            ),
          ),
          SizedBox(
            width: 360,
            child: Material(
              color: Colors.white,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  ..._drawPanel(),
                  const Divider(height: 32),
                  ..._generatePanel(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _drawPanel() => [
    const _Title('盘面'),
    Wrap(
      spacing: 6,
      children: [
        for (var n = 6; n <= 12; n++)
          ChoiceChip(
            key: ValueKey('size-$n'),
            label: Text('$n'),
            selected: _size == n,
            onSelected: _search != null ? null : (_) => _setSize(n),
          ),
      ],
    ),
    const SizedBox(height: 4),
    Text('$_size×$_size，$_size 只猫、$_size 种颜色', style: _hint),
    const SizedBox(height: 16),
    const _Title('颜色'),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (var id = 0; id < _size; id++) _swatch(id), _eraser()],
    ),
    const SizedBox(height: 6),
    Text('左键拖动涂色，右键拖动擦除。圆点标出的颜色已经用过。', style: _hint),
    if (_size > 10)
      Text('App 只有 10 种颜色：第 11、12 种在游戏里和第 1、2 种同色。', style: _hint),
    const SizedBox(height: 16),
    const _Title('对称绘制'),
    SegmentedButton<Mirror>(
      showSelectedIcon: false,
      segments: [
        for (final m in Mirror.values)
          ButtonSegment(
            value: m,
            label: Text(m.label, key: ValueKey('mirror-${m.name}')),
          ),
      ],
      selected: {_mirror},
      onSelectionChanged: (s) => setState(() => _mirror = s.single),
    ),
    const SizedBox(height: 12),
    Row(
      children: [
        OutlinedButton(
          onPressed: _search != null
              ? null
              : () => setState(() {
                  _theme = _blank(_size);
                  _clearResult();
                }),
          child: const Text('清空'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _search != null ? null : _open,
          child: const Text('打开草稿…'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: showReferenceWindow,
          child: const Text('图案参考'),
        ),
      ],
    ),
  ];

  List<Widget> _generatePanel() {
    final problems = _problems;
    final result = _result;
    return [
      const _Title('生成设置'),
      Text('目标技巧（不选 = 不限定）', style: _hint),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final MapEntry(key: t, value: name) in _techniques.entries)
            FilterChip(
              label: Text(name),
              selected: _targets.contains(t),
              onSelected: (on) =>
                  setState(() => on ? _targets.add(t) : _targets.remove(t)),
            ),
        ],
      ),
      _switch('允许用到其他高级技巧', _superset, (v) => setState(() => _superset = v)),
      const SizedBox(height: 8),
      Text(
        '高级提示总次数：${_total.start.round()}–${_total.end.round()}',
        style: _hint,
      ),
      RangeSlider(
        values: _total,
        min: 0,
        max: 10,
        divisions: 10,
        onChanged: (v) => setState(() => _total = v),
      ),
      _switch(
        '规则 2：不白送开局、至多一个 2 格区域',
        _rules2,
        (v) => setState(() => _rules2 = v),
      ),
      _switch('涂色区域可扩展（占用空白格）', _grows, (v) => setState(() => _grows = v)),
      Row(
        children: [
          Text('搜索步数', style: _hint),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: _budget,
            items: [
              for (final n in [5000, 30000, 100000, 300000])
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: (v) => setState(() => _budget = v!),
          ),
        ],
      ),
      const SizedBox(height: 8),
      for (final p in problems)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(p, style: const TextStyle(color: Color(0xFFCC3D1A))),
        ),
      Row(
        children: [
          FilledButton(
            onPressed: _search == null && problems.isEmpty ? _generate : null,
            child: const Text('生成'),
          ),
          const SizedBox(width: 8),
          if (_search != null)
            OutlinedButton(onPressed: _stop, child: const Text('停止')),
        ],
      ),
      if (_status != null) ...[
        const SizedBox(height: 8),
        Text(_status!, key: const ValueKey('status'), style: _hint),
      ],
      if (result != null) ...[
        const Divider(height: 32),
        const _Title('结果'),
        Text(_describe(_advancedOnly(result.counts))),
        const SizedBox(height: 4),
        Text(
          '候选最多碎成 ${result.fragments ?? '—'} 块'
          '${result.orderCorrelation == null ? '' : '，解题顺序与区域大小相关 ${result.orderCorrelation!.toStringAsFixed(2)}'}',
          style: _hint,
        ),
        Text('全部提示：${_describe(result.counts)}', style: _hint),
        _switch(
          '显示结果（关掉看草稿）',
          _showResult,
          (v) => setState(() => _showResult = v),
        ),
        _switch('显示答案', _showCats, (v) => setState(() => _showCats = v)),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: '名称（关卡 ID / 文件名）',
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: _copy,
              child: const Text('复制关卡 JSON'),
            ),
            FilledButton.tonal(onPressed: _save, child: const Text('保存')),
            OutlinedButton(onPressed: _adopt, child: const Text('转为草稿继续改')),
          ],
        ),
      ] else if (_search == null) ...[
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: '名称（关卡 ID / 文件名）',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _save, child: const Text('保存草稿')),
      ],
    ];
  }

  Map<String, int> _advancedOnly(Map<String, int> counts) => {
    for (final t in _techniques.keys)
      if (counts.containsKey(t)) t: counts[t]!,
  };

  Widget _swatch(int id) {
    final used = _theme.any((row) => row.contains(id));
    final selected = _brush == id;
    return InkWell(
      key: ValueKey('swatch-$id'),
      onTap: () => setState(() => _brush = id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: RegionPalette.watercolor.color(id),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.black87 : Colors.transparent,
            width: 3,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${id + 1}',
              style: TextStyle(
                color: RegionPalette.watercolor.markerColor(id),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (used)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  Icons.circle,
                  size: 5,
                  color: RegionPalette.watercolor.markerColor(id),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _eraser() => InkWell(
    onTap: () => setState(() => _brush = null),
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFE6E2DA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _brush == null ? Colors.black87 : Colors.transparent,
          width: 3,
        ),
      ),
      child: const Icon(Icons.auto_fix_normal, size: 18),
    ),
  );

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label),
        value: value,
        onChanged: _search != null ? null : onChanged,
      );
}

const _hint = TextStyle(fontSize: 12, color: Colors.black54);

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
