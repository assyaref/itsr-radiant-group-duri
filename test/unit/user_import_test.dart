import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/utils/user_import.dart';

Uint8List csv(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('template parses: only the example row, which is skipped', () {
    final rows = UserImport.parse(UserImport.templateBytes());
    expect(rows, hasLength(1));
    expect(rows.single.status, ImportStatus.skipped);
  });

  test('semicolon CSV with quotes, aliases and role labels', () {
    final rows = UserImport.parse(
      csv(
        'NIK;Nama Lengkap;Email;Departemen;Role;No HP;Password\n'
        'e001;"Budi; Santoso";Budi@X.com;HR;Karyawan;0812;rahasia123\n'
        'it01;Tika;tika@x.com;;IT Support;;rahasia123\n',
      ),
    );
    expect(rows.map((r) => r.status), everyElement(ImportStatus.ready));
    expect(rows[0].employeeNumber, 'E001');
    expect(rows[0].fullName, 'Budi; Santoso');
    expect(rows[0].email, 'budi@x.com');
    expect(rows[0].role, 'employee');
    expect(rows[1].role, 'it_support');
    expect(rows[1].department, 'General');
  });

  test('comma CSV, validation and duplicates', () {
    final rows = UserImport.parse(
      csv(
        'nik,nama,email,role,password\n'
        'A1,Ok,a@x.com,admin,rahasia123\n'
        'A1,Dup,b@x.com,employee,rahasia123\n'
        'B2,Bad,not-an-email,employee,rahasia123\n'
        'C3,Super,c@x.com,superadmin,rahasia123\n'
        'D4,Short,d@x.com,employee,abc\n'
        'E5,Exists,e@x.com,employee,rahasia123\n',
      ),
      existingEmployeeNumbers: {'E5'},
    );
    expect(rows[0].status, ImportStatus.ready);
    expect(rows[0].role, 'administrator');
    expect(rows[1].message, 'NIK duplikat di file');
    expect(rows[2].message, 'Email tidak valid');
    expect(rows[3].message, contains('Super Admin'));
    expect(rows[4].status, ImportStatus.invalid);
    expect(rows[5].message, 'NIK sudah terdaftar');
  });

  test('missing required columns is a format error', () {
    expect(
      () => UserImport.parse(csv('nama;email\nx;y@z.com\n')),
      throwsFormatException,
    );
  });
}
