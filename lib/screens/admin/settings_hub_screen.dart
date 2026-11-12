import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/common.dart';
import '../../widgets/employee_ui.dart';

/// Title block used by admin pages inside the shell (desktop has no app bar).
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.backTo,
  });
  final String title;
  final String subtitle;
  final Widget child;

  /// When set, shows a back arrow that goes to this location.
  final String? backTo;

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktop(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(desktop ? 24 : 12, desktop ? 22 : 12, 16, 8),
          child: Row(children: [
            if (backTo != null)
              IconButton(
                tooltip: 'Kembali',
                onPressed: () => context.go(backTo!),
                icon: const Icon(Icons.arrow_back),
              )
            else if (!desktop)
              const SizedBox(width: 4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: EColors.ink)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: EColors.muted, fontSize: 13)),
              ]),
            ),
          ]),
        ),
      ),
      Expanded(child: child),
    ]);
  }
}

/// "7. Pengaturan": entry points to the configuration pages that exist.
class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  static const items = <(String, String, IconData, Color, String)>[
    ('Kategori Tiket', 'Kelola kategori masalah', Icons.category_rounded, EColors.blue, '/admin/categories'),
    ('Email & Notifikasi', 'Server email (SMTP), uji kirim, status pengiriman', Icons.mark_email_unread_rounded,
        EColors.purple, '/admin/email-notifications'),
    ('Pengaturan Sistem', 'Email grup IT, email manajer, alamat aplikasi', Icons.tune_rounded, EColors.teal,
        '/admin/settings/system'),
    ('Karyawan & Hak Akses', 'Akun, role (Karyawan / IT Support / Administrator), import', Icons.manage_accounts_rounded,
        EColors.green, '/admin/users'),
    ('Laporan', 'Rekapitulasi dan export PDF', Icons.insert_chart_rounded, EColors.amber, '/summary'),
  ];

  @override
  Widget build(BuildContext context) => AdminPage(
        title: 'Pengaturan',
        subtitle: 'Konfigurasi aplikasi IT Support',
        child: ListView(
          padding: EdgeInsets.fromLTRB(isDesktop(context) ? 24 : 16, 8, isDesktop(context) ? 24 : 16, 24),
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ECard(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(children: [
                  for (final (title, sub, icon, color, path) in items)
                    ListTile(
                      key: Key('settings_${path.replaceAll('/', '_')}'),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: Icon(icon, color: color),
                      ),
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: EColors.ink)),
                      subtitle: Text(sub, style: const TextStyle(fontSize: 12.5, color: EColors.muted)),
                      trailing: const Icon(Icons.chevron_right, color: EColors.grey),
                      onTap: () => context.go(path),
                    ),
                ]),
              ),
            ),
          ],
        ),
      );
}
