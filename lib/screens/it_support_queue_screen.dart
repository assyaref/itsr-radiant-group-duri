import 'package:flutter/material.dart';

import '../providers/tickets_provider.dart';
import '../widgets/ticket_list_view.dart';

/// All tickets visible to IT Support / Administrators (RLS-enforced), with
/// status, priority and assignee filters.
class ITSupportQueueScreen extends StatelessWidget {
  const ITSupportQueueScreen({super.key});

  @override
  Widget build(BuildContext context) => const TicketListView(
        scope: TicketScope.queue,
        showAssigneeFilter: true,
        emptyTitle: 'The queue is empty',
        emptyMessage: 'New tickets from employees will appear here.',
      );
}
