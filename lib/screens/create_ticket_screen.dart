import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../data/attachment_repository.dart';
import '../models/category_model.dart';
import '../providers/attachment_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/tickets_provider.dart';
import '../utils/browser_files.dart';
import '../utils/error_messages.dart';
import '../utils/formatters.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';
import '../widgets/employee_ui.dart';

/// "4. Form Buat Tiket" of the employee design: a 3-step wizard
/// (Detail → Lampiran → Kirim) with Indonesian labels and optional
/// photo/file uploads before the ticket is submitted.
class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  String? _category;
  String _priority = AppConstants.priorityMedium;
  int _step = 0; // 0 = Detail, 1 = Lampiran, 2 = Kirim
  bool _busy = false;

  final List<PickedFile> _picked = [];
  final Set<String> _pickedNames = {};
  String? _pickError;

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    setState(() => _pickError = null);
    final files = await pickFiles(
      accept: '.jpg,.jpeg,.png,.pdf,.doc,.docx,.xls,.xlsx,.txt,.zip',
      multiple: true,
    );
    if (files.isEmpty) return;
    final added = <PickedFile>[];
    for (final f in files) {
      if (_pickedNames.contains(f.name)) continue;
      if (!f.mimeType.isAllowedAttachmentMime) {
        setState(() => _pickError = 'Tipe file tidak diizinkan: ${f.name}');
        return;
      }
      if (f.size > kMaxAttachmentSize) {
        setState(() => _pickError = 'File terlalu besar (maks 10 MB): ${f.name}');
        return;
      }
      added.add(f);
    }
    if (added.isEmpty) return;
    setState(() {
      _picked.addAll(added);
      _pickedNames.addAll(added.map((f) => f.name));
    });
  }

  void _removeAt(int i) {
    setState(() {
      _pickedNames.remove(_picked[i].name);
      _picked.removeAt(i);
    });
  }

  Future<void> _submit() async {
    // Fields live on step 0; they were validated before the user could
    // advance, so here we only guard against double-submit.
    if (_busy || _category == null) return;
    setState(() => _busy = true);
    try {
      // Read .future (not .valueOrNull): nothing else on this screen watches
      // the provider, so it may not be built yet on a deep link into the form.
      final user = await ref.read(currentUserProvider.future);
      if (user == null) throw StateError('Not signed in');
      final id = await ref.read(ticketActionsProvider).createTicket(
            subject: _subject.text,
            description: _description.text,
            category: _category!,
            priority: _priority,
          );
      // Upload attachments (optional) after the ticket exists.
      for (final f in _picked) {
        await ref.read(attachmentActionsProvider).uploadAttachment(
              ticketId: id,
              fileName: f.name,
              mimeType: f.mimeType,
              bytes: f.bytes,
              uploadedBy: user.id,
            );
      }
      if (!mounted) return;
      if (!user.isStaff) {
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

  void _next() {
    if (_step == 0 && !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _step = _step + 1);
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step = _step - 1);
    } else {
      context.pop();
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
          backgroundColor: EColors.page,
          appBar: EHeader(
            title: 'Buat Tiket',
            onBack: () => context.pop(),
          ),
          body: Column(
            children: [
              _Stepper(step: _step),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_step == 0) _DetailForm(cats: cats),
                        if (_step == 1) const _AttachmentStep(),
                        if (_step == 2)
                          _ReviewStep(
                            subject: _subject.text,
                            category: _category!,
                            priority: _priority,
                            location: _location.text.trim(),
                            description: _description.text,
                            attachments: _picked,
                          ),
                        const SizedBox(height: 20),
                        _Footer(
                          step: _step,
                          busy: _busy,
                          onBack: _back,
                          onNext: _next,
                          onSubmit: _submit,
                        ),
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

// ---------------------------------------------------------------------------
// Stepper header (design screens 4–5): 1 Detail · 2 Lampiran · 3 Kirim
// ---------------------------------------------------------------------------
class _Stepper extends StatelessWidget {
  const _Stepper({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Detail', 'Lampiran', 'Kirim'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) Expanded(child: _Line(done: step > i - 1)),
            _Circle(number: i + 1, label: labels[i], state: _state(i, step)),
          ],
        ],
      ),
    );
  }

  // 0 = upcoming, 1 = active, 2 = done
  int _state(int i, int step) => i < step ? 2 : (i == step ? 1 : 0);
}

class _Circle extends StatelessWidget {
  const _Circle({super.key, required this.number, required this.label, required this.state});
  final int number;
  final String label;
  final int state;

  @override
  Widget build(BuildContext context) {
    final color = state == 0 ? EColors.grey : EColors.blue;
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state == 2 ? EColors.blue : Colors.white,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: state == 2
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
                      '$number',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: state == 1 ? FontWeight.w700 : FontWeight.w500,
              color: state == 0 ? EColors.muted : EColors.blue,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) => Container(
    height: 2,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: done ? EColors.blue : EColors.line,
  );
}

// ---------------------------------------------------------------------------
// Step 1 — Informasi Masalah
// ---------------------------------------------------------------------------
class _DetailForm extends StatelessWidget {
  const _DetailForm({required this.cats});
  final List<CategoryModel> cats;

  @override
  Widget build(BuildContext context) {
    final screen = context.findAncestorStateOfType<_CreateTicketScreenState>();
    if (screen == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Informasi Masalah',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: EColors.ink,
          ),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Judul Masalah', required: true),
        TextFormField(
          key: const Key('subject_field'),
          controller: screen._subject,
          enabled: !screen._busy,
          maxLength: 200,
          textInputAction: TextInputAction.next,
          decoration: eInput(hint: 'Contoh: Laptop tidak bisa nyala'),
          validator: Validators.subject,
        ),
        const SizedBox(height: 16),
        const FieldLabel('Kategori', required: true),
        DropdownButtonFormField<String>(
          key: const Key('category_field'),
          initialValue: screen._category,
          isExpanded: true,
          decoration: eInput().copyWith(
            prefixIcon: const Icon(Icons.category_outlined, color: EColors.muted),
          ),
          items: [
            for (final cat in cats)
              DropdownMenuItem(value: cat.name, child: Text(cat.name)),
          ],
          onChanged: screen._busy
              ? null
              : (v) => screen.setState(() => screen._category = v),
          validator: (v) => v == null ? 'Pilih kategori masalah' : null,
        ),
        const SizedBox(height: 16),
        const FieldLabel('Prioritas', required: true),
        DropdownButtonFormField<String>(
          key: const Key('priority_field'),
          initialValue: screen._priority,
          isExpanded: true,
          decoration: eInput().copyWith(
            prefixIcon: const Icon(Icons.flag_outlined, color: EColors.muted),
          ),
          items: [
            for (final p in AppConstants.priorities)
              DropdownMenuItem(value: p, child: Text(Fmt.priority(p))),
          ],
          onChanged: screen._busy
              ? null
              : (v) => screen.setState(() => screen._priority = v!),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Deskripsi Masalah', required: true),
        TextFormField(
          key: const Key('description_field'),
          controller: screen._description,
          enabled: !screen._busy,
          minLines: 5,
          maxLines: 12,
          maxLength: 5000,
          decoration: eInput(
            hint: 'Jelaskan masalahnya, kapan mulai terjadi, dan perangkat/lokasi terkait',
          ),
          validator: Validators.description,
        ),
        const SizedBox(height: 16),
        const FieldLabel('Lokasi', optional: true),
        TextFormField(
          key: const Key('location_field'),
          controller: screen._location,
          enabled: !screen._busy,
          maxLength: 120,
          decoration: eInput(
            hint: 'Contoh: Ruang Marketing',
            prefix: const Icon(Icons.place_outlined, color: EColors.muted),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Upload Lampiran (Opsional)
// ---------------------------------------------------------------------------
class _AttachmentStep extends ConsumerStatefulWidget {
  const _AttachmentStep();

  @override
  ConsumerState<_AttachmentStep> createState() => _AttachmentStepState();
}

class _AttachmentStepState extends ConsumerState<_AttachmentStep> {
  @override
  Widget build(BuildContext context) {
    final screen = context.findAncestorStateOfType<_CreateTicketScreenState>();
    if (screen == null) return const SizedBox.shrink();
    final picked = screen._picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload Lampiran (Opsional)',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: EColors.ink,
          ),
        ),
        const SizedBox(height: 16),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: screen._busy ? null : screen._pickFiles,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EColors.line),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: EColors.blueSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.cloud_upload_outlined,
                      color: EColors.blue,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Ketuk untuk upload foto atau file',
                    style: TextStyle(fontWeight: FontWeight.w600, color: EColors.ink),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Format: JPG, PNG, PDF (Maks. 10 MB)',
                    style: TextStyle(color: EColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (picked.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: picked.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _Thumb(
                file: picked[i],
                onRemove: () => screen._removeAt(i),
              ),
            ),
          ),
        ],
        if (screen._pickError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: EColors.red, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    screen._pickError!,
                    style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EColors.blueSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: EColors.blue, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lampiran membantu tim IT memahami masalah Anda lebih cepat.',
                  style: TextStyle(color: EColors.text, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({super.key, required this.file, required this.onRemove});
  final PickedFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isImage = file.mimeType.startsWith('image/');
    return Stack(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EColors.line),
            color: EColors.page,
          ),
          clipBehavior: Clip.antiAlias,
          child: isImage
              ? Image.memory(file.bytes, fit: BoxFit.cover)
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.insert_drive_file, color: EColors.muted, size: 24),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: EColors.muted),
                      ),
                    ),
                  ],
                ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 14, color: EColors.ink),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Kirim (review ringkas + tombol kirim)
