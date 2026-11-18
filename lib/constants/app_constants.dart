import 'dart:convert';

class AppConstants {
  static const String appName = 'ITSR Radiant Group Duri';
  static const String appTagline = 'Report. Track. Resolve.';
  static const String appShortName = 'ITSR';

  // Environment configuration - passed at build time using --dart-define.
  // Only the PUBLIC (publishable/anon) key may ever be supplied here.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  static bool get hasValidConfiguration =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Rejects keys that are clearly server-side secrets.
  static bool looksLikeSecretKey(String key) =>
      key.startsWith('sb_secret_') ||
      key.contains('service_role') ||
      _jwtRole(key) == 'service_role';

  static String? _jwtRole(String key) {
    final parts = key.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final role = (jsonDecode(payload) as Map<String, dynamic>)['role'];
      return role is String ? role : null;
    } catch (_) {
      return null;
    }
  }

  // User roles
  static const String roleEmployee = 'employee';
  static const String roleITSupport = 'it_support';
  static const String roleAdministrator = 'administrator';
  static const String roleSuperAdmin = 'superadmin';

  /// Roles that can be assigned in the app. [roleSuperAdmin] is never
  /// assignable: superadmin accounts are locked server-side.
  static const List<String> roles = [
    roleEmployee,
    roleITSupport,
    roleAdministrator,
  ];

  // Ticket priorities
  static const String priorityLow = 'low';
  static const String priorityMedium = 'medium';
  static const String priorityHigh = 'high';
  static const String priorityCritical = 'critical';
  static const List<String> priorities = [
    priorityLow,
    priorityMedium,
    priorityHigh,
    priorityCritical,
  ];

  // Ticket statuses
  static const String statusOpen = 'open';
  static const String statusAssigned = 'assigned';
  static const String statusInProgress = 'in_progress';
  static const String statusPendingUser = 'pending_user';
  static const String statusResolved = 'resolved';
  static const String statusClosed = 'closed';
  static const String statusReopened = 'reopened';
  static const List<String> statuses = [
    statusOpen,
    statusAssigned,
    statusInProgress,
    statusPendingUser,
    statusResolved,
    statusClosed,
    statusReopened,
  ];

  /// Staff status transitions — mirrors private.is_valid_transition() in the
  /// database (the database is authoritative; this only drives which buttons
  /// are shown).
  static const Map<String, List<String>> staffTransitions = {
    statusOpen: [statusInProgress, statusClosed],
    statusAssigned: [
      statusInProgress,
      statusPendingUser,
      statusResolved,
      statusOpen,
    ],
    statusInProgress: [statusPendingUser, statusResolved],
    statusPendingUser: [statusInProgress, statusResolved],
    statusResolved: [statusClosed, statusReopened],
    statusClosed: [statusReopened],
    statusReopened: [statusInProgress, statusResolved],
  };

  // Notification recipient addresses are NOT constants: administrators set
  // them in Admin > Settings (stored in public.app_settings).
}
