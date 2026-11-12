import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/ticket_stats.dart';
import '../../models/user_model.dart';
import '../../providers/tickets_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/employee_ui.dart';

/// "2. Beranda (Dashboard)" of the employee design.
class EmployeeHomeScreen extends ConsumerWidget {
  const EmployeeHomeScreen({super.key, required this.user});
  final UserModel user;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(ticketStatsProvider('mine'));
    ref.invalidate(recentMyTicketsProvider);
    await ref
        .read(recentMyTicketsProvider.future)
        .catchError((_) => const <Never>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firstName = user.fullName.trim().split(RegExp(r'\s+')).first;
    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(firstName: firstName, fullName: user.fullName),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Stats(),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Tiket Terbaru',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: EColors.ink,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go('/tickets'),
                      child: const Text(
                        'Lihat Semua',
                        style: TextStyle(
                          color: EColors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const _RecentTickets(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.firstName, required this.fullName});
  final String firstName;
  final String fullName;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hai, $firstName 👋',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Selamat datang di\nIT Support Cabang Duri',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Notifikasi',
                    onPressed: () => context.go('/notifications'),
                    icon: const Icon(
                      Icons.notifications_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InitialsAvatar(
                    fullName,
                    size: 40,
                    solid: true,
                    onTap: () => context.go('/profile'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Material(
                color: const Color(0xFF1D4ED8),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.push('/tickets/new'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Laporkan Masalah IT\ndengan Cepat!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Kami siap membantu Anda',
                                style: TextStyle(
                                  color: Color(0xFFDBEAFE),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          key: const Key('dashboard_create_ticket'),
                          width: 46,
                          height: 46,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.add,
                            color: EColors.blue,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(ticketStatsProvider('mine'));
    return stats.when(
      loading: () => const SizedBox(height: 150, child: LoadingView()),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(ticketStatsProvider('mine')),
      ),
      data: (TicketStats s) {
        final cards = [
          (
            'Tiket Saya',
            s.total,
            Icons.confirmation_number_rounded,
            EColors.blue,
          ),
          ('Diproses', s.inProgress, Icons.autorenew_rounded, EColors.amber),
          ('Menunggu', s.open, Icons.hourglass_top_rounded, EColors.purple),
          (
            'Selesai',
            s.resolved + s.closed,
            Icons.check_rounded,
            EColors.green,
          ),
        ];
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.2,
          children: [
            for (final (label, value, icon, color) in cards)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.go('/tickets'),
                child: ECard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: 0.15),
                        ),
                        child: Icon(icon, size: 18, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$value',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: EColors.ink,
                              ),
                            ),
                            Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: EColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RecentTickets extends ConsumerWidget {
  const _RecentTickets();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentMyTicketsProvider);
    return recent.when(
      loading: () => const SizedBox(height: 120, child: LoadingView()),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(recentMyTicketsProvider),
      ),
      data: (items) => items.isEmpty
          ? ECard(
              child: Column(
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    size: 40,
                    color: EColors.grey,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Belum ada tiket',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: EColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Laporkan masalah IT pertama Anda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: EColors.muted),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => context.push('/tickets/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Buat Tiket'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (final t in items) ...[
                  TicketRow(t),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}
