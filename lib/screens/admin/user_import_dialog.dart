import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tickets_provider.dart';
import '../../utils/browser_files.dart' show downloadBytes, pickFiles;
import '../../utils/error_messages.dart';
import '../../utils/formatters.dart';
import '../../utils/user_import.dart';
import '../../widgets/common.dart';

const String kUserTemplateFileName = 'template-import-user-itsr.csv';

Future<void> downloadUserTemplate(BuildContext context) async {
  await downloadBytes(
    UserImport.templateBytes(),
    kUserTemplateFileName,
    'text/csv',
  );
  if (context.mounted) {
    showSnack(context, 'Template diunduh: $kUserTemplateFileName');
  }
}

/// Administrator: import many users at once from a CSV file.
class UserImportDialog extends ConsumerStatefulWidget {
  const UserImportDialog({super.key});

  @override
  ConsumerState<UserImportDialog> createState() => _UserImportDialogState();
}

class _UserImportDialogState extends ConsumerState<UserImportDialog> {
  String? _fileName;
  List<ImportRow>? _rows;
  String? _error;
  bool _running = false;
  bool _done = false;
  int _progress = 0;

  int _count(ImportStatus s) => _rows?.where((r) => r.status == s).length ?? 0;

  Future<void> _pick() async {
    final files = await pickFiles(
      accept: '.csv,text/csv,text/plain',
      multiple: false,
    );
    if (files.isEmpty || !mounted) return;
    final users = await ref
        .read(usersProvider.future)
        .catchError((_) => const <Never>[]);
    try {
      final rows = UserImport.parse(
        files.first.bytes,
        existingEmployeeNumbers: {for (final u in users) u.employeeNumber},
        existingEmails: {for (final u in users) u.email},
      );
      setState(() {
        _fileName = files.first.name;
        _rows = rows;
        _error = null;
        _done = false;
      });
    } on FormatException catch (e) {
      setState(() {
        _fileName = files.first.name;
        _rows = null;
        _error = e.message;
      });
    }
  }

  Future<void> _import() async {
    final rows = _rows!;
    setState(() {
      _running = true;
      _progress = 0;
    });
    final repo = ref.read(adminRepositoryProvider);
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r.status != ImportStatus.ready) continue;
      ImportRow result;
      try {
        await repo.createUser(
          employeeNumber: r.employeeNumber,
          fullName: r.fullName,
          email: r.email,
          department: r.department,
          role: r.role,
          phoneNumber: r.phoneNumber,
          password: r.password,
        );
        result = r.withStatus(ImportStatus.created, 'Berhasil dibuat');
      } catch (e) {
        result = r.withStatus(ImportStatus.failed, friendlyError(e));
      }
      if (!mounted) return;
      setState(() {
        rows[i] = result;
        _progress++;
      });
    }
    ref.invalidate(usersProvider);
    ref.invalidate(assignableStaffProvider);
    if (!mounted) return;
    setState(() {
      _running = false;
      _done = true;
    });
    showSnack(
      context,
      'Import selesai: ${_count(ImportStatus.created)} berhasil, '
      '${_count(ImportStatus.failed)} gagal',
      error: _count(ImportStatus.failed) > 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final ready = _count(ImportStatus.ready);
    final total = rows == null ? 0 : ready + _progress;
    return AlertDialog(
      title: const Text('Import pengguna'),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '1. Unduh template CSV dan isi satu baris per pengguna '
              '(Role: employee, it_support, atau administrator).\n'
              '2. Simpan sebagai CSV, lalu pilih file di sini.\n'
              '3. Periksa hasil validasi, kemudian klik Import.',
              style: TextStyle(height: 1.5),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const Key('download_user_template'),
                  onPressed: _running
                      ? null
                      : () => downloadUserTemplate(context),
                  icon: const Icon(Icons.download),
                  label: const Text('Unduh template'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('pick_import_file'),
                  onPressed: _running ? null : _pick,
                  icon: const Icon(Icons.upload_file),
                  label: Text(
                    _fileName == null ? 'Pilih file CSV' : 'Ganti file',
                  ),
                ),
              ],
            ),
            if (_fileName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'File: $_fileName',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Colors.red[700])),
              ),
            if (rows != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip('Siap', ready, Colors.blue),
                  _Chip(
                    'Tidak valid',
                    _count(ImportStatus.invalid),
                    Colors.orange,
                  ),
                  if (_count(ImportStatus.skipped) > 0)
                    _Chip(
                      'Dilewati',
                      _count(ImportStatus.skipped),
                      Colors.grey,
                    ),
                  if (_running || _done) ...[
                    _Chip(
                      'Berhasil',
                      _count(ImportStatus.created),
                      Colors.green,
                    ),
                    _Chip('Gagal', _count(ImportStatus.failed), Colors.red),
                  ],
                ],
              ),
              if (_running) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: total == 0 ? null : _progress / total,
                ),
              ],
              const SizedBox(height: 8),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _RowTile(rows[i]),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: Text(_done ? 'Tutup' : 'Batal'),
        ),
        if (!_done)
          FilledButton.icon(
            key: const Key('run_user_import'),
            onPressed: _running || ready == 0 ? null : _import,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.group_add),
            label: Text('Import $ready pengguna'),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$label: $count',
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

class _RowTile extends StatelessWidget {
  const _RowTile(this.r);
  final ImportRow r;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (r.status) {
      ImportStatus.ready => (Icons.radio_button_unchecked, Colors.blue),
      ImportStatus.invalid => (Icons.error_outline, Colors.orange),
      ImportStatus.skipped => (Icons.remove_circle_outline, Colors.grey),
      ImportStatus.created => (Icons.check_circle, Colors.green),
      ImportStatus.failed => (Icons.cancel, Colors.red),
    };
    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(
        '${r.employeeNumber.isEmpty ? '—' : r.employeeNumber} · '
        '${r.fullName.isEmpty ? '—' : r.fullName}',
      ),
      subtitle: Text(
        'Baris ${r.line} · ${r.email} · '
        '${r.role.isEmpty ? r.rawRole : Fmt.role(r.role)}'
        '${r.message == null ? '' : '\n${r.message}'}',
      ),
      isThreeLine: r.message != null,
    );
  }
}
