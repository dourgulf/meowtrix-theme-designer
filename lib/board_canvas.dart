// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'dart:math';

import 'palette.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// The painting surface: one square per cell in its Region colour (the
/// app's palette), grey when unpainted. Drag or click with the primary
/// button to paint, with the secondary button to erase. A primary press
/// that lands on a cell already in the brush colour erases instead, for
/// the whole stroke. Without [onPaint] it only displays the board.
class BoardCanvas extends StatefulWidget {
  const BoardCanvas({
    super.key,
    required this.cells,
    this.themeMask,
    this.solution,
    this.hasBrushColour,
    this.onPaint,
  });

  /// Region ID per cell, null for unpainted.
  final List<List<int?>> cells;

  /// Cells marked with a dot (the painted theme, shown over a result).
  final List<List<bool>>? themeMask;

  /// Cat column per row, drawn when set.
  final List<int>? solution;

  /// Whether the painted theme already has the brush colour at a cell;
  /// decides whether a primary press starts a painting or an erasing
  /// stroke.
  final bool Function(int row, int column)? hasBrushColour;

  /// Called for every cell a stroke touches.
  final void Function(int row, int column, {required bool erase})? onPaint;

  @override
  State<BoardCanvas> createState() => _BoardCanvasState();
}

class _BoardCanvasState extends State<BoardCanvas> {
  bool _erasing = false;
  (int, int)? _last;

  static const _gap = 3.0;

  int get _size => widget.cells.length;

  (int, int)? _cellAt(Offset local, double side) {
    final cell = side / _size;
    final r = (local.dy / cell).floor(), c = (local.dx / cell).floor();
    if (r < 0 || c < 0 || r >= _size || c >= _size) return null;
    return (r, c);
  }

  void _paint(Offset local, double side) {
    final hit = _cellAt(local, side);
    if (hit == null || hit == _last) return;
    _last = hit;
    widget.onPaint?.call(hit.$1, hit.$2, erase: _erasing);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final cell = side / _size;
        return SizedBox.square(
          dimension: side,
          child: Listener(
            onPointerDown: (e) {
              final hit = _cellAt(e.localPosition, side);
              _erasing =
                  e.buttons & kSecondaryMouseButton != 0 ||
                  (hit != null &&
                      (widget.hasBrushColour?.call(hit.$1, hit.$2) ?? false));
              _last = null;
              _paint(e.localPosition, side);
            },
            onPointerMove: (e) => _paint(e.localPosition, side),
            onPointerUp: (_) => _last = null,
            child: Stack(
              children: [
                for (var r = 0; r < _size; r++)
                  for (var c = 0; c < _size; c++)
                    Positioned(
                      left: c * cell + _gap / 2,
                      top: r * cell + _gap / 2,
                      width: cell - _gap,
                      height: cell - _gap,
                      child: _Cell(
                        key: ValueKey('cell-$r-$c'),
                        id: widget.cells[r][c],
                        marked: widget.themeMask?[r][c] ?? false,
                        cat: widget.solution?[r] == c,
                        radius: min(6, cell * 0.15),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.id,
    required this.marked,
    required this.cat,
    required this.radius,
  });

  final int? id;
  final bool marked;
  final bool cat;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final id = this.id;
    final ink = id == null
        ? Colors.black54
        : RegionPalette.watercolor.markerColor(id);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: id == null
            ? const Color(0xFFE6E2DA)
            : RegionPalette.watercolor.color(id),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (marked)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          if (cat)
            FractionallySizedBox(
              widthFactor: 0.55,
              heightFactor: 0.55,
              child: FittedBox(child: Icon(Icons.pets, color: ink)),
            ),
        ],
      ),
    );
  }
}
