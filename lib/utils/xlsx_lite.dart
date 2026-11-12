import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Minimal .xlsx writer / reader (no external spreadsheet package: the
/// `excel` package conflicts with the PDF package's xml version).
///
/// Writer: one or more sheets of plain strings, bold header row, optional
/// column widths, and columns pre-formatted as Text ("@") so that values such
/// as employee number "03233" or PIN "0123" keep their leading zeros.
/// Reader: values of one sheet (shared strings, inline strings, numbers).
class XlsxSheet {
  const XlsxSheet(this.name, this.rows, {this.widths = const [], this.textColumns = false});
  final String name;
  final List<List<String>> rows;
  final List<double> widths;

  /// Format every used column as Text, also for rows typed in later.
  final bool textColumns;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String columnName(int index) {
  var n = index + 1, s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

int _columnIndex(String ref) {
  var n = 0;
  for (final c in ref.codeUnits) {
    if (c < 65 || c > 90) break;
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

Uint8List buildXlsx(List<XlsxSheet> sheets) {
  final archive = Archive();
  void add(String path, String xml) {
    final bytes = utf8.encode(xml);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
      '${[for (var i = 0; i < sheets.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
      '</Types>');
  add('_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>');
  add('xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
      '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
      '</sheets></workbook>');
  add('xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
      '<Relationship Id="rId${sheets.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '</Relationships>');
  // Styles: 0 default, 1 bold header (blue fill, white), 2 text format "@".
  add('xl/styles.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FF2563EB"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="49" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyNumberFormat="1"/>'
      '<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
      '</styleSheet>');

  for (var i = 0; i < sheets.length; i++) {
    final sh = sheets[i];
    final colCount = sh.rows.fold<int>(sh.widths.length, (m, r) => r.length > m ? r.length : m);
    final cols = StringBuffer();
    if (colCount > 0) {
      cols.write('<cols>');
      for (var c = 0; c < colCount; c++) {
        final w = c < sh.widths.length ? sh.widths[c] : 18.0;
        cols.write('<col min="${c + 1}" max="${c + 1}" width="$w" customWidth="1"'
            '${sh.textColumns ? ' style="2"' : ''}/>');
      }
      cols.write('</cols>');
    }
    final data = StringBuffer('<sheetData>');
    for (var r = 0; r < sh.rows.length; r++) {
      data.write('<row r="${r + 1}">');
      for (var c = 0; c < sh.rows[r].length; c++) {
        final style = r == 0 ? ' s="1"' : (sh.textColumns ? ' s="2"' : '');
        data.write('<c r="${columnName(c)}${r + 1}" t="inlineStr"$style>'
            '<is><t xml:space="preserve">${_esc(sh.rows[r][c])}</t></is></c>');
      }
      data.write('</row>');
    }
    data.write('</sheetData>');
    add('xl/worksheets/sheet${i + 1}.xml',
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
        '$cols$data</worksheet>');
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Reads the sheet called [preferredSheet] (or the first sheet) of an .xlsx.
/// Throws [FormatException] when the bytes are not a readable workbook.
List<List<String>> readXlsx(Uint8List bytes, {String? preferredSheet}) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('File bukan Excel (.xlsx) yang valid');
  }
  String? text(String path) {
    final f = zip.findFile(path);
    return f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final workbook = text('xl/workbook.xml');
  if (workbook == null) throw const FormatException('File bukan Excel (.xlsx) yang valid');
  final rels = XmlDocument.parse(text('xl/_rels/workbook.xml.rels') ?? '<Relationships/>');
  final relTarget = {
    for (final r in rels.findAllElements('Relationship'))
      r.getAttribute('Id') ?? '': r.getAttribute('Target') ?? '',
  };
  final sheets = XmlDocument.parse(workbook).findAllElements('sheet').toList();
  if (sheets.isEmpty) return const [];
  final sheet = sheets.firstWhere(
    (s) => preferredSheet != null && (s.getAttribute('name') ?? '').toLowerCase() == preferredSheet.toLowerCase(),
    orElse: () => sheets.first,
  );
  var rid = '';
  for (final a in sheet.attributes) {
    if (a.name.local == 'id') rid = a.value;
  }
  var target = relTarget[rid] ?? 'worksheets/sheet1.xml';
  target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
  final sheetXml = text(target);
  if (sheetXml == null) throw const FormatException('Sheet tidak ditemukan di file Excel');

  final shared = <String>[];
  final ss = text('xl/sharedStrings.xml');
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final rows = <List<String>>[];
  for (final row in XmlDocument.parse(sheetXml).findAllElements('row')) {
    final rIndex = (int.tryParse(row.getAttribute('r') ?? '') ?? rows.length + 1) - 1;
    while (rows.length < rIndex) {
      rows.add(<String>[]);
    }
    final cells = <String>[];
    var next = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? next : _columnIndex(ref);
      next = col + 1;
      final type = c.getAttribute('t');
      String value;
      if (type == 'inlineStr') {
        value = c.findAllElements('t').map((t) => t.innerText).join();
      } else {
        final v = c.getElement('v')?.innerText ?? '';
        if (type == 's') {
          final i = int.tryParse(v);
          value = i != null && i < shared.length ? shared[i] : '';
        } else if (type == null || type == 'n') {
          final d = double.tryParse(v);
          value = d != null && d == d.roundToDouble() && d.abs() < 1e15 ? d.toInt().toString() : v;
        } else {
          value = v;
        }
      }
      while (cells.length < col) {
        cells.add('');
      }
      cells.add(value);
    }
    rows.add(cells);
  }
  return rows;
}

/// Parses CSV (comma or semicolon, auto-detected; quotes supported).
List<List<String>> readCsv(String input) {
  final text = input.startsWith('﻿') ? input.substring(1) : input;
  final firstLine = text.split(RegExp(r'\r?\n')).first;
  final sep = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? ';' : ',';
  final rows = <List<String>>[];
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
    } else if (ch == sep) {
      row.add(cell.toString());
      cell.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
    } else {
      cell.write(ch);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  return rows;
}
