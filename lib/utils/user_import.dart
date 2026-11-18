import 'dart:convert';
import 'dart:typed_data';

import '../constants/app_constants.dart';
import 'validators.dart';

/// Bulk user import from a CSV file (made from [UserImport.templateBytes]).
///
/// Pure Dart so it can be unit-tested. Accounts are created one by one via the
/// `admin-users` Edge Function, which re-validates every field server-side.
class UserImport {
  UserImport._();

  static const int maxRows = 500;

  /// Example row in the template; rows with this employee number are skipped.
  static const String exampleEmployeeNumber = 'CONTOH01';

  /// Template columns (Indonesian headers, as shown to administrators).
  static const List<String> headers = [
    'NIK',
    'Nama Lengkap',
    'Email',
    'Departemen',
    'Role',
    'No HP',
    'Password',
  ];

  /// Header aliases (lower-case, spaces/underscores removed) -> field.
  static const Map<String, String> _aliases = {
    'nik': 'employee_number',
    'employeenumber': 'employee_number',
    'nomorkaryawan': 'employee_number',
    'namalengkap': 'full_name',
    'nama': 'full_name',
    'fullname': 'full_name',
    'email': 'email',
    'departemen': 'department',
    'department': 'department',
    'role': 'role',
    'peran': 'role',
    'nohp': 'phone_number',
    'telepon': 'phone_number',
    'phone': 'phone_number',
    'phonenumber': 'phone_number',
    'password': 'password',
    'katasandi': 'password',
  };

  /// Role spellings accepted in the Role column.
  static const Map<String, String> _roles = {
    'employee': AppConstants.roleEmployee,
    'karyawan': AppConstants.roleEmployee,
    'pegawai': AppConstants.roleEmployee,
    'user': AppConstants.roleEmployee,
    'itsupport': AppConstants.roleITSupport,
    'it': AppConstants.roleITSupport,
    'teknisi': AppConstants.roleITSupport,
    'administrator': AppConstants.roleAdministrator,
    'admin': AppConstants.roleAdministrator,
  };

  static final _employeeNumber = RegExp(r'^[A-Z0-9]{2,20}$');

  /// CSV template, `;`-separated with a UTF-8 BOM so Excel (Indonesian
  /// locale) opens it in columns. Contains one example row.
  static Uint8List templateBytes() {
    final lines = [
      headers.join(';'),
      [
        exampleEmployeeNumber,
        'Contoh Nama Karyawan',
        'nama@domain-perusahaan',
        'Operasional',
        'employee',
        '081234567890',
        'PasswordAwal123',
      ].join(';'),
    ];
    return Uint8List.fromList([
      0xEF, 0xBB, 0xBF, // BOM
      ...utf8.encode('${lines.join('\r\n')}\r\n'),
    ]);
  }

  /// Parses CSV bytes into rows with per-row validation.
  /// [existingEmployeeNumbers] / [existingEmails] mark duplicates of accounts
  /// that already exist. Throws [FormatException] for an unusable file.
  static List<ImportRow> parse(
    Uint8List bytes, {
    Set<String> existingEmployeeNumbers = const {},
    Set<String> existingEmails = const {},
  }) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final lines = text.split(RegExp(r'\r\n|\n|\r'));
    // Excel's optional "sep=;" hint line.
    var start = 0;
    String? sep;
    if (lines.isNotEmpty && lines.first.toLowerCase().startsWith('sep=')) {
      sep = lines.first.length > 4 ? lines.first[4] : null;
      start = 1;
    }
    final records = _records(lines.skip(start).join('\n'), sep);
    if (records.isEmpty) throw const FormatException('File kosong');

