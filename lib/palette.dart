// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
// Author: lidawen
// Standalone preview palette, preserved from the original designer.
import 'package:flutter/material.dart';

class RegionPalette {
  const RegionPalette._();
  static const watercolor = RegionPalette._();
  static const _colors = [
    Color(0xFFFFB2C6),
    Color(0xFF227A66),
    Color(0xFFFFE085),
    Color(0xFF105081),
    Color(0xFF654228),
    Color(0xFF9FCA90),
    Color(0xFFE49758),
    Color(0xFF6E67A8),
    Color(0xFF37B1BF),
    Color(0xFFB84A47),
    Color(0xFFACDEFC),
    Color(0xFF958679),
  ];
  static const _dark = {1, 3, 4, 7, 9, 11};
  Color color(int slot) => _colors[slot % _colors.length];
  Color markerColor(int slot) => _dark.contains(slot % _colors.length)
      ? Colors.white
      : const Color(0xFF49353F);
}
