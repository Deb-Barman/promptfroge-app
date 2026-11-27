import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'state/device_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // If a widget ever throws while building, show a quiet placeholder for that one spot instead of Flutter's
  // opaque gray box, and keep the rest of the screen usable.
  if (kReleaseMode) {
    ErrorWidget.builder = (details) {
      debugPrint('Widget error: ${details.exceptionAsString()}');
      return const _SoftError();
    };
  }
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const PromptForgeApp(),
  ));
}

class _SoftError extends StatelessWidget {
  const _SoftError();

  @override
  Widget build(BuildContext context) => const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('This section hit a problem. Go back and reopen it.', textAlign: TextAlign.center, style: TextStyle(color: Color(0x99A0A7B4), fontSize: 12.5, decoration: TextDecoration.none, fontWeight: FontWeight.w400)),
          ),
        ),
      );
}
