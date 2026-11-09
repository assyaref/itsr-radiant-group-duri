import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../providers/tickets_provider.dart';
import '../widgets/ticket_list_view.dart';

class MyTicketsScreen extends StatelessWidget {
  const MyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          heroTag: 'new_ticket_fab',
          onPressed: () => context.go('/tickets/new'),
          icon: const Icon(Icons.add),
          label: const Text('New ticket'),
        ),
        body: TicketListView(
          scope: TicketScope.mine,
          emptyTitle: 'You have not submitted any tickets',
          emptyMessage: 'Having an IT problem? Create a ticket and IT Support will be notified.',
          emptyAction: FilledButton.icon(
            onPressed: () => context.go('/tickets/new'),
            icon: const Icon(Icons.add),
            label: const Text('Create a ticket'),
          ),
        ),
      );
}
