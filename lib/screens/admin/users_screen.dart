import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_constants.dart';
import '../../models/user_import.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/browser_files.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatters.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import '../../widgets/employee_ui.dart';

/// "5. Manajemen Karyawan": employees, IT Support staff and administrators,
/// with role tabs, search, department / status filters, bulk import from the
/// Excel template, add / edit / reset password / (de)activate.
/// All writes go through the `admin-users` Edge Function, which re-checks the
/// caller's administrator role server-side.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _query = '';
  String? _role;
  String? _dept;
  bool? _active;

  Future<void> _downloadTemplate() async {
    await downloadBytes(UserImport.template(), 'template-import-karyawan.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    if (mounted) showSnack(context, 'Template diunduh: template-import-karyawan.xlsx');
  }

  Future<void> _import(List<UserModel> existing) async {
    final files = await pickFiles(
      accept: '.xlsx,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv',
      multiple: false,
    );
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    List<ImportRow> rows;
    try {
      rows = UserImport.parse(UserImport.readFile(f.name, f.bytes), existing);
    } on FormatException catch (e) {
      showSnack(context, e.message, error: true);
      return;
    }
    if (rows.isEmpty) {
      showSnack(context, 'Tidak ada baris data di ${f.name}', error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportDialog(fileName: f.name, rows: rows),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final desktop = isDesktop(context);
    final list = users.valueOrNull ?? const <UserModel>[];
    final departments = {for (final u in list) u.department}.toList()..sort();
    final roleTabs = <(String, String?)>[
      ('Semua', null),
      ('Karyawan', AppConstants.roleEmployee),
      ('IT Support', AppConstants.roleITSupport),
      ('Administrator', AppConstants.roleAdministrator),
    ];

    final actions = Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(
        key: const Key('download_import_template'),
        onPressed: _downloadTemplate,
        icon: const Icon(Icons.description_outlined),
        label: const Text('Template Import'),
      ),
      OutlinedButton.icon(
        key: const Key('import_users_button'),
        onPressed: users.hasValue ? () => _import(list) : null,
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Import Karyawan'),
      ),
      FilledButton.icon(
        key: const Key('add_user_button'),
        style: FilledButton.styleFrom(backgroundColor: EColors.blue),
        onPressed: () => showDialog(context: context, builder: (_) => const _UserDialog()),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Tambah Karyawan'),
      ),
    ]);

    Widget dropdown<T>(Key key, String hint, T? value, List<(T, String)> options, ValueChanged<T?> onChanged) =>
        SizedBox(
          width: desktop ? 200 : double.infinity,
          child: DropdownButtonFormField<T?>(
            key: key,
            initialValue: value,
            isExpanded: true,
            decoration: eInput(),
            hint: Text(hint, style: const TextStyle(fontSize: 13.5)),
            items: [
              DropdownMenuItem<T?>(value: null, child: Text(hint, style: const TextStyle(fontSize: 13.5))),
              for (final (v, l) in options)
                DropdownMenuItem<T?>(value: v, child: Text(l, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: onChanged,
          ),
        );

    final search = TextField(
      key: const Key('users_search'),
      decoration: eInput(
        hint: 'Cari nama, employee number, email, atau departemen…',
        prefix: const Icon(Icons.search, color: EColors.muted),
      ),
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
    );
    final filters = [
      dropdown<String>(const Key('filter_department'), 'Semua Departemen', _dept,
          [for (final d in departments) (d, d)], (v) => setState(() => _dept = v)),
      dropdown<bool>(const Key('filter_status'), 'Semua Status', _active,
          const [(true, 'Aktif'), (false, 'Nonaktif')], (v) => setState(() => _active = v)),
    ];

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(usersProvider),
      child: ListView(
        padding: EdgeInsets.all(desktop ? 24 : 16),
        children: [
          if (!desktop) const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            spacing: 12,
            children: [
              const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Manajemen Karyawan',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: EColors.ink)),
                SizedBox(height: 2),
                Text('Kelola data karyawan dan akun akses aplikasi',
                    style: TextStyle(color: EColors.muted, fontSize: 13)),
              ]),
              actions,
            ],
          ),
          const SizedBox(height: 16),
          ECard(
            padding: EdgeInsets.all(desktop ? 18 : 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final (label, role) in roleTabs) ...[
                    ESegment(
                      key: Key('role_tab_$label'),
                      label: label,
                      count: users.hasValue ? list.where((u) => role == null || u.role == role).length : null,
                      selected: _role == role,
                      onTap: () => setState(() => _role = role),
                    ),
                    const SizedBox(width: 8),
                  ],
                ]),
              ),
              const SizedBox(height: 14),
              if (desktop)
                Row(children: [
                  Expanded(child: search),
                  for (final f in filters) ...[const SizedBox(width: 10), f],
                ])
              else ...[
                search,
                const SizedBox(height: 10),
                for (final f in filters) ...[f, const SizedBox(height: 8)],
              ],
              const SizedBox(height: 14),
              users.when(
                loading: () => const SizedBox(height: 200, child: LoadingView()),
                error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(usersProvider)),
                data: (all) {
                  final filtered = all.where((u) {
                    if (_role != null && u.role != _role) return false;
                    if (_dept != null && u.department != _dept) return false;
                    if (_active != null && u.isActive != _active) return false;
                    if (_query.isEmpty) return true;
                    return [u.fullName, u.employeeNumber, u.email, u.department]
                        .any((f) => f.toLowerCase().contains(_query));
                  }).toList();
                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: EmptyView(icon: Icons.people_outline, title: 'Tidak ada karyawan yang cocok'),
                    );
                  }
                  if (desktop) return _UsersTable(users: filtered, meId: me?.id);
                  return Column(children: [
                    for (final u in filtered) ...[_UserTile(user: u, isMe: u.id == me?.id), const SizedBox(height: 8)],
                  ]);
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row actions shared by the desktop table and the phone cards.
Future<void> _toggleActive(BuildContext context, WidgetRef ref, UserModel user) async {
  final activate = !user.isActive;
  final ok = await showConfirmDialog(
    context,
    title: activate ? 'Aktifkan karyawan' : 'Nonaktifkan karyawan',
    message: activate
        ? 'Izinkan ${user.fullName} masuk lagi?'
        : '${user.fullName} tidak akan bisa masuk. Tiket dan riwayatnya tetap disimpan.',
    confirmLabel: activate ? 'Aktifkan' : 'Nonaktifkan',
    destructive: !activate,
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(adminActionsProvider).updateUser(user.id, {'is_active': activate});
    if (context.mounted) showSnack(context, activate ? 'Karyawan diaktifkan' : 'Karyawan dinonaktifkan');
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e), error: true);
  }
}

