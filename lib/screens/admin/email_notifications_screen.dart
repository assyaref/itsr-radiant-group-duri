import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/smtp_config_model.dart';
import '../../providers/admin_provider.dart';
import '../../providers/smtp_provider.dart';
import '../../utils/error_messages.dart';
import '../../utils/validators.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

class EmailNotificationsScreen extends ConsumerWidget {
  const EmailNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(smtpConfigProvider);
    return config.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(smtpConfigProvider),
      ),
      data: (cfg) => _EmailNotificationsForm(config: cfg),
    );
  }
}

class _EmailNotificationsForm extends ConsumerStatefulWidget {
  const _EmailNotificationsForm({required this.config});
  final SmtpConfigModel config;

  @override
  ConsumerState<_EmailNotificationsForm> createState() =>
      _EmailNotificationsFormState();
}

class _EmailNotificationsFormState extends ConsumerState<_EmailNotificationsForm> {
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _statusMessage;
  bool _statusError = false;

  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _senderName;
  late final TextEditingController _senderEmail;
  late final TextEditingController _itSupportEmail;
  late final TextEditingController _managerEmail;
  late final TextEditingController _testRecipient;
  // Held only in memory while the admin types; never pre-filled from the server.
  final _passwordCtl = TextEditingController();

  late bool _secure;
  late bool _notificationsEnabled;
  String? _password;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(text: widget.config.smtpHost);
    _port = TextEditingController(text: widget.config.smtpPort?.toString() ?? '');
    _username = TextEditingController(text: widget.config.smtpUsername);
    _senderName = TextEditingController(text: widget.config.smtpSenderName);
    _senderEmail = TextEditingController(text: widget.config.smtpSenderEmail);
    _itSupportEmail = TextEditingController(text: widget.config.itSupportGroupEmail);
    _managerEmail = TextEditingController(text: widget.config.managerEmail);
    _testRecipient = TextEditingController(
      text: widget.config.itSupportGroupEmail ?? widget.config.smtpSenderEmail ?? '',
    );
    _secure = widget.config.smtpSecure ?? false;
    _notificationsEnabled = widget.config.notificationsEnabled;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password = null;
    _passwordCtl.dispose();
    _senderName.dispose();
    _senderEmail.dispose();
    _itSupportEmail.dispose();
    _managerEmail.dispose();
    _testRecipient.dispose();
    super.dispose();
  }

  void _setStatus(String? message, {bool error = false}) {
    setState(() {
      _statusMessage = message;
      _statusError = error;
    });
  }

  Future<void> _saveSmtp() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    _setStatus(null);
    try {
      await ref.read(smtpActionsProvider).saveSmtpConfig(
        SmtpConfigInput(
          host: _host.text.trim(),
          port: int.tryParse(_port.text.trim()) ?? 0,
          secure: _secure,
          username: _username.text.trim(),
          password: _password ?? '',
          senderName: _senderName.text.trim().isEmpty ? null : _senderName.text.trim(),
          senderEmail: _senderEmail.text.trim(),
        ),
      );
      _password = null;
      _passwordCtl.clear();
      _setStatus('SMTP configuration saved. Credential stored securely.');
      ref.invalidate(smtpConfigProvider);
    } catch (e) {
      _setStatus(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeCredential() async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove SMTP credential',
      message:
          'This will delete the stored SMTP password. Email delivery will stop '
          'until a new credential is configured. Continue?',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    _setStatus(null);
    try {
      await ref.read(smtpActionsProvider).removeSmtpCredential();
      _password = null;
      _passwordCtl.clear();
      _setStatus('SMTP credential removed.');
      ref.invalidate(smtpConfigProvider);
    } catch (e) {
      _setStatus(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    final username = _username.text.trim();
    if (host.isEmpty || port == null || username.isEmpty || _password == null) {
      _setStatus('Please fill in all SMTP fields before testing.', error: true);
      return;
    }
    setState(() => _busy = true);
    _setStatus(null);
    try {
      await ref.read(smtpActionsProvider).testSmtpConnection(
        host: host,
        port: port,
        secure: _secure,
        username: username,
        password: _password!,
      );
      _setStatus('SMTP connection test successful.');
    } catch (e) {
      _setStatus(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendTestEmail() async {
    final recipient = _testRecipient.text.trim();
    if (recipient.isEmpty) {
      _setStatus('Please enter a recipient email address.', error: true);
      return;
    }
    final ok = await showConfirmDialog(
      context,
      title: 'Send test email',
      message:
          'A test email will be sent to $recipient using the configured SMTP '
          'settings. Continue?',
      confirmLabel: 'Send test email',
    );
    if (!ok) return;
    setState(() => _busy = true);
    _setStatus(null);
    try {
      await ref.read(smtpActionsProvider).sendTestEmail(
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 0,
        secure: _secure,
        username: _username.text.trim(),
        password: _password ?? '',
        senderName: _senderName.text.trim().isEmpty ? null : _senderName.text.trim(),
        senderEmail: _senderEmail.text.trim(),
        recipient: recipient,
        confirm: true,
      );
      _setStatus('Test email sent successfully.');
    } catch (e) {
      _setStatus(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRecipients() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    _setStatus(null);
    try {
      await ref.read(adminActionsProvider).saveSettings(
        itSupportGroupEmail: _itSupportEmail.text.trim().isEmpty
            ? null
            : _itSupportEmail.text.trim(),
        managerEmail: _managerEmail.text.trim().isEmpty
            ? null
            : _managerEmail.text.trim(),
        notificationsEnabled: _notificationsEnabled,
        appBaseUrl: null,
      );
      _setStatus('Notification recipients saved.');
      ref.invalidate(smtpConfigProvider);
      ref.invalidate(appSettingsProvider);
    } catch (e) {
      _setStatus(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleDelivery(bool value) async {
    setState(() => _busy = true);
    _setStatus(null);
    try {
      await ref.read(adminActionsProvider).saveSettings(
        itSupportGroupEmail: widget.config.itSupportGroupEmail,
        managerEmail: widget.config.managerEmail,
        notificationsEnabled: value,
        appBaseUrl: null,
      );
      _notificationsEnabled = value;
      ref.invalidate(smtpConfigProvider);
      ref.invalidate(appSettingsProvider);
      _setStatus(
        value ? 'Email delivery enabled.' : 'Email delivery disabled.',
      );
    } catch (e) {
      _setStatus(friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: PageBody(
        maxWidth: 900,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSmtpCard(context),
              const SizedBox(height: 24),
              _buildRecipientsCard(context),
              const SizedBox(height: 24),
              _buildControlsCard(context),
              const SizedBox(height: 24),
              _buildActionsCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmtpCard(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SMTP Configuration',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Outgoing mail server settings. The SMTP password is stored '
            'server-side encrypted and is never shown again after saving.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _host,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'SMTP Host *',
              hintText: 'mail.radiant-utama.com',
            ),
            validator: (v) => Validators.requiredText(v, 'SMTP Host', max: 255),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _port,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'SMTP Port *',
                    hintText: '465 or 587',
                  ),
                  validator: (v) {
                    final p = int.tryParse(v?.trim() ?? '');
                    if (p == null || p <= 0 || p > 65535) {
                      return 'Enter a valid port (1–65535)';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<bool>(
                  initialValue: _secure,
                  items: const [
                    DropdownMenuItem(value: false, child: Text('STARTTLS (port 587)')),
                    DropdownMenuItem(value: true, child: Text('SSL/TLS (port 465)')),
                  ],
                  onChanged: _busy ? null : (v) => setState(() => _secure = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _username,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'SMTP Username *',
              hintText: 'name@company-domain',
            ),
            validator: (v) => Validators.email(v, required: true),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordCtl,
            enabled: !_busy,
            obscureText: _obscurePassword,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'SMTP Password *',
              hintText: widget.config.passwordConfigured
                  ? 'Stored (not shown) — re-enter to save changes'
                  : 'Enter SMTP password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: _busy
                    ? null
                    : () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            onChanged: (v) => _password = v.isEmpty ? null : v,
            validator: (_) => _password == null ? 'SMTP password is required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _senderName,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Sender Name',
              hintText: 'ITSR Radiant Group Duri',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _senderEmail,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Sender Email *',
              hintText: 'name@company-domain',
            ),
            validator: (v) => Validators.email(v, required: true),
          ),
          const SizedBox(height: 20),
          if (widget.config.isConfigured) ...[
            Chip(
              label: const Text('Credential configured'),
              avatar: const Icon(Icons.lock_outline, color: Colors.green, size: 18),
              backgroundColor: Colors.green[50],
            ),
          ] else ...[
            Chip(
              label: const Text('No SMTP credential configured'),
              avatar: const Icon(Icons.lock_open, color: Colors.orange, size: 18),
              backgroundColor: Colors.orange[50],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _saveSmtp,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Configuration'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || !widget.config.isConfigured ? null : _removeCredential,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove Credential'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildRecipientsCard(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Notification Recipients',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Email addresses used for ticket notifications. These are stored '
            'in app_settings and are visible to administrators only.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _itSupportEmail,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'IT Support Email',
              hintText: 'name@company-domain',
              helperText:
                  'CC recipient for all notifications; fallback when no IT staff are active.',
            ),
            validator: (v) => Validators.email(v, required: false),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _managerEmail,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Manager Email',
              hintText: 'Not configured (NULL)',
              helperText: 'CC recipient for all notifications. Optional.',
            ),
            validator: (v) => Validators.email(v, required: false),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _busy ? null : _saveRecipients,
              icon: const Icon(Icons.save),
              label: const Text('Save Recipients'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildControlsCard(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Notification Controls',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Send email notifications'),
            subtitle: Text(
              _notificationsEnabled
                  ? 'Delivery is enabled.'
                  : 'Delivery is disabled. No outbox emails will be sent.',
            ),
            value: _notificationsEnabled,
            onChanged: _busy ? null : _toggleDelivery,
          ),
          const Divider(height: 24),
          _StatusRow(
            label: 'SMTP configuration',
            value: widget.config.isConfigured ? 'Configured' : 'Not configured',
            ok: widget.config.isConfigured,
          ),
          _StatusRow(
            label: 'SMTP password',
            value: widget.config.passwordConfigured
                ? 'Stored (encrypted)'
                : 'Not stored',
            ok: widget.config.passwordConfigured,
          ),
          _StatusRow(
            label: 'Last connection test',
            value: widget.config.smtpLastTestAt == null
                ? 'Never'
                : '${Fmt.dateTime(widget.config.smtpLastTestAt!)} — '
                    '${widget.config.smtpLastTestResult ?? 'unknown'}',
            ok: widget.config.smtpLastTestResult == 'success',
          ),
          _StatusRow(
            label: 'Last successful email',
            value: widget.config.smtpLastSuccessfulEmailAt == null
                ? 'None'
                : Fmt.dateTime(widget.config.smtpLastSuccessfulEmailAt!),
            ok: widget.config.smtpLastSuccessfulEmailAt != null,
          ),
          _StatusRow(
            label: 'Last failed email',
            value: widget.config.smtpLastFailedEmailAt == null
                ? 'None'
                : Fmt.dateTime(widget.config.smtpLastFailedEmailAt!),
            ok: widget.config.smtpLastFailedEmailAt == null,
          ),
        ],
      ),
    ),
  );

  Widget _buildActionsCard(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SMTP Actions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Test Connection verifies connectivity and authentication '
            'without sending email. Send Test Email requires explicit '
            'confirmation.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _testConnection,
                icon: const Icon(Icons.network_check),
                label: const Text('Test Connection'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed:
                    _busy || !widget.config.isConfigured
                        ? null
                        : _sendTestEmail,
                icon: const Icon(Icons.email_outlined),
                label: const Text('Send Test Email'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _toggleDelivery(false),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Disable Email Delivery'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _toggleDelivery(true),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Enable Email Delivery'),
                ),
              ),
            ],
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusError ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _statusError ? Colors.red[200]! : Colors.green[200]!,
                ),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _statusError ? Colors.red[800] : Colors.green[800],
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    this.ok = true,
  });
  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (ok ? Colors.green : Colors.red)[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (ok ? Colors.green : Colors.red)[200]!,
              ),
            ),
            child: Text(
              value,
              style: TextStyle(
                color: (ok ? Colors.green : Colors.red)[800],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
