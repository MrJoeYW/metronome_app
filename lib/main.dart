import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'metronome_database.dart';

part 'src/app_palette.dart';
part 'src/pages/metronome_main_page.dart';
part 'src/widgets/top_function_bar.dart';
part 'src/widgets/beat_pattern.dart';
part 'src/widgets/bpm_dial.dart';
part 'src/widgets/selectors.dart';
part 'src/widgets/transport_and_presets.dart';
part 'src/sheets/function_sheets.dart';
part 'src/pages/webview_page.dart';
part 'src/pages/settings_page.dart';
part 'src/sheets/metronome_settings_sheet.dart';
part 'src/models/tap_tempo.dart';
part 'src/models/metronome_models.dart';

/// App 鍚姩鍏ュ彛锛氬厛閿佸畾娌夋蹈寮忕郴缁?UI锛屽啀杩涘叆 Flutter 椤甸潰鏍戙€?
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _applyImmersiveMode();
  runApp(const MyApp());
}

Future<void> _applyImmersiveMode() async {
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pulse Grid',
      theme: base.copyWith(
        scaffoldBackgroundColor: AppPalette.background,
        colorScheme: const ColorScheme.dark(
          primary: AppPalette.primary,
          secondary: AppPalette.secondary,
          surface: AppPalette.surface,
          surfaceContainerHighest: AppPalette.surfaceVariant,
          error: AppPalette.danger,
          onPrimary: AppPalette.background,
          onSurface: AppPalette.textPrimary,
        ),
        textTheme: base.textTheme.apply(
          bodyColor: AppPalette.textPrimary,
          displayColor: AppPalette.textPrimary,
        ),
      ),
      home: const MetronomeMainPage(),
    );
  }
}

/// 椤跺眰椤甸潰瀹瑰櫒銆?///
