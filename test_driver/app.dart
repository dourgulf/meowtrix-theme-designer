// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 lidawen
import 'package:flutter_driver/driver_extension.dart';
import 'package:theme_designer/main.dart' as app;

/// Entry point with the Flutter Driver extension, for driving the tool
/// from a script: `fvm flutter run -d macos -t test_driver/app.dart`.
void main() {
  enableFlutterDriverExtension();
  app.main();
}