Future<void> _resetPassword(BuildContext context, WidgetRef ref, UserModel user) async {
  final pw = await showDialog<String>(context: context, builder: (_) => const _PasswordDialog());
  if (pw == null || !context.mounted) return;
  try {
    await ref.read(adminActionsProvider).resetPassword(user.id, pw);
    if (context.mounted) {
      showSnack(context, 'Password direset. Sampaikan password baru ke ${user.fullName} secara pribadi.');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, friendlyError(e), error: true);
  }
}

Widget _statusTag(UserModel u) =>
    u.isActive ? const ETag('Aktif', EColors.green) : const ETag('Nonaktif', EColors.red);

class _UserActions extends ConsumerWidget {
  const _UserActions({required this.user, required this.isMe});
  final UserModel user;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: 'Edit ${user.fullName}',
          visualDensity: VisualDensity.compact,
          onPressed: () => showDialog(context: context, builder: (_) => _UserDialog(existing: user)),
          icon: const Icon(Icons.edit_outlined, size: 20, color: EColors.text),
        ),
        IconButton(
          tooltip: 'Reset password',
          visualDensity: VisualDensity.compact,
          onPressed: () => _resetPassword(context, ref, user),
          icon: const Icon(Icons.key_outlined, size: 20, color: EColors.text),
        ),
        PopupMenuButton<String>(
          tooltip: 'Aksi lainnya',
          icon: const Icon(Icons.more_vert, size: 20, color: EColors.text),
          onSelected: (v) {
            if (v == 'active') _toggleActive(context, ref, user);
          },
          itemBuilder: (_) => [
            if (!isMe)
              PopupMenuItem(value: 'active', child: Text(user.isActive ? 'Nonaktifkan' : 'Aktifkan')),
            if (isMe) const PopupMenuItem(enabled: false, child: Text('Akun Anda sendiri')),
          ],
        ),
      ]);
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({required this.users, required this.meId});
  final List<UserModel> users;
  final String? meId;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: EColors.ink);
    const cell = TextStyle(fontSize: 13, color: EColors.text);
    return LayoutBuilder(builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: DataTable(
              headingRowHeight: 42,
              dataRowMinHeight: 52,
              dataRowMaxHeight: 58,
              horizontalMargin: 12,
              columnSpacing: 20,
              headingRowColor: const WidgetStatePropertyAll(Color(0xFFF8FAFC)),
              border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFFF1F5F9))),
              columns: const [
                DataColumn(label: Text('Employee No.', style: head)),
                DataColumn(label: Text('Nama', style: head)),
                DataColumn(label: Text('Departemen', style: head)),
                DataColumn(label: Text('Role', style: head)),
                DataColumn(label: Text('Status', style: head)),
                DataColumn(label: Text('Aksi', style: head)),
              ],
              rows: [
                for (final u in users)
                  DataRow(cells: [
                    DataCell(Text(u.employeeNumber, style: cell.copyWith(fontWeight: FontWeight.w600))),
                    DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                      InitialsAvatar(u.fullName, size: 32),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${u.fullName}${u.id == meId ? ' (Anda)' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: cell.copyWith(color: EColors.ink, fontWeight: FontWeight.w600)),
                          Text(u.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: EColors.muted)),
                        ]),
                      ),
                    ])),
                    DataCell(Text(u.department, style: cell)),
                    DataCell(Text(Fmt.role(u.role), style: cell)),
                    DataCell(_statusTag(u)),
                    DataCell(_UserActions(user: u, isMe: u.id == meId)),
                  ]),
              ],
            ),
          ),
        ));
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.isMe});
  final UserModel user;
  final bool isMe;

  @override
  Widget build(BuildContext context) => ECard(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(children: [
          InitialsAvatar(user.fullName, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${user.fullName}${isMe ? ' (Anda)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: EColors.ink)),
              const SizedBox(height: 2),
              Text('${user.employeeNumber} · ${Fmt.role(user.role)} · ${user.department}',
                  style: const TextStyle(fontSize: 12, color: EColors.muted)),
              const SizedBox(height: 4),
              _statusTag(user),
            ]),
          ),
          _UserActions(user: user, isMe: isMe),
        ]),
      );
}

