import 'package:flutter_test/flutter_test.dart';
import 'package:itsr_radiant/models/user_import.dart';
import 'package:itsr_radiant/utils/xlsx_lite.dart';

import '../support/fakes.dart';

void main() {
  test('template is a readable .xlsx with the data sheet and headers', () {
    final bytes = UserImport.template();
    final rows = readXlsx(bytes, preferredSheet: UserImport.dataSheet);
    expect(rows.first, ['employee_number*', 'full_name*', 'email*', 'department', 'role*', 'phone_number', 'password*']);
    expect(rows.length, 1, reason: 'no example rows that could be imported by mistake');
    final help = readXlsx(bytes, preferredSheet: 'Petunjuk');
    expect(help.first.first, 'Kolom');
  });

  test('xlsx round trip keeps leading zeros and text', () {
    final bytes = buildXlsx([
      const XlsxSheet('Data Karyawan', [
        ['employee_number', 'full_name', 'email', 'role', 'password'],
        ['03233', 'Siti & "Ani"', 'siti@x.test', 'employee', '0123'],
      ], textColumns: true),
    ]);
    final rows = readXlsx(bytes);
    expect(rows[1], ['03233', 'Siti & "Ani"', 'siti@x.test', 'employee', '0123']);
  });

  test('rows are validated: policy, roles, duplicates in file and in the system', () {
    final existing = [user('u1', 'employee')]; // employee number U1, email u1@example.test
    final table = [
      ['NIK', 'Nama', 'Email', 'Departemen', 'Role', 'No HP', 'PIN'],
      ['emp010', 'Andi Pratama', 'Andi@Kantor.test', 'Marketing', 'karyawan', '0812', '12345'],
      ['EMP011', 'Rudi', 'rudi@kantor.test', '', 'teknisi', '', 'longpassword'],
      ['EMP012', 'Bad Role', 'bad@kantor.test', 'IT', 'superuser', '', '1234'],
      ['EMP013', 'Short PW', 'pw@kantor.test', 'IT', 'admin', '', '123456'],
      ['EMP010', 'Dup', 'dup@kantor.test', 'IT', 'employee', '', '1234'],
      ['U1', 'Existing', 'u1@example.test', 'IT', 'employee', '', '1234'],
      ['', '', '', '', '', '', ''],
    ];
    final rows = UserImport.parse(table, existing);
    expect(rows.length, 6, reason: 'blank lines skipped');
    expect(rows[0].isValid, isTrue);
    expect(rows[0].employeeNumber, 'EMP010');
    expect(rows[0].email, 'andi@kantor.test');
    expect(rows[0].role, 'employee');
    expect(rows[1].isValid, isTrue);
    expect(rows[1].role, 'it_support');
    expect(rows[1].department, 'General');
    expect(rows[2].errors.join(), contains('Role'));
    expect(rows[3].errors.join(), contains('Password'));
    expect(rows[4].errors.join(), contains('ganda di file'));
    expect(rows[5].errors.join(), contains('sudah terdaftar'));
    expect(rows[0].line, 2);
  });

  test('missing required columns are reported', () {
    expect(() => UserImport.parse([['nama', 'email']], const []), throwsFormatException);
  });

  test('CSV with semicolons and quotes', () {
    final rows = readCsv('﻿employee_number;full_name;email;role;password\n03233;"Doe; John";j@x.test;employee;1234\n');
    expect(rows[1], ['03233', 'Doe; John', 'j@x.test', 'employee', '1234']);
  });
}
