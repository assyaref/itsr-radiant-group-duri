import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_constants.dart';
import '../providers/tickets_provider.dart';
import '../utils/error_messages.dart';
import '../utils/formatters.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';
import '../utils/browser_files.dart';
import '../widgets/attachment_widgets.dart';
import '../widgets/employee_ui.dart';

/// "4./5. Form Buat Tiket" of the design: 1 Detail → 2 Lampiran → 3 Kirim.
class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key});

  static const descriptionMax = 1000;

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
  bool _busy = false;
  int _step = 0; // 0 = Detail, 1 = Lampiran, 2 = Kirim
  final List<PickedFile> _files = [];

  Future<void> _addFiles() async {
    final picked = await pickAttachmentFiles(
      context,
      alreadyChosen: _files.length,
    );
    if (picked.isNotEmpty && mounted) setState(() => _files.addAll(picked));
  }

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    _location.dispose();
    super.dispose();
  }

  void _back() {
    if (_busy) return;
    if (_step > 0) {
      setState(() => _step--);
    } else {
      goBack(context);
    }
  }

  /// The ticket has no location column: keep the user's input by appending it
  /// to the description instead of silently dropping it.
  String _descriptionWithLocation() {
    final loc = _location.text.trim();
    final desc = _description.text.trim();
    return loc.isEmpty ? desc : '$desc\n\nLokasi: $loc';
  }

  bool get _detailValid =>
      _category != null &&
      Validators.subject(_subject.text) == null &&
      Validators.description(_description.text) == null;

  void _next() {
    if (_busy) return;
    if (_step == 0 && !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _step++);
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_detailValid) {
      setState(() => _step = 0);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _formKey.currentState?.validate(),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(ticketActionsProvider)
          .createTicket(
            subject: _subject.text,
            description: _descriptionWithLocation(),
            category: _category!,
            priority: _priority,
          );
      // Attachments are uploaded after the ticket exists; a failed upload
      // never loses the ticket itself.
      List<String> failed = const [];
      if (_files.isNotEmpty) {
        failed = await ref.read(ticketActionsProvider).uploadAttachments(id, [
          for (final f in _files) (name: f.name, bytes: f.bytes),
        ]);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      context.go('/tickets/$id/submitted');
      if (failed.isNotEmpty) {
        messenger?.showSnackBar(
          SnackBar(
            backgroundColor: EColors.red,
            duration: const Duration(seconds: 8),
            content: Text(
              'Tiket terkirim, tetapi ${failed.length} lampiran gagal diunggah:\n'
              '${failed.join('\n')}\nAnda bisa menambahkannya lagi dari tab Lampiran.',
            ),
          ),
        );
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
    return PopScope(
      canPop: _step == 0 && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: EHeader(title: 'Buat Tiket', onBack: _back),
        body: categories.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(categoriesProvider),
          ),
          data: (cats) {
            if (cats.isEmpty) {
              return const EmptyView(
                icon: Icons.category_outlined,
                title: 'Kategori belum tersedia',
                message: 'Administrator perlu menambahkan kategori tiket terlebih dahulu.',
              );
            }
            return Column(
              children: [
                _Stepper(step: _step),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: switch (_step) {
                      0 => _detailStep(cats.map((c) => c.name).toList()),
                      1 => _attachmentStep(),
                      _ => _reviewStep(),
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _detailStep(List<String> categoryNames) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
            controller: _subject,
            enabled: !_busy,
            maxLength: 200,
            textInputAction: TextInputAction.next,
            decoration: eInput(
              hint: 'Contoh: Laptop tidak bisa nyala',
              counter: '',
            ),
            validator: Validators.subject,
          ),
          const SizedBox(height: 8),
          const FieldLabel('Kategori', required: true),
          DropdownButtonFormField<String>(
            key: const Key('category_field'),
            initialValue: _category,
            isExpanded: true,
            hint: const Text('Pilih kategori'),
            decoration: eInput(),
            items: [
              for (final name in categoryNames)
                DropdownMenuItem(
                  value: name,
                  child: Row(
                    children: [
                      Icon(
                        categoryStyle(name).$1,
                        size: 20,
                        color: EColors.text,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: _busy ? null : (v) => setState(() => _category = v),
            validator: (v) => v == null ? 'Please select a category' : null,
          ),
          const SizedBox(height: 16),
          const FieldLabel('Prioritas', required: true),
          DropdownButtonFormField<String>(
            key: const Key('priority_field'),
            initialValue: _priority,
            isExpanded: true,
            decoration: eInput(),
            items: [
              for (final p in AppConstants.priorities)
                DropdownMenuItem(
                  value: p,
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_rounded,
                        size: 20,
                        color: EColors.priority(p),
                      ),
                      const SizedBox(width: 10),
                      Text(Fmt.priority(p)),
                    ],
                  ),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() => _priority = v ?? _priority),
          ),
          const SizedBox(height: 16),
          const FieldLabel('Deskripsi Masalah', required: true),
          TextFormField(
            key: const Key('description_field'),
            controller: _description,
            enabled: !_busy,
            minLines: 4,
            maxLines: 10,
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                CreateTicketScreen.descriptionMax,
              ),
            ],
            decoration: eInput(
              hint: 'Jelaskan masalah yang Anda alami, sejak kapan, dan pesan error jika ada.',
              counter:
                  '${_description.text.length}/${CreateTicketScreen.descriptionMax}',
            ),
            validator: Validators.description,
          ),
          const SizedBox(height: 8),
          const FieldLabel('Lokasi', optional: true),
          TextFormField(
            key: const Key('location_field'),
            controller: _location,
            enabled: !_busy,
            maxLength: 120,
            decoration: eInput(
              hint: 'Contoh: Ruang Marketing',
              prefix: const Icon(
                Icons.location_on_outlined,
                color: EColors.text,
              ),
              counter: '',
            ),
          ),
          const SizedBox(height: 16),
          EPrimaryButton(
            key: const Key('next_step_button'),
            label: 'Lanjutkan',
            icon: Icons.arrow_forward,
            onPressed: _next,
          ),
        ],
      ),
    );
  }

  Widget _attachmentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text.rich(
          TextSpan(
            text: 'Upload Lampiran',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: EColors.ink,
            ),
            children: [
              TextSpan(
                text: ' (Opsional)',
                style: TextStyle(
                  fontWeight: FontWeight.w400,
                  color: EColors.muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AttachmentPicker(
          files: _files,
          enabled: !_busy,
          onAdd: _addFiles,
          onRemove: (i) => setState(() => _files.removeAt(i)),
        ),
        const SizedBox(height: 24),
        _twoButtons(
          next: EPrimaryButton(
            key: const Key('next_step_button'),
            label: 'Lanjutkan',
            icon: Icons.arrow_forward,
            onPressed: _next,
          ),
        ),
      ],
    );
  }

  Widget _reviewStep() {
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(color: EColors.muted, fontSize: 13),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
    const valueStyle = TextStyle(
      color: EColors.ink,
      fontWeight: FontWeight.w600,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Periksa & Kirim',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: EColors.ink,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: EColors.line),
          ),
          child: Column(
            children: [
              row('Judul', Text(_subject.text.trim(), style: valueStyle)),
              row(
                'Kategori',
                Row(
                  children: [
                    Icon(
                      categoryStyle(_category ?? '').$1,
                      size: 18,
                      color: EColors.text,
                    ),
                    const SizedBox(width: 6),
                    Flexible(child: Text(_category ?? '-', style: valueStyle)),
                  ],
                ),
              ),
              row(
                'Prioritas',
                Align(
                  alignment: Alignment.centerLeft,
                  child: ETag.priority(_priority),
                ),
              ),
              row(
                'Lokasi',
                Text(
                  _location.text.trim().isEmpty ? '-' : _location.text.trim(),
                  style: valueStyle,
                ),
              ),
              row(
                'Lampiran',
                Text(
                  _files.isEmpty ? '-' : _files.map((f) => f.name).join(', '),
                  style: valueStyle,
                ),
              ),
              row(
                'Deskripsi',
                Text(
                  _description.text.trim(),
                  style: const TextStyle(color: EColors.text, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _twoButtons(
          next: EPrimaryButton(
            key: const Key('submit_ticket_button'),
            label: 'Kirim Tiket',
            icon: Icons.send_rounded,
            busy: _busy,
            onPressed: _submit,
          ),
        ),
      ],
    );
  }

  Widget _twoButtons({required Widget next}) => Row(
    children: [
      Expanded(
        child: SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: _busy ? null : _back,
            style: OutlinedButton.styleFrom(
              foregroundColor: EColors.ink,
              side: const BorderSide(color: EColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Kembali'),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(child: next),
    ],
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Detail', 'Lampiran', 'Kirim'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _StepDot(
              number: i + 1,
              label: labels[i],
              state: i < step ? 1 : (i == step ? 0 : -1),
            ),
            if (i < labels.length - 1)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 22),
                  height: 2,
                  color: i < step ? EColors.blue : EColors.line,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.label,
    required this.state,
  });
  final int number;
  final String label;

  /// 1 = done, 0 = current, -1 = upcoming
  final int state;

  @override
  Widget build(BuildContext context) {
    final active = state >= 0;
    return Semantics(
      label: 'Langkah $number: $label${state == 0 ? ' (sekarang)' : ''}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state == 0 ? EColors.blue : Colors.white,
              border: Border.all(
                color: active ? EColors.blue : EColors.line,
                width: 1.6,
              ),
            ),
            alignment: Alignment.center,
            child: state == 1
                ? const Icon(Icons.check, size: 16, color: EColors.blue)
                : Text(
                    '$number',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: state == 0 ? Colors.white : EColors.muted,
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: state == 0 ? FontWeight.w700 : FontWeight.w500,
              color: active ? EColors.blue : EColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}
