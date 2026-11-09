import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: Colors.blue[700]!,
    scaffoldBackgroundColor: Colors.grey[50]!,
    colorScheme: ColorScheme.light(
      primary: Colors.blue[700]!,
      onPrimary: Colors.white,
      secondary: Colors.blue[900]!,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.grey[900]!,
      error: Colors.red[600]!,
      onError: Colors.white,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blue[700]!,
      foregroundColor: Colors.white,
      elevation: 4,
      centerTitle: false,
    ),
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Colors.grey[900]!,
      ),
      displayMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Colors.grey[900]!,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: Colors.grey[900]!,
      ),
      titleMedium: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.grey[900]!,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: Colors.grey[800]!),
      bodyMedium: TextStyle(fontSize: 14, color: Colors.grey[700]!),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: Colors.blue[400]!,
    scaffoldBackgroundColor: Colors.grey[900]!,
    colorScheme: ColorScheme.dark(
      primary: Colors.blue[400]!,
      onPrimary: Colors.grey[900]!,
      secondary: Colors.blue[300]!,
      onSecondary: Colors.grey[900]!,
      surface: Colors.grey[850]!,
      onSurface: Colors.white,
      error: Colors.red[400]!,
      onError: Colors.grey[900]!,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.grey[850]!,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey[900]!,
      foregroundColor: Colors.white,
      elevation: 4,
      centerTitle: false,
    ),
    textTheme: TextTheme(
      displayLarge: const TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      displayMedium: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      titleLarge: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      titleMedium: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: Colors.grey[300]!),
      bodyMedium: TextStyle(fontSize: 14, color: Colors.grey[400]!),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[700]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[700]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.blue[400]!, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );

  // Status colors for tickets
  static Color getStatusColor(String? status) {
    switch (status) {
      case 'open':
        return Colors.blue[600]!;
      case 'assigned':
        return Colors.purple[600]!;
      case 'in_progress':
        return Colors.orange[600]!;
      case 'pending_user':
        return Colors.amber[600]!;
      case 'resolved':
        return Colors.green[600]!;
      case 'closed':
        return Colors.grey[600]!;
      case 'reopened':
        return Colors.red[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  // Priority colors
  static Color getPriorityColor(String? priority) {
    switch (priority) {
      case 'low':
        return Colors.green[600]!;
      case 'medium':
        return Colors.blue[600]!;
      case 'high':
        return Colors.orange[600]!;
      case 'critical':
        return Colors.red[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  // Format status text for display
  static String formatStatus(String? status) {
    if (status == null) return 'Unknown';
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  // Format priority text for display
  static String formatPriority(String? priority) {
    if (priority == null) return 'Unknown';
    return priority
        .split(' ')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}
