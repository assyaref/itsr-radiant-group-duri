import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category_model.dart';
import '../../providers/admin_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

/// Administrator: ticket categories. Categories are never deleted (existing
/// tickets reference them); they are deactivated instead.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(allCategoriesProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_category_fab',
        onPressed: () => showDialog(context: context, builder: (_) => const _CategoryDialog()),
        icon: const Icon(Icons.add),
        label: const Text('Add category'),
      ),
      body: cats.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(allCategoriesProvider)),
        data: (list) => list.isEmpty
            ? const EmptyView(icon: Icons.category_outlined, title: 'No categories yet')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _CategoryTile(category: list[i]),
              ),
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});
  final CategoryModel category;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(Icons.label_outline,
              color: category.isActive ? Theme.of(context).colorScheme.primary : Colors.grey),
          title: Text(category.name),
          subtitle: Text([
            if ((category.description ?? '').isNotEmpty) category.description!,
            'Order ${category.sortOrder}',
            if (!category.isActive) 'INACTIVE',
          ].join(' • ')),
          trailing: Wrap(spacing: 4, children: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  showDialog(context: context, builder: (_) => _CategoryDialog(existing: category)),
            ),
            Switch(
              value: category.isActive,
              onChanged: (v) async {
                if (!v) {
                  final ok = await showConfirmDialog(context,
                      title: 'Deactivate category',
                      message:
                          'Employees will no longer be able to choose "${category.name}". Existing tickets keep it.',
                      confirmLabel: 'Deactivate');
                  if (!ok) return;
                }
                try {
                  await ref.read(adminActionsProvider).updateCategory(category.id, {'is_active': v});
                } catch (e) {
                  if (context.mounted) showSnack(context, friendlyError(e), error: true);
                }
              },
            ),
          ]),
        ),
      );
}

class _CategoryDialog extends ConsumerStatefulWidget {
  const _CategoryDialog({this.existing});
  final CategoryModel? existing;

  @override
  ConsumerState<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends ConsumerState<_CategoryDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late final _order = TextEditingController(text: '${widget.existing?.sortOrder ?? 100}');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final actions = ref.read(adminActionsProvider);
      final order = int.parse(_order.text.trim());
      if (widget.existing == null) {
        await actions.createCategory(_name.text, _desc.text, order);
      } else {
        await actions.updateCategory(widget.existing!.id, {
          'name': _name.text.trim(),
          'description': _desc.text.trim(),
          'sort_order': order,
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'Add category' : 'Edit category'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name *'),
                validator: (v) => Validators.requiredText(v, 'Name', max: 60),
              ),
              if (widget.existing != null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Renaming also updates existing tickets in this category.',
                      style: TextStyle(fontSize: 12)),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _order,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Sort order'),
                validator: (v) => int.tryParse(v?.trim() ?? '') == null ? 'Enter a number' : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
        ],
      );
}
