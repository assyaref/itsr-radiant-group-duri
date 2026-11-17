import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/tickets_provider.dart';
import '../../widgets/employee_ui.dart';

/// "6. Konfirmasi Pengajuan": shown right after a ticket is created.
class TicketSubmittedScreen extends ConsumerWidget {
  const TicketSubmittedScreen({super.key, required this.ticketId});
  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final number = ref
        .watch(ticketDetailProvider(ticketId))
        .valueOrNull
        ?.ticket
        .ticketNumber;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/dashboard');
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(
                    width: 220,
                    height: 170,
                    child: _SuccessBadge(),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tiket Berhasil Dikirim!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: EColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tiket Anda telah berhasil dibuat\ndengan nomor:',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: EColors.text,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    key: const Key('submitted_ticket_number'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: EColors.blueSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: number == null
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            number,
                            style: const TextStyle(
                              color: EColors.blue,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Tim IT akan segera memproses tiket Anda.\nAnda akan mendapatkan notifikasi '
                    'jika ada pembaruan.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: EColors.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  EPrimaryButton(
                    key: const Key('back_to_home_button'),
                    label: 'Kembali ke Beranda',
                    onPressed: () => context.go('/dashboard'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go('/tickets/$ticketId'),
                    child: const Text('Lihat detail tiket'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Green check with a few confetti marks around it.
class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    const colors = [
      EColors.red,
      EColors.amber,
      EColors.blue,
      EColors.green,
      EColors.purple,
    ];
    final rnd = math.Random(7);
    return Stack(
      alignment: Alignment.center,
      children: [
        for (var i = 0; i < 14; i++)
          Align(
            alignment: Alignment(
              math.cos(i / 14 * 2 * math.pi) * (0.75 + rnd.nextDouble() * 0.25),
              math.sin(i / 14 * 2 * math.pi) * (0.8 + rnd.nextDouble() * 0.2),
            ),
            child: Transform.rotate(
              angle: rnd.nextDouble() * math.pi,
              child: Container(
                width: 7,
                height: 3.5,
                decoration: BoxDecoration(
                  color: colors[i % colors.length],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        Container(
          width: 108,
          height: 108,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: EColors.green,
            boxShadow: [
              BoxShadow(
                color: Color(0x4422C55E),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.check_rounded,
            color: Colors.white,
            size: 64,
            semanticLabel: 'Berhasil',
          ),
        ),
      ],
    );
  }
}
