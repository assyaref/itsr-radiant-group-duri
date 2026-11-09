import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_constants.dart';
import '../../models/user_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatters.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

/// Administrator: employees, roles, IT Support staff, activation, passwords.
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

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(usersProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_user_fab',
        onPressed: () => showDialog(context: context, builder: (_) => const _UserDialog()),
        icon: const Icon(Icons.person_add),
        label: const Text('Add user'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: const InputDecoration(
                      hintText: 'Search name, number, email, department',
                      prefixIcon: Icon(Icons.search),
                      isDense: true),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Role', isDense: true),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (final r in AppConstants.roles)
                      DropdownMenuItem(value: r, child: Text(Fmt.role(r))),
                  ],
                  onChanged: (v) => setState(() => _role = v),
                ),
              ),
            ]),
          ),
          Expanded(
            child: users.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(usersProvider)),
              data: (list) {
                final filtered = list.where((u) {
                  if (_role != null && u.role != _role) return false;
                  if (_query.isEmpty) return true;
                  return [u.fullName, u.employeeNumber, u.email, u.department]
                      .any((f) => f.toLowerCase().contains(_query));
                }).toList();
                if (filtered.isEmpty) {
                  return const EmptyView(icon: Icons.people_outline, title: 'No users found');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _UserTile(user: filtered[i], isMe: filtered[i].id == me?.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserTile extends ConsumerWidget {
  const _UserTile({required this.user, required this.isMe});
  final UserModel user;
  final bool isMe;

  Future<void> _toggleActive(BuildContext context, WidgetRef ref) async {
    final activate = !user.isActive;
    final ok = await showConfirmDialog(
      context,
      title: activate ? 'Reactivate user' : 'Deactivate user',
      message: activate
          ? 'Allow ${user.fullName} to sign in again?'
          : '${user.fullName} will be signed out of all data immediately and cannot sign in. '
              'Their tickets and history are kept.',
      confirmLabel: activate ? 'Reactivate' : 'Deactivate',
      destructive: !activate,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(adminActionsProvider).updateUser(user.id, {'is_active': activate});
      if (context.mounted) showSnack(context, activate ? 'User reactivated' : 'User deactivated');
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  Future<void> _resetPassword(BuildContext context, WidgetRef ref) async {
    final pw = await showDialog<String>(context: context, builder: (_) => const _PasswordDialog());
    if (pw == null || !context.mounted) return;
    try {
      await ref.read(adminActionsProvider).resetPassword(user.id, pw);
      if (context.mounted) {
        showSnack(context, 'Password reset. Share the new password with ${user.fullName} securely.');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: user.isActive ? null : Colors.grey[300],
            child: Text(user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase()),
          ),
          title: Text(
            '${user.fullName}${isMe ? ' (you)' : ''}',
            style: TextStyle(
              decoration: user.isActive ? null : TextDecoration.lineThrough,
            ),
          ),
          subtitle: Text(
            '${user.employeeNumber} • ${Fmt.role(user.role)} • ${user.department}\n${user.email}'
            '${user.isActive ? '' : '  —  DEACTIVATED'}',
          ),
          isThreeLine: true,
          trailing: PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  showDialog(context: context, builder: (_) => _UserDialog(existing: user));
                case 'password':
                  _resetPassword(context, ref);
                case 'active':
                  _toggleActive(context, ref);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit details / role')),
              const PopupMenuItem(value: 'password', child: Text('Reset password')),
              if (!isMe)
                PopupMenuItem(
                  value: 'active',
                  child: Text(user.isActive ? 'Deactivate' : 'Reactivate'),
                ),
            ],
          ),
        ),
      );
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
                        helperText: 'At least 8 characters. Share it with the user securely.',
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
                decoration: const InputDecoration(labelText: 'New password'),
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