// ---------------------------------------------------------------------------
class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    super.key,
    required this.subject,
    required this.category,
    required this.priority,
    required this.location,
    required this.description,
    required this.attachments,
  });
  final String subject;
  final String category;
  final String priority;
  final String location;
  final String description;
  final List<PickedFile> attachments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kirim Tiket',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: EColors.ink,
          ),
        ),
        const SizedBox(height: 16),
        ECard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(label: 'Judul', value: subject),
              const SizedBox(height: 10),
              _Row(label: 'Kategori', value: category),
              const SizedBox(height: 10),
              _Row(label: 'Prioritas', value: Fmt.priority(priority)),
              if (location.isNotEmpty) ...[
                const SizedBox(height: 10),
                _Row(label: 'Lokasi', value: location),
              ],
              const SizedBox(height: 10),
              _Row(label: 'Deskripsi', value: description),
              const SizedBox(height: 10),
              _Row(
                label: 'Lampiran',
                value: attachments.isEmpty ? 'Tidak ada' : '${attachments.length} file',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Pastikan informasi di atas sudah benar. Tiket akan diteruskan ke tim IT Support.',
          style: TextStyle(color: EColors.muted, fontSize: 13),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 90,
        child: Text(label, style: const TextStyle(color: EColors.muted, fontSize: 13)),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Footer buttons: Kembali / Lanjutkan / Kirim
// ---------------------------------------------------------------------------
class _Footer extends StatelessWidget {
  const _Footer({
    super.key,
    required this.step,
    required this.busy,
    required this.onBack,
    required this.onNext,
    required this.onSubmit,
  });
  final int step;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final last = step == 2;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : onBack,
            child: const Text('Kembali'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: EPrimaryButton(
            key: Key(last ? 'submit_ticket_button' : 'continue_ticket_details_button'),
            label: last ? 'Kirim Tiket' : 'Lanjutkan',
            busy: busy,
            icon: last ? Icons.send_rounded : Icons.arrow_forward,
            onPressed: last ? onSubmit : onNext,
          ),
        ),
      ],
    );
  }
}
