import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../constants/app_theme.dart';
import '../providers/auth_provider.dart';
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
  String? _location;
  bool _busy = false;
  int _step = 0; // 0 = Detail, 1 = Lampiran

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
      final id = await ref
          .read(ticketActionsProvider)
          .createTicket(
            subject: _subject.text,
            description: _description.text,
            category: _category!,
            priority: _priority,
          );
      if (!mounted) return;
      final user = ref.read(currentUserProvider).valueOrNull;
      if (user != null && !user.isStaff) {
        context.go('/tickets/$id/submitted');
      } else {
        showSnack(context, 'Ticket submitted. IT Support has been notified.');
        context.go('/tickets/$id');
      }
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
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(categoriesProvider),
      ),
      data: (cats) {
        if (cats.isEmpty) {
          return const EmptyView(
            icon: Icons.category_outlined,
            title: 'No categories available',
            message: 'An administrator needs to add ticket categories first.',
          );
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            title: const Text('Buat Tiket'),
            centerTitle: false,
            elevation: 0,
          ),
          body: Column(
            children: [
              // Stepper header (matches reference mobile create ticket)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _StepCircle(1, 'Detail', _step == 0),
                        Expanded(child: _StepLine(_step >= 1)),
                        _StepCircle(2, 'Lampiran', _step == 1),
                        Expanded(child: _StepLine(_step >= 2)),
                        _StepCircle(3, 'Kirim', _step >= 2),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _step == 0
                            ? 'Informasi Masalah'
                            : 'Upload Lampiran (Opsional)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    if (_step == 0) const SizedBox(height: 8),
                    if (_step == 0)
                      Text(
                        'Judul Masalah *',
                        style: TextStyle(color: AppTheme.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_step == 0) ...[
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
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            key: const Key('category_field'),
                            initialValue: _category,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Category *',
                            ),
                            items: [
                              for (final cat in cats)
                                DropdownMenuItem(
                                  value: cat.name,
                                  child: Text(
                                    cat.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _category = v),
                            validator: (v) =>
                                v == null ? 'Please select a category' : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            key: const Key('priority_field'),
                            initialValue: _priority,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Priority *',
                            ),
                            items: [
                              for (final p in AppConstants.priorities)
                                DropdownMenuItem(
                                  value: p,
                                  child: Text(Fmt.priority(p)),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() => _priority = v!),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('location_field'),
                            controller: TextEditingController(
                              text: _location ?? '',
                            ),
                            enabled: !_busy,
                            decoration: const InputDecoration(
                              labelText: 'Location (Optional)',
                              hintText: 'e.g. Ruang Marketing',
                            ),
                            onChanged: (v) =>
                                setState(() => _location = v.trim()),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            key: const Key('description_field'),
                            controller: _description,
                            enabled: !_busy,
                            minLines: 5,
                            maxLines: 12,
                            maxLength: 5000,
                            decoration: const InputDecoration(
                              labelText: 'Description *',
                              hintText: 'What happened? When did it start? Any error messages? Which device/location?',
                              alignLabelWithHint: true,
                            ),
                            validator: Validators.description,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy ? null : () => context.pop(),
                                  child: const Text('Batal'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  key: const Key(
                                    'continue_ticket_details_button',
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () {
                                          if (_formKey.currentState!
                                              .validate()) {
                                            setState(() => _step = 1);
                                          }
                                        },
                                  child: const Text('Lanjutkan →'),
                                ),
                              ),
                            ],
                          ),
                        ] else if (_step == 1) ...[
                          // Lampiran step (matches reference screen 5)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.cloud_upload_outlined,
                                  size: 48,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Ketuk untuk upload foto atau file',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.ink,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Format: JPG, PNG, PDF (Maks. 10 MB)',
                                  style: TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {},
                                        icon: const Icon(Icons.image_outlined),
                                        label: const Text('Pilih File'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {},
                                        icon: const Icon(
                                          Icons.camera_alt_outlined,
                                        ),
                                        label: const Text('Kamera'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() => _step = 0),
                                  child: const Text('Kembali'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  key: const Key('submit_ticket_button'),
                                  onPressed: _busy ? null : _submit,
                                  child: const Text('Lanjutkan →'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle(this.number, this.label, this.active);
  final int number;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : AppTheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? AppTheme.primary : AppTheme.border,
              width: 2,
            ),
          ),
          child: Center(
            child: Text(
              number.toString(),
              style: TextStyle(
                color: active ? Colors.white : AppTheme.muted,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: active ? AppTheme.primary : AppTheme.muted,
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine(this.active);
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      color: active ? AppTheme.primary : AppTheme.border,
    );
  }
}
