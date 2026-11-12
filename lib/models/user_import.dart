import 'dart:convert';
import 'dart:typed_data';

import '../constants/app_constants.dart';
import '../utils/validators.dart';
import '../utils/xlsx_lite.dart';
import 'user_model.dart';

/// One row of a bulk user import, already normalised and validated.
class ImportRow {
  ImportRow({
    required this.line,
    required this.employeeNumber,
    required this.fullName,
    required this.email,
    required this.department,
    required this.role,
    required this.phone,
    required this.password,
    required this.errors,
  });

  final int line; // spreadsheet row number (header = 1)
  final String employeeNumber;
  final String fullName;
  final String email;
  final String department;
  final String role;
  final String? phone;
  final String password;
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

/// Bulk import of user accounts from the Excel/CSV template.
class UserImport {
  UserImport._();

  static const dataSheet = 'Data Karyawan';
  static const headers = [
    'employee_number',
    'full_name',
    'email',
    'department',
    'role',
    'phone_number',
    'password',
  ];
  static const maxRows = 500;

  /// The downloadable template: an empty "Data Karyawan" sheet (text columns)
  /// plus a "Petunjuk" sheet with rules and examples.
  static Uint8List template() => buildXlsx([
        XlsxSheet(
          dataSheet,
          [
            ['employee_number*', 'full_name*', 'email*', 'department', 'role*', 'phone_number', 'password*'],
          ],
          widths: const [20, 28, 32, 22, 16, 18, 16],
          textColumns: true,
        ),
        const XlsxSheet(
          'Petunjuk',
          [
            ['Kolom', 'Wajib', 'Keterangan', 'Contoh'],
            ['employee_number', 'Ya', '2–20 huruf/angka tanpa spasi (NIK). Harus unik.', 'EMP001 / 03233'],
            ['full_name', 'Ya', 'Nama lengkap, maks. 120 karakter.', 'Andi Pratama'],
            ['email', 'Ya', 'Email kantor yang valid. Harus unik.', 'andi.pratama@(domain kantor)'],
            ['department', 'Tidak', 'Departemen. Kosong = General.', 'Marketing'],
            ['role', 'Ya', 'employee (Karyawan), it_support (IT Support), atau administrator.', 'employee'],
            ['phone_number', 'Tidak', 'Nomor HP.', '081234567890'],
            ['password', 'Ya', 'PIN 4–5 digit angka ATAU password minimal 8 karakter.', '12345'],
            ['', '', '', ''],
            ['Cara pakai', '', 'Isi sheet "Data Karyawan" mulai baris 2, satu akun per baris. '
                'Jangan ubah judul kolom. Kolom sudah berformat Teks agar angka 0 di depan tidak hilang.', ''],
            ['', '', 'Simpan sebagai .xlsx (atau CSV), lalu pilih "Import Karyawan" di aplikasi. '
                'Anda akan melihat pratinjau dan hanya baris yang valid yang dibuat.', ''],
            ['', '', 'Bagikan password/PIN awal kepada karyawan secara pribadi. '
                'Karyawan dapat menggantinya di menu Profil > Ubah Password.', ''],
          ],
          widths: [18, 8, 80, 30],
        ),
      ]);

  /// Reads an .xlsx or .csv file into rows of strings.
  static List<List<String>> readFile(String fileName, Uint8List bytes) {
    final n = fileName.toLowerCase();
    if (n.endsWith('.csv')) return readCsv(utf8.decode(bytes, allowMalformed: true));
    if (n.endsWith('.xlsx')) return readXlsx(bytes, preferredSheet: dataSheet);
    throw const FormatException('Gunakan file .xlsx (template) atau .csv');
  }

