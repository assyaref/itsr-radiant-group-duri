import 'dart:convert';
import 'dart:io';
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

  test('bundled .xlsx template parses: only the example row, skipped', () {
    final bytes = File(
      'assets/templates/template-import-user-itsr.xlsx',
    ).readAsBytesSync();
    final rows = UserImport.parse(Uint8List.fromList(bytes));
    expect(rows, hasLength(1));
    expect(rows.single.status, ImportStatus.skipped);
  });

  test('.xlsx with shared strings and a numeric NIK cell', () {
    final bytes = File(
      'test/fixtures/import_sample.xlsx',
    ).readAsBytesSync();
    final rows = UserImport.parse(Uint8List.fromList(bytes));
    expect(rows, hasLength(2));
    // Numeric NIK cell 90692 normalises to the plain integer string.
    expect(rows[0].employeeNumber, '90692');
    expect(rows[0].status, ImportStatus.ready);
    // Text NIK with a leading zero is preserved exactly.
    expect(rows[1].employeeNumber, '060392');
    expect(rows[1].role, 'it_support');
    expect(rows[1].fullName, 'Budi Santoso');
    expect(rows[1].line, 3);
  });

  test('corrupt .xlsx bytes raise a format error', () {
    expect(
      () => UserImport.parse(Uint8List.fromList(utf8.encode('PK\x03\x04garbage'))),
      throwsFormatException,
    );
  });
}