    final header = records.first
        .map(
          (h) => _aliases[h.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '')],
        )
        .toList();
    for (final required in const [
      'employee_number',
      'full_name',
      'email',
      'role',
      'password',
    ]) {
      if (!header.contains(required)) {
        throw FormatException(
          'Kolom wajib tidak ditemukan. Gunakan template: ${headers.join(', ')}',
        );
      }
    }

    final rows = <ImportRow>[];
    final seenNo = <String>{};
    final seenEmail = <String>{};
    final existingNo = existingEmployeeNumbers
        .map((e) => e.toUpperCase())
        .toSet();
    final existingMail = existingEmails.map((e) => e.toLowerCase()).toSet();

    for (var i = 1; i < records.length; i++) {
      final rec = records[i];
      if (rec.every((c) => c.trim().isEmpty)) continue;
      final f = <String, String>{};
      for (var c = 0; c < header.length && c < rec.length; c++) {
        final key = header[c];
        if (key != null) f[key] = rec[c].trim();
      }
      final row = ImportRow(
        line: i + 1 + start,
        employeeNumber: (f['employee_number'] ?? '').toUpperCase(),
        fullName: f['full_name'] ?? '',
        email: (f['email'] ?? '').toLowerCase(),
        department: (f['department'] ?? '').isEmpty
            ? 'General'
            : f['department']!,
        role:
            _roles[(f['role'] ?? '').toLowerCase().replaceAll(
              RegExp(r'[\s_\-]'),
              '',
            )] ??
            '',
        rawRole: f['role'] ?? '',
        phoneNumber: (f['phone_number'] ?? '').isEmpty
            ? null
            : f['phone_number'],
        password: f['password'] ?? '',
      );
      if (row.employeeNumber == exampleEmployeeNumber) {
        rows.add(
          row.withStatus(ImportStatus.skipped, 'Baris contoh — dilewati'),
        );
        continue;
      }
      final error = _validate(row, seenNo, seenEmail, existingNo, existingMail);
      seenNo.add(row.employeeNumber);
      seenEmail.add(row.email);
      rows.add(
        error == null ? row : row.withStatus(ImportStatus.invalid, error),
      );
      if (rows.length > maxRows) {
        throw const FormatException('Maksimal $maxRows baris per import');
      }
    }
    if (rows.isEmpty) {
      throw const FormatException('Tidak ada data pengguna di file');
    }
    return rows;
  }

  static String? _validate(
    ImportRow r,
    Set<String> seenNo,
    Set<String> seenEmail,
    Set<String> existingNo,
    Set<String> existingMail,
  ) {
    if (!_employeeNumber.hasMatch(r.employeeNumber)) {
      return 'NIK harus 2–20 huruf/angka';
    }
    if (r.fullName.isEmpty || r.fullName.length > 120) {
      return 'Nama lengkap wajib diisi';
    }
    if (Validators.email(r.email) != null) return 'Email tidak valid';
    if (r.role.isEmpty) {
      return r.rawRole.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '') ==
              'superadmin'
          ? 'Role Super Admin tidak bisa diimport'
          : 'Role harus employee, it_support, atau administrator';
    }
    if (Validators.newPassword(r.password) != null) {
      return 'Password minimal 8 karakter (atau PIN 4–5 digit)';
    }
    if (seenNo.contains(r.employeeNumber)) return 'NIK duplikat di file';
    if (seenEmail.contains(r.email)) return 'Email duplikat di file';
    if (existingNo.contains(r.employeeNumber)) return 'NIK sudah terdaftar';
    if (existingMail.contains(r.email)) return 'Email sudah terdaftar';
    return null;
  }

  /// Splits CSV text into records, honouring double-quoted fields. The
  /// delimiter is [sep] or detected from the header line (`;`, `,` or tab).
  static List<List<String>> _records(String text, String? sep) {
    final firstLine = text.split('\n').first;
    final delim =
        sep ??
        ([';', ',', '\t']..sort(
              (a, b) => b
                  .allMatches(firstLine)
                  .length
                  .compareTo(a.allMatches(firstLine).length),
            ))
            .first;
    final out = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == delim) {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n') {
        row.add(cell.toString());
        cell.clear();
        out.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      out.add(row);
    }
    return out;
  }
}

enum ImportStatus { ready, invalid, skipped, created, failed }

class ImportRow {
  const ImportRow({
    required this.line,
    required this.employeeNumber,
    required this.fullName,
    required this.email,
    required this.department,
    required this.role,
    required this.rawRole,
    required this.phoneNumber,
    required this.password,
    this.status = ImportStatus.ready,
    this.message,
  });

  final int line;
  final String employeeNumber;
  final String fullName;
  final String email;
  final String department;
  final String role;
  final String rawRole;
  final String? phoneNumber;
  final String password;
  final ImportStatus status;
  final String? message;

  ImportRow withStatus(ImportStatus s, [String? msg]) => ImportRow(
    line: line,
    employeeNumber: employeeNumber,
    fullName: fullName,
    email: email,
    department: department,
    role: role,
    rawRole: rawRole,
    phoneNumber: phoneNumber,
    password: password,
    status: s,
    message: msg,
  );
}
