import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../constants/app_constants.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatters.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';
import '../../widgets/employee_ui.dart';

/// "11. Profil Karyawan".
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const appVersion = '1.0.0';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) return const LoadingView();

    final items = <(Key, IconData, String, VoidCallback)>[
      (
        const Key('profile_account'),
        Icons.person_outline_rounded,
        'Informasi Akun',
        () => _showAccount(context, user),
      ),
      (
        const Key('profile_password'),
        Icons.lock_outline_rounded,
        'Ubah Password',
        () => _changePassword(context, ref),
      ),
      (
        const Key('profile_summary'),
        Icons.insert_chart_outlined_rounded,
        'Ringkasan Tiket',
        () => context.push('/summary'),
      ),
      (
        const Key('profile_notifications'),
        Icons.notifications_none_rounded,
        'Notifikasi',
        () => context.go('/notifications'),
      ),
      (
        const Key('profile_help'),
        Icons.help_outline_rounded,
        'Bantuan',
        () => _showHelp(context),
      ),
      (
        const Key('profile_about'),
        Icons.info_outline_rounded,
        'Tentang Aplikasi',
        () => _showAbout(context),
      ),
    ];

    return Scaffold(
      backgroundColor: EColors.page,
      appBar: EHeader(
        title: 'Profil',
        centerTitle: true,
        onBack: () => context.go('/dashboard'),
        trailing: IconButton(
          tooltip: 'Informasi Akun',
          icon: const Icon(Icons.settings_outlined, color: EColors.blue),
          onPressed: () => _showAccount(context, user),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SizedBox(height: 8),
          Center(child: InitialsAvatar(user.fullName, size: 96)),
          const SizedBox(height: 12),
          Text(
            user.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: EColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            user.department,
            textAlign: TextAlign.center,
            style: const TextStyle(color: EColors.muted, fontSize: 13.5),
          ),
          const SizedBox(height: 20),
          ECard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (key, icon, label, onTap) in items)
                  ListTile(
                    key: key,
                    leading: Icon(icon, color: EColors.text),
                    title: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: EColors.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: EColors.grey,
                    ),
                    onTap: onTap,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              key: const Key('profile_sign_out'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: const Icon(Icons.logout_rounded, color: EColors.red),
              title: const Text(
                'Keluar',
                style: TextStyle(
                  color: EColors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: () async {
                final ok = await showConfirmDialog(
                  context,
                  title: 'Keluar',
                  message: 'Keluar dari aplikasi?',
                  confirmLabel: 'Keluar',
                );
                if (ok) {
                  await ref.read(authControllerProvider.notifier).signOut();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  static void _showAccount(BuildContext context, UserModel u) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Informasi Akun',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final (label, value) in [
                ('Nama', u.fullName),
                ('Employee Number', u.employeeNumber),
                ('Email', u.email),
                ('Departemen', u.department),
                ('Telepon', u.phoneNumber ?? '-'),
                ('Peran', Fmt.role(u.role)),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          label,
                          style: const TextStyle(color: EColors.muted),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          value,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Perubahan data akun dilakukan oleh administrator IT.',
                style: TextStyle(color: EColors.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _changePassword(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (changed == true && context.mounted) {
      showSnack(context, 'Password berhasil diubah');
    }
  }

  static void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Bantuan',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              const Text(
                '• Buat tiket untuk setiap masalah IT (perangkat, aplikasi, jaringan, akun).\n'
                '• Pantau status di menu Tiket; balas pertanyaan IT Support melalui tab Komentar.\n'
                '• Jika tiket sudah selesai tetapi masalah muncul lagi, buka ulang tiket tersebut.\n'
                '• Lupa password? Hubungi administrator IT Support Cabang Duri.',
                style: TextStyle(height: 1.6, color: EColors.text),
              ),
              const SizedBox(height: 16),
              EPrimaryButton(
                label: 'Buat Tiket',
                icon: Icons.add,
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/tickets/new');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: 'Versi $appVersion',
      applicationIcon: const CircleAvatar(
        backgroundColor: EColors.blue,
        child: Icon(Icons.headset_mic, color: Colors.white),
      ),
      children: const [
        Text(
          'Aplikasi tiket IT Support Cabang Duri: ajukan tiket, pantau status, '
          'dan dapatkan solusi lebih cepat.',
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .changePassword(_current.text, _pw.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ubah Password'),
    content: Form(
      key: _form,
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: EColors.red),
                ),
              ),
            TextFormField(
              key: const Key('current_password_field'),
              controller: _current,
              obscureText: _obscure,
              enabled: !_busy,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(
                labelText: 'Password / PIN saat ini',
              ),
              validator: (v) => (v == null || v.isEmpty)
                  ? 'Masukkan password saat ini'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('new_password_field'),
              controller: _pw,
              obscureText: _obscure,
              enabled: !_busy,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'Password / PIN baru',
                helperText: 'PIN 4–6 digit angka, atau minimal 8 karakter',
                suffixIcon: IconButton(
                  tooltip: _obscure
                      ? 'Tampilkan password'
                      : 'Sembunyikan password',
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: Validators.newPassword,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('confirm_password_field'),
              controller: _confirm,
              obscureText: _obscure,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Ulangi password baru',
              ),
              validator: (v) => v != _pw.text ? 'Password tidak sama' : null,
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Batal'),
      ),
      FilledButton(
        key: const Key('save_password_button'),
        onPressed: _busy ? null : _save,
        child: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Simpan'),
      ),
    ],
  );
}
