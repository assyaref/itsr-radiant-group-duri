import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants/app_constants.dart';
import 'constants/app_theme.dart';
import 'data/resilient_http_client.dart';
import 'router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorHandlers();

  // Validate Supabase configuration (passed via --dart-define at build time).
  // A misconfigured build shows an explanatory page instead of a blank screen.
  final configProblem = startupConfigurationProblem(
    AppConstants.supabaseUrl,
    AppConstants.supabaseAnonKey,
  );
  if (configProblem != null) {
    debugPrint('ITSR startup aborted: $configProblem');
    runApp(StartupErrorApp(message: configProblem));
    return;
  }

  // Ticket lists open details with context.push (keeps Back working). Make the
  // browser URL follow push too, so a refresh or a copied link stays on the
  // ticket (Phase 16 E2E finding: URL stayed on the list page).
  GoRouter.optionURLReflectsImperativeAPIs = true;

  try {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
      // Timeouts on every request + safe retries for reads.
      httpClient: ResilientHttpClient(),
    );
  } catch (e, st) {
    // E.g. corrupted persisted session in browser storage.
    debugPrint('Supabase.initialize failed: $e\n$st');
    runApp(const StartupErrorApp(
      message: 'The application could not start. Please reload the page. '
          'If the problem persists, clear this site\'s data in the browser '
          'and contact IT Support.',
      canReload: true,
    ));
    return;
  }

  runApp(const ProviderScope(child: MyApp()));
}

/// Returns a user-facing explanation when the build configuration is unusable,
/// or null when it is fine. Pure, so it can be unit-tested.
String? startupConfigurationProblem(String url, String key) {
  if (url.isEmpty || key.isEmpty) {
    return 'This build is missing its server configuration '
        '(SUPABASE_URL / SUPABASE_ANON_KEY must be passed with --dart-define). '
        'Please contact IT Support.';
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme || !(uri.scheme == 'https' || uri.scheme == 'http') ||
      uri.host.isEmpty) {
    return 'This build has an invalid server URL. Please contact IT Support.';
  }
  // Refuse to start with a server-side secret (service_role / sb_secret_) key.
  if (AppConstants.looksLikeSecretKey(key) || key.length > 500) {
    return 'This build contains a server-side secret key instead of the public '
        'publishable key and has been blocked for safety. Please contact IT Support.';
  }
  return null;
}

/// Uncaught errors are logged instead of silently killing the app, and a
/// broken widget renders a small notice instead of a grey/red screen.
void _installGlobalErrorHandlers() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
    return true; // handled: keep the app running
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => const Material(
          color: Colors.transparent,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'This part of the page could not be displayed. Please reload.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Minimal app shown when startup cannot continue.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message, this.canReload = false});
  final String message;
  final bool canReload;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppConstants.appName,
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 56, color: Colors.red[400]),
                    const SizedBox(height: 16),
                    const Text(
                      'ITSR is unavailable',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    if (canReload) ...[
                      const SizedBox(height: 8),
                      const Text('Reload the page (F5) to try again.',
                          textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
