import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'constants/app_constants.dart';
import 'constants/app_theme.dart';
import 'router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Validate Supabase configuration (passed via --dart-define at build time)
  if (!AppConstants.hasValidConfiguration) {
    throw StateError(
      'Please configure your Supabase URL and anon key using --dart-define. '
      'Example: flutter build web --release --dart-define=SUPABASE_URL=your_url --dart-define=SUPABASE_ANON_KEY=your_anon_key '
      'These values are required to connect to your Supabase project. '
      'Never commit your service role key to version control.',
    );
  }

  // Refuse to start with a server-side secret (service_role / sb_secret_) key.
  if (AppConstants.looksLikeSecretKey(AppConstants.supabaseAnonKey) ||
      AppConstants.supabaseAnonKey.length > 500) {
    throw StateError(
      'Invalid publishable key detected. The anon key should not contain "service_role" '
      'and should be the public publishable key from your Supabase project settings. '
      'Service role keys must never be included in client-side code.',
    );
  }

  // Ticket lists open details with context.push (keeps Back working). Make the
  // browser URL follow push too, so a refresh or a copied link stays on the
  // ticket (Phase 16 E2E finding: URL stayed on the list page).
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // Initialize Supabase with safe configuration
  await Supabase.initialize(
    url: AppConstants.supabaseUrl,
    publishableKey: AppConstants.supabaseAnonKey,
  );

  runApp(const ProviderScope(child: MyApp()));
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
