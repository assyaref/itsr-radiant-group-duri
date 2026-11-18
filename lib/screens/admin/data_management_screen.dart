import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/admin_provider.dart';
import '../../utils/browser_files.dart' show downloadBytes, pickFiles;
import '../../utils/error_messages.dart';
import '../../widgets/common.dart';

/// Phrase the administrator must type before all ticket data is deleted.
/// The `admin_purge_tickets` RPC checks the same phrase server-side.
const String kPurgeConfirmPhrase = 'HAPUS SEMUA DATA';

/// Phrase required by the `admin_restore` RPC.
const String kRestoreConfirmPhrase = 'RESTORE DATA';

/// Administrator + Superadmin: download a JSON backup of the database and
/// delete all ticket data. Both actions are re-authorized by the database.
class DataManagementScreen extends ConsumerStatefulWidget {
  const DataManagementScreen({super.key});

  @override
  ConsumerState<DataManagementScreen> createState() =>
      _DataManagementScreenState();
}

class _DataManagementScreenState extends ConsumerState<DataManagementScreen> {
  bool _busy = false;
  String? _lastBackup;

  Future<bool> _backup() async {
    setState(() => _busy = true);
    try {
      final data = await ref.read(adminActionsProvider).exportBackup();
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final name =
          'itsr-backup-${now.year}${two(now.month)}${two(now.day)}-'
          '${two(now.hour)}${two(now.minute)}.json';
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
      );
      await downloadBytes(bytes, name, 'application/json');
      final tables = (data['tables'] as Map?) ?? const {};
      final tickets = (tables['tickets'] as List?)?.length ?? 0;
      if (!mounted) return true;
      setState(() => _lastBackup = '$name · $tickets tiket');
      showSnack(context, 'Backup diunduh: $name');
      return true;
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purge() async {
    final ok = await showDialog<_PurgeChoice>(
      context: context,
      builder: (_) => const _PurgeDialog(),
    );
    if (ok == null || !mounted) return;
    if (ok.backupFirst && !await _backup()) return;
    setState(() => _busy = true);
    try {
      final res = await ref
          .read(adminActionsProvider)
          .purgeTickets(kPurgeConfirmPhrase);
      if (!mounted) return;
      showSnack(
        context,
        'Data dihapus: ${res['tickets']} tiket, ${res['comments']} komentar, '
        '${res['attachments']} lampiran',
      );
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final files = await pickFiles(
      accept: '.json,application/json',
      multiple: false,
    );
    if (files.isEmpty || !mounted) return;
    final Map<String, dynamic> backup;
    try {
      final decoded = jsonDecode(utf8.decode(files.first.bytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != 'itsr-backup' ||
          decoded['tables'] is! Map) {
        throw const FormatException();
      }
      backup = decoded;
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'File ini bukan backup ITSR yang valid',
          error: true,
        );
      }
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<_RestoreChoice>(
      context: context,
      builder: (_) =>
          _RestoreDialog(fileName: files.first.name, backup: backup),
    );
    if (choice == null || !mounted) return;
    if (choice.backupFirst && !await _backup()) return;
    setState(() => _busy = true);
    try {
      final res = await ref
          .read(adminActionsProvider)
          .restoreBackup(
            backup,
            mode: choice.mode,
            confirmPhrase: kRestoreConfirmPhrase,
          );
      if (!mounted) return;
      final skipped = res['skipped_tickets'] ?? 0;
      showSnack(
        context,
        'Restore selesai: ${res['tickets']} tiket, ${res['comments']} '
        'komentar, ${res['attachments']} lampiran dipulihkan'
        '${skipped == 0 ? '' : ' · $skipped tiket dilewati (pelapor tidak ada)'}',
      );
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Backup & Data',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Khusus Administrator & Super Admin. Setiap tindakan dicatat '
                  'di audit log server.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.cloud_download_outlined,
                  color: const Color(0xFF2563EB),
                  title: 'Backup database',
                  body:
                      'Unduh seluruh data aplikasi (pengguna, kategori, '
                      'tiket, komentar, aktivitas, metadata lampiran, '
                      'pengaturan) sebagai file JSON. Password dan secret '
                      'SMTP tidak ikut tersimpan.',
                  footer: _lastBackup == null
                      ? null
                      : 'Backup terakhir: $_lastBackup',
                  button: FilledButton.icon(
                    key: const Key('backup_button'),
                    onPressed: _busy ? null : _backup,
                    icon: const Icon(Icons.download),
                    label: const Text('Unduh backup'),
                  ),
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.settings_backup_restore,
                  color: const Color(0xFF059669),
                  title: 'Restore database',
                  body:
                      'Pulihkan kategori, tiket, komentar, aktivitas, dan '
                      'data lampiran dari file backup JSON. Akun pengguna dan '
                      'pengaturan tidak diubah, dan tidak ada email '
                      'notifikasi yang dikirim.',
                  button: FilledButton.icon(
                    key: const Key('restore_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                    ),
                    onPressed: _busy ? null : _restore,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Pilih file backup…'),
                  ),
                ),
                const SizedBox(height: 16),
                _ActionCard(
                  icon: Icons.delete_forever_outlined,
                  color: const Color(0xFFDC2626),
                  title: 'Hapus database tiket',
                  body:
                      'Menghapus PERMANEN semua tiket beserta komentar, '
                      'riwayat aktivitas, data lampiran, dan antrean email. '
                      'Akun pengguna, kategori, dan pengaturan tetap ada. '
                      'Tindakan ini tidak dapat dibatalkan.',
                  button: FilledButton.icon(
                    key: const Key('purge_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                    onPressed: _busy ? null : _purge,
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Hapus semua data tiket'),
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.button,
    this.footer,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget button;
  final String? footer;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: color.withValues(alpha: 0.25)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(body, style: const TextStyle(height: 1.45)),
                if (footer != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    footer!,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 12),
                button,
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _RestoreChoice {
  const _RestoreChoice({required this.mode, required this.backupFirst});
  final String mode; // merge | replace
  final bool backupFirst;
}

/// Shows what is in the backup, lets the admin pick merge/replace and
/// requires typing [kRestoreConfirmPhrase].
class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.fileName, required this.backup});
  final String fileName;
  final Map<String, dynamic> backup;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final _text = TextEditingController();
  String _mode = 'merge';
  bool _backupFirst = true;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int _n(String table) =>
      ((widget.backup['tables'] as Map)[table] as List?)?.length ?? 0;

  @override
  Widget build(BuildContext context) {
    final matches = _text.text.trim() == kRestoreConfirmPhrase;
    final when = widget.backup['generated_at']?.toString() ?? '-';
    final by = widget.backup['generated_by']?.toString() ?? '-';
    return AlertDialog(
      icon: const Icon(Icons.settings_backup_restore, color: Color(0xFF059669)),
      title: const Text('Restore dari backup'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${widget.fileName}\n'
                  'Dibuat: $when\nOleh: $by\n'
                  '${_n('tickets')} tiket · ${_n('ticket_comments')} komentar · '
                  '${_n('ticket_activity_log')} aktivitas · '
                  '${_n('ticket_attachments')} lampiran · '
                  '${_n('categories')} kategori',
                  style: const TextStyle(height: 1.5, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _mode,
                onChanged: (v) => setState(() => _mode = v ?? 'merge'),
                child: const Column(
                  children: [
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: 'merge',
                      title: Text('Gabungkan'),
                      subtitle: Text(
                        'Hanya menambah data yang belum ada. Data sekarang tetap.',
                      ),
                    ),
                    RadioListTile<String>(
                      key: Key('restore_mode_replace'),
                      contentPadding: EdgeInsets.zero,
                      value: 'replace',
                      title: Text('Ganti semua'),
                      subtitle: Text(
                        'Hapus SEMUA data tiket sekarang, lalu isi dari backup.',
                      ),
                    ),
                  ],
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _backupFirst,
                onChanged: (v) => setState(() => _backupFirst = v ?? true),
                title: const Text('Unduh backup data sekarang terlebih dahulu'),
              ),
              const SizedBox(height: 4),
              const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: 'Ketik '),
                    TextSpan(
                      text: kRestoreConfirmPhrase,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: ' untuk melanjutkan:'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('restore_confirm_field'),
                controller: _text,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(isDense: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('restore_confirm_button'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF059669),
          ),
          onPressed: matches
              ? () => Navigator.pop(
                  context,
                  _RestoreChoice(mode: _mode, backupFirst: _backupFirst),
                )
              : null,
          child: const Text('Restore'),
        ),
      ],
    );
  }
}

class _PurgeChoice {
  const _PurgeChoice({required this.backupFirst});
  final bool backupFirst;
}

/// Requires typing [kPurgeConfirmPhrase] exactly before the button enables.
class _PurgeDialog extends StatefulWidget {
  const _PurgeDialog();

  @override
  State<_PurgeDialog> createState() => _PurgeDialogState();
}

class _PurgeDialogState extends State<_PurgeDialog> {
  final _text = TextEditingController();
  bool _backupFirst = true;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _text.text.trim() == kPurgeConfirmPhrase;
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
      title: const Text('Hapus semua data tiket?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Semua tiket, komentar, aktivitas, dan data lampiran akan '
              'dihapus permanen.',
            ),
            const SizedBox(height: 12),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Ketik '),
                  TextSpan(
                    text: kPurgeConfirmPhrase,
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: ' untuk melanjutkan:'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('purge_confirm_field'),
              controller: _text,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(isDense: true),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _backupFirst,
              onChanged: (v) => setState(() => _backupFirst = v ?? true),
              title: const Text('Unduh backup terlebih dahulu'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('purge_confirm_button'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
          ),
          onPressed: matches
              ? () => Navigator.pop(
                  context,
                  _PurgeChoice(backupFirst: _backupFirst),
                )
              : null,
          child: const Text('Hapus permanen'),
        ),
      ],
    );
  }
}