// ---------------------------------------------------------------------------
/// Preview + run of a bulk import.
class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog({required this.fileName, required this.rows});
  final String fileName;
  final List<ImportRow> rows;

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  bool _running = false;
  bool _done = false;
  int _progress = 0;
  final Map<int, String> _failed = {}; // line -> reason
  final Set<int> _created = {};

  List<ImportRow> get _valid => widget.rows.where((r) => r.isValid).toList();

  Future<void> _run() async {
    setState(() => _running = true);
    final actions = ref.read(adminActionsProvider);
    for (final r in _valid) {
      if (!mounted) return;
      try {
        await actions.createUser(
          employeeNumber: r.employeeNumber,
          fullName: r.fullName,
          email: r.email,
          department: r.department,
          role: r.role,
          phoneNumber: r.phone,
          password: r.password,
          refresh: false,
        );
        _created.add(r.line);
      } catch (e) {
        _failed[r.line] = friendlyError(e);
      }
      if (mounted) setState(() => _progress++);
    }
    ref.invalidate(usersProvider);
    if (mounted) {
      setState(() {
        _running = false;
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _valid.length;
    final invalid = widget.rows.length - valid;
    return AlertDialog(
      title: Text(_done ? 'Hasil Import' : 'Pratinjau Import'),
      content: SizedBox(
        width: 720,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            _done
                ? '${_created.length} akun dibuat, ${_failed.length} gagal, $invalid dilewati (data tidak valid).'
                : '${widget.fileName}: ${widget.rows.length} baris · $valid siap diimport · $invalid bermasalah.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (_running) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: valid == 0 ? null : _progress / valid),
            const SizedBox(height: 4),
            Text('Membuat akun $_progress dari $valid…', style: const TextStyle(fontSize: 12, color: EColors.muted)),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: ListView.separated(
              itemCount: widget.rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = widget.rows[i];
                final (color, label, detail) = _created.contains(r.line)
                    ? (EColors.green, 'Dibuat', '')
                    : _failed.containsKey(r.line)
                        ? (EColors.red, 'Gagal', _failed[r.line]!)
                        : r.isValid
                            ? (EColors.blue, 'Siap', '')
                            : (EColors.amber, 'Dilewati', r.errors.join(' · '));
                return ListTile(
                  dense: true,
                  leading: Text('#${r.line}', style: const TextStyle(color: EColors.muted)),
                  title: Text(
                    '${r.employeeNumber.isEmpty ? '—' : r.employeeNumber} · ${r.fullName.isEmpty ? '—' : r.fullName}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [r.email, Fmt.role(r.role), r.department, if (detail.isNotEmpty) detail].join(' · '),
                    style: TextStyle(color: detail.isNotEmpty ? color : EColors.muted),
                  ),
                  trailing: ETag(label, color),
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context),
          child: Text(_done ? 'Tutup' : 'Batal'),
        ),
        if (!_done)
          FilledButton(
            key: const Key('run_import_button'),
            onPressed: _running || valid == 0 ? null : _run,
            child: Text('Import $valid akun'),
          ),
      ],
    );
  }
}

class _UserDialog extends ConsumerStatefulWidget {
  const _UserDialog({this.existing});
  final UserModel? existing;

  @override
  ConsumerState<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<_UserDialog> {
  final _form = GlobalKey<FormState>();
  late final _number = TextEditingController(text: widget.existing?.employeeNumber);
  late final _name = TextEditingController(text: widget.existing?.fullName);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _dept = TextEditingController(text: widget.existing?.department ?? 'General');
  late final _phone = TextEditingController(text: widget.existing?.phoneNumber);
  final _password = TextEditingController();
  late String _role = widget.existing?.role ?? AppConstants.roleEmployee;
  bool _busy = false;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_number, _name, _email, _dept, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final me = ref.read(currentUserProvider).valueOrNull;
    if (_editing &&
        widget.existing!.id == me?.id &&
        widget.existing!.role == AppConstants.roleAdministrator &&
        _role != AppConstants.roleAdministrator) {
      showSnack(context, 'You cannot remove your own administrator role', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final actions = ref.read(adminActionsProvider);
      if (_editing) {
        final e = widget.existing!;
        final changes = <String, dynamic>{
          if (_name.text.trim() != e.fullName) 'full_name': _name.text.trim(),
          if (_email.text.trim().toLowerCase() != e.email) 'email': _email.text.trim().toLowerCase(),
          if (_dept.text.trim() != e.department) 'department': _dept.text.trim(),
          if (_phone.text.trim() != (e.phoneNumber ?? '')) 'phone_number': _phone.text.trim(),
          if (_role != e.role) 'role': _role,
        };
        if (changes.isNotEmpty) await actions.updateUser(e.id, changes);
      } else {
        await actions.createUser(
          employeeNumber: Validators.normalizeEmployeeNumber(_number.text),
          fullName: _name.text.trim(),
          email: _email.text.trim().toLowerCase(),
          department: _dept.text.trim(),
          role: _role,
          phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          password: _password.text,
        );
      }
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, _editing ? 'User updated' : 'User created');
      }
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_editing ? 'Edit user' : 'Add user'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _number,
                    enabled: !_editing && !_busy,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Employee number *'),
                    validator: Validators.employeeNumber,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Full name *'),
                    validator: (v) => Validators.requiredText(v, 'Full name'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email (used for notifications) *'),
                    validator: Validators.email,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _dept,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Department *'),
                    validator: (v) => Validators.requiredText(v, 'Department', max: 80),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phone,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone (optional)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Role *'),
                    items: [
                      for (final r in AppConstants.roles)
                        DropdownMenuItem(value: r, child: Text(Fmt.role(r))),
                    ],
                    onChanged: _busy ? null : (v) => setState(() => _role = v!),
                  ),
                  if (!_editing) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Initial password *',
                        helperText: 'A 4–5 digit PIN or at least 8 characters. Share it securely.',
                      ),
                      validator: Validators.newPassword,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_editing ? 'Save' : 'Create'),
          ),
        ],
      );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Reset password'),
        content: SizedBox(
          width: 400,
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _pw,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'A 4–5 digit PIN or at least 8 characters',
                ),
                validator: Validators.newPassword,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pw2,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repeat new password'),
                validator: (v) => v != _pw.text ? 'Passwords do not match' : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) Navigator.pop(context, _pw.text);
            },
            child: const Text('Reset'),
          ),
        ],
      );
}
