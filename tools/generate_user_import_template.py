#!/usr/bin/env python3
"""Generates the user-import Excel template and a parser test fixture.

No third-party packages required (an .xlsx is a zip of XML files).

Outputs
  assets/templates/template-import-user-itsr.xlsx  - what admins download
  test/fixtures/import_sample.xlsx                 - reader test fixture

The template stores every value as inline text (NIK and phone columns use the
@ text number format) so leading zeros in NIKs survive Excel round-trips.
The fixture instead uses a sharedStrings table plus one *numeric* NIK cell,
which exercises the other two cell encodings the importer understands.
"""

import os
import sys
import zipfile
from xml.sax.saxutils import escape

HEADERS = ['NIK', 'Nama Lengkap', 'Email', 'Departemen', 'Role', 'No HP', 'Password']
EXAMPLE = [
    'CONTOH01',
    'Contoh Nama Karyawan',
    'nama@domain-perusahaan',
    'Operasional',
    'employee',
    '081234567890',
    'PasswordAwal123',
]
COL_WIDTHS = [16, 28, 34, 20, 18, 20, 22]
# 1-based columns forced to text format (@) so NIK keeps leading zeros
TEXT_COLS = (1, 6)

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
{extra_overrides}</Types>
"""

ROOT_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
"""

WORKBOOK = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Import Pengguna" sheetId="1" r:id="rId1"/></sheets>
</workbook>
"""

WORKBOOK_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
{extra_rels}</Relationships>
"""

STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="1"><numFmt numFmtId="164" formatCode="@"/></numFmts>
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFDDEBF7"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="1" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
"""


def col_letter(index0: int) -> str:
    out = ''
    n = index0 + 1
    while n:
        n, rem = divmod(n - 1, 26)
        out = chr(65 + rem) + out
    return out


def sheet_xml(rows, shared):
    """rows: list of list of (value, is_numeric). shared: list or None."""
    lines = [
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
        f'  <dimension ref="A1:{col_letter(len(HEADERS) - 1)}{len(rows)}"/>',
        '  <sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>',
        '  <sheetFormatPr defaultRowHeight="15"/>',
        '  <cols>'
        + ''.join(f'<col min="{i + 1}" max="{i + 1}" width="{w}" customWidth="1"/>'
                  for i, w in enumerate(COL_WIDTHS))
        + '</cols>',
        '  <sheetData>',
    ]
    for r_idx, row in enumerate(rows, start=1):
        cells = [f'    <row r="{r_idx}">']
        for c_idx, (value, is_numeric) in enumerate(row):
            ref = f'{col_letter(c_idx)}{r_idx}'
            col = c_idx + 1
            if r_idx == 1:
                text = escape(str(value))
                cells.append(f'      <c r="{ref}" s="1" t="inlineStr"><is><t>{text}</t></is></c>')
                continue
            if is_numeric:
                cells.append(f'      <c r="{ref}"><v>{escape(str(value))}</v></c>')
            elif shared is not None:
                cells.append(f'      <c r="{ref}" t="s"><v>{shared.index(str(value))}</v></c>')
            else:
                style = ' s="2"' if col in TEXT_COLS else ''
                text = escape(str(value))
                cells.append(f'      <c r="{ref}"{style} t="inlineStr"><is><t>{text}</t></is></c>')
        cells.append('    </row>')
        lines.append('\n'.join(cells))
    lines.append('  </sheetData>')
    lines.append(f'  <autoFilter ref="A1:{col_letter(len(HEADERS) - 1)}{len(rows)}"/>')
    lines.append('</worksheet>')
    return '\n'.join(lines)


def shared_strings_xml(strings):
    items = ''.join(f'<si><t>{escape(s)}</t></si>' for s in strings)
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        f'<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        f'count="{len(strings)}" uniqueCount="{len(strings)}">{items}</sst>'
    )


def write_xlsx(path, rows, use_shared_strings):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    strings = None
    extra_overrides = ''
    extra_rels = ''
    if use_shared_strings:
        strings = []
        for row in rows[1:]:
            for value, is_numeric in row:
                if not is_numeric and str(value) not in strings:
                    strings.append(str(value))
        extra_overrides = '  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>\n'
        extra_rels = '  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>\n'
    sheet = sheet_xml(rows, strings)
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CONTENT_TYPES.format(extra_overrides=extra_overrides))
        z.writestr('_rels/.rels', ROOT_RELS)
        z.writestr('xl/workbook.xml', WORKBOOK)
        z.writestr('xl/_rels/workbook.xml.rels', WORKBOOK_RELS.format(extra_rels=extra_rels))
        z.writestr('xl/styles.xml', STYLES)
        if strings is not None:
            z.writestr('xl/sharedStrings.xml', shared_strings_xml(strings))
        z.writestr('xl/worksheets/sheet1.xml', sheet)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    template_rows = [[(h, False) for h in HEADERS], [(v, False) for v in EXAMPLE]]
    template_path = os.path.join(root, 'assets', 'templates', 'template-import-user-itsr.xlsx')
    write_xlsx(template_path, template_rows, use_shared_strings=False)

    fixture_rows = [
        [(h, False) for h in HEADERS],
        [(90692, True), ('Adi Widyantara', False), ('adi.widyantara@radiant-utama.com', False),
         ('AIS', False), ('employee', False), ('+62 812-1562-4333', False), ('PasswordAwal123', False)],
        [('060392', False), ('Budi Santoso', False), ('budi@example.com', False),
         ('HR', False), ('IT Support', False), ('0812345678', False), ('rahasia123', False)],
    ]
    fixture_path = os.path.join(root, 'test', 'fixtures', 'import_sample.xlsx')
    write_xlsx(fixture_path, fixture_rows, use_shared_strings=True)

    print('wrote', template_path)
    print('wrote', fixture_path)


if __name__ == '__main__':
    sys.exit(main())
