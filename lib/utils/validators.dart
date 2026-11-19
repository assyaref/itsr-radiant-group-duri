/// Form validators. Rules mirror the database CHECK constraints so users get
/// immediate feedback; the database remains the authority.
class Validators {
  Validators._();

  static final RegExp employeeNumberPattern = RegExp(r'^[A-Z0-9]{2,20}$');
  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String normalizeEmployeeNumber(String value) =>
      value.trim().toUpperCase();

  static String? employeeNumber(String? value) {
    final v = normalizeEmployeeNumber(value ?? '');
    if (v.isEmpty) return 'Please enter your employee number';
    if (!employeeNumberPattern.hasMatch(v)) {
      return 'Use 2–20 letters or digits (e.g. EMP001)';
    }
    return null;
  }

  /// A PIN of 4, 5 or 6 digits is allowed as a password.
  static final RegExp pinPattern = RegExp(r'^\d{4,6}$');

  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    if (pinPattern.hasMatch(value)) return null;
    if (value.length < 6) return 'Enter your PIN (min. 4 digits) or password';
    return null;
  }

  /// New passwords: a PIN of 4+ digits, or 6–128 characters.
  /// (4–6 digit PINs are stored peppered; longer numbers as normal passwords.)
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (pinPattern.hasMatch(v)) return null;
    if (RegExp(r'^\d+$').hasMatch(v) && v.length < 4) {
      return 'PIN must be at least 4 digits';
    }
    if (v.length < 6) return 'Use a PIN of at least 4 digits or a password of at least 6 characters';
    if (v.length > 128) return 'Password is too long';
    return null;
  }

  static String? subject(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter a subject';
    if (v.length < 3) return 'Subject must be at least 3 characters';
    if (v.length > 200) return 'Subject must be at most 200 characters';
    return null;
  }

  static String? description(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please describe the problem';
    if (v.length < 5) return 'Description must be at least 5 characters';
    if (v.length > 5000) return 'Description must be at most 5000 characters';
    return null;
  }

  static String? requiredText(String? value, String field, {int max = 120}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '$field is required';
    if (v.length > max) return '$field must be at most $max characters';
    return null;
  }

  static String? email(String? value, {bool required = true}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return required ? 'Email is required' : null;
    if (!_email.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Removes characters that have meaning inside a PostgREST `or=(...)` filter,
  /// so free-text search can never alter the filter structure.
  static String sanitizeSearch(String input) =>
      input.replaceAll(RegExp(r'[,()"\\*%:.]'), ' ').trim();
}