  static String _norm(String h) => h.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  static const _aliases = <String, List<String>>{
    'employee_number': ['employeenumber', 'nik', 'nomorkaryawan', 'nokaryawan', 'employeeno'],
    'full_name': ['fullname', 'nama', 'namalengkap', 'name'],
    'email': ['email', 'emailkantor'],
    'department': ['department', 'departemen', 'divisi', 'bagian'],
    'role': ['role', 'peran', 'akses'],
    'phone_number': ['phonenumber', 'phone', 'telepon', 'nohp', 'hp', 'nomorhp'],
    'password': ['password', 'pin', 'passwordpin', 'kata sandi', 'katasandi'],
  };

  static String? roleOf(String raw) {
    final r = _norm(raw);
    if (r.isEmpty || r == 'employee' || r == 'karyawan' || r == 'pegawai') return AppConstants.roleEmployee;
    if (r == 'itsupport' || r == 'teknisi' || r == 'it' || r == 'support') return AppConstants.roleITSupport;
    if (r == 'administrator' || r == 'admin') return AppConstants.roleAdministrator;
    return null;
  }

  /// Validates the rows of a file against the policy and existing users.
  /// Throws [FormatException] for a missing / unrecognised header row.
  static List<ImportRow> parse(List<List<String>> table, List<UserModel> existing) {
    final headerIndex = table.indexWhere((r) => r.any((c) => c.trim().isNotEmpty));
    if (headerIndex < 0) throw const FormatException('File kosong');
    final header = table[headerIndex];
    final col = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final h = _norm(header[i]);
      for (final e in _aliases.entries) {
        if (e.value.contains(h) && !col.containsKey(e.key)) col[e.key] = i;
      }
    }
    final missing = ['employee_number', 'full_name', 'email', 'password'].where((k) => !col.containsKey(k));
    if (missing.isNotEmpty) {
      throw FormatException('Kolom wajib tidak ditemukan: ${missing.join(', ')}. Gunakan template.');
    }

    final existingNumbers = {for (final u in existing) u.employeeNumber.toUpperCase()};
    final existingEmails = {for (final u in existing) u.email.toLowerCase()};
    final seenNumbers = <String>{}, seenEmails = <String>{};
    final out = <ImportRow>[];

    for (var r = headerIndex + 1; r < table.length; r++) {
      final row = table[r];
      String v(String key) {
        final i = col[key];
        return i == null || i >= row.length ? '' : row[i].trim();
      }

      if (row.every((c) => c.trim().isEmpty)) continue; // blank line
      if (out.length >= maxRows) break;

      final errors = <String>[];
      final number = Validators.normalizeEmployeeNumber(v('employee_number'));
      final name = v('full_name');
      final email = v('email').toLowerCase();
      final dept = v('department').isEmpty ? 'General' : v('department');
      final role = roleOf(v('role'));
      final phone = v('phone_number');
      final password = v('password');

      void check(String? msg) {
        if (msg != null) errors.add(msg);
      }

      check(Validators.employeeNumber(number) == null ? null : 'Employee number tidak valid (2–20 huruf/angka)');
      check(Validators.requiredText(name, 'Nama', max: 120) == null ? null : 'Nama wajib diisi (maks. 120)');
      check(Validators.email(email) == null ? null : 'Email tidak valid');
      if (dept.length > 120) errors.add('Departemen terlalu panjang');
      if (role == null) errors.add('Role harus employee, it_support, atau administrator');
      check(Validators.newPassword(password) == null ? null : 'Password: PIN 4–5 digit atau min. 8 karakter');
      if (number.isNotEmpty && existingNumbers.contains(number)) errors.add('Employee number sudah terdaftar');
      if (email.isNotEmpty && existingEmails.contains(email)) errors.add('Email sudah terdaftar');
      if (number.isNotEmpty && !seenNumbers.add(number)) errors.add('Employee number ganda di file');
      if (email.isNotEmpty && !seenEmails.add(email)) errors.add('Email ganda di file');

      out.add(ImportRow(
        line: r + 1,
        employeeNumber: number,
        fullName: name,
        email: email,
        department: dept,
        role: role ?? AppConstants.roleEmployee,
        phone: phone.isEmpty ? null : phone,
        password: password,
        errors: errors,
      ));
    }
    return out;
  }
}
