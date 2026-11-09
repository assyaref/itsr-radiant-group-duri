import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_settings_model.dart';
import '../../providers/admin_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/formatters.dart';
import '../../utils/validators.dart';
import '../../widgets/common.dart';

/// Administrator: notification settings. The addresses entered here are the
/// ONLY source of the IT Support group / manager CC recipients.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    return s.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(appSettingsProvider)),
      data: (settings) => _SettingsForm(settings: settings),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});
  final AppSettingsModel settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  final _form = GlobalKey<FormState>();
  late final _group = TextEditingController(text: widget.settings.itSupportGroupEmail);
  late final _manager = TextEditingController(text: widget.settings.managerEmail);
  late final _baseUrl = TextEditingController(text: widget.settings.appBaseUrl);
  late bool _enabled = widget.settings.notificationsEnabled;
  bool _busy = false;

  @override
  void dispose() {
    _group.dispose();
    _manager.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(adminActionsProvider).saveSettings(
            itSupportGroupEmail: _group.text,
            managerEmail: _manager.text,
            notificationsEnabled: _enabled,
            appBaseUrl: _baseUrl.text,
          );
      if (mounted) showSnack(context, 'Settings saved');
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PageBody(
          maxWidth: 720,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Email notifications', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Emails are sent through the Gmail account configured on the server '
                      '(GMAIL_USER secret). Every notification CCs the addresses below.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Send email notifications'),
                      value: _enabled,
                      onChanged: _busy ? null : (v) => setState(() => _enabled = v),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _group,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'IT Support group email (CC)',
                        helperText: 'Leave empty if there is no shared IT mailbox',
                      ),
                      validator: (v) => Validators.email(v, required: false),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _manager,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Manager email (CC)'),
                      validator: (v) => Validators.email(v, required: false),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _baseUrl,
                      enabled: !_busy,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Application URL (for links in emails)',
                        hintText: 'https://itsr.your-domain',
                      ),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return null;
                        final u = Uri.tryParse(t);
                        return (u == null || !u.hasScheme || !u.scheme.startsWith('http'))
                            ? 'Enter a full URL starting with https://'
                            : null;
                      },
                    ),
                    if (widget.settings.updatedAt != null) ...[
                      const SizedBox(height: 12),
                      Text('Last saved ${Fmt.dateTime(widget.settings.updatedAt!)}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: const Icon(Icons.save),
                        label: const Text('Save settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
