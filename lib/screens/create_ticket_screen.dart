import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../providers/tickets_provider.dart';
import '../utils/error_messages.dart';
import '../utils/formatters.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';

class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  String? _category;
  String _priority = AppConstants.priorityMedium;
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(ticketActionsProvider).createTicket(
            subject: _subject.text,
            description: _description.text,
            category: _category!,
            priority: _priority,
          );
      if (!mounted) return;
      showSnack(context, 'Ticket submitted. IT Support has been notified.');
      context.go('/tickets/$id');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);

    return categories.when(
      loading: () => const LoadingView(),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(categoriesProvider)),
      data: (cats) {
        if (cats.isEmpty) {
          return const EmptyView(
            icon: Icons.category_outlined,
            title: 'No categories available',
            message: 'An administrator needs to add ticket categories first.',
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PageBody(
            maxWidth: 760,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Describe your problem',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('A ticket number is assigned automatically when you submit.',
                          style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const Key('subject_field'),
                        controller: _subject,
                        enabled: !_busy,
                        maxLength: 200,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Subject *',
                          hintText: 'e.g. Laptop does not turn on',
                        ),
                        validator: Validators.subject,
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(builder: (context, c) {
                        final category = DropdownButtonFormField<String>(
                          key: const Key('category_field'),
                          initialValue: _category,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Category *'),
                          items: [
                            for (final cat in cats)
                              DropdownMenuItem(
                                value: cat.name,
                                child: Text(cat.name, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: _busy ? null : (v) => setState(() => _category = v),
                          validator: (v) => v == null ? 'Please select a category' : null,
                        );
                        final priority = DropdownButtonFormField<String>(
                          key: const Key('priority_field'),
                          initialValue: _priority,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Priority *'),
                          items: [
                            for (final p in AppConstants.priorities)
                              DropdownMenuItem(value: p, child: Text(Fmt.priority(p))),
                          ],
                          onChanged: _busy ? null : (v) => setState(() => _priority = v!),
                        );
                        if (c.maxWidth < 520) {
                          return Column(children: [
                            category,
                            const SizedBox(height: 16),
                            priority,
                          ]);
                        }
                        return Row(children: [
                          Expanded(child: category),
                          const SizedBox(width: 16),
                          Expanded(child: priority),
                        ]);
                      }),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('description_field'),
                        controller: _description,
                        enabled: !_busy,
                        minLines: 5,
                        maxLines: 12,
                        maxLength: 5000,
                        decoration: const InputDecoration(
                          labelText: 'Description *',
                          hintText:
                              'What happened? When did it start? Any error messages? Which device/location?',
                          alignLabelWithHint: true,
                        ),
                        validator: Validators.description,
                      ),
                      const SizedBox(height: 16),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowSpacing: 8,
                        overflowAlignment: OverflowBarAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : () => context.go('/tickets'),
                            child: const Text('Cancel'),
                          ),
                          FilledButton.icon(
                            key: const Key('submit_ticket_button'),
                            onPressed: _busy ? null : _submit,
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            label: const Text('Submit ticket'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
