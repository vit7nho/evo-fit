import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/provider_config.dart';

void main() {
  runApp(const ProviderScope(retry: noAutomaticRetry, child: EvoFitApp()));
}
