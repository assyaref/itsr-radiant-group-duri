import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';
import '../providers/auth_provider.dart';
import '../utils/error_messages.dart';
import '../utils/validators.dart';

/// How the user identifies themselves.
enum LoginMethod { email, company }

/// Login page following the "1. Halaman Login" design:
/// brand header, IT Support illustration, swipeable slogan with page dots,
/// "Masuk dengan Email" / "atau" / "Masuk dengan Akun Perusahaan".
/// Choosing a method shows the matching sign-in form on the same page.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const illustrationAsset = 'assets/images/login_illustration.png';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  LoginMethod? _method;
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _choose(LoginMethod? method) {
    setState(() {
      _method = method;
      _error = null;
      _identifier.clear();
      _password.clear();
    });
  }

  Future<void> _submit() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final id = _method == LoginMethod.email
        ? _identifier.text.trim().toLowerCase()
        : Validators.normalizeEmployeeNumber(_identifier.text);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(id, _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 960;

    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: _method == null
          ? _Welcome(
              key: const ValueKey('welcome'),
              showIllustration: !wide,
              onEmail: () => _choose(LoginMethod.email),
              onCompany: () => _choose(LoginMethod.company),
            )
          : _buildForm(context, showIllustration: !wide),
    );

    // No on-screen back arrow (design): the phone's / browser's Back gesture
    // returns from the sign-in form to the welcome page.
    return PopScope(
      canPop: _method == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _choose(null);
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFEFF5FF), Colors.white],
              stops: [0, 0.55],
            ),
          ),
          child: SafeArea(
            child: wide
                ? Row(
                    children: [
                      const Expanded(child: _DesktopHero()),
                      SizedBox(
                        width: 480,
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(40),
                            child: content,
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: content,
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, {required bool showIllustration}) {
    final email = _method == LoginMethod.email;
    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          key: ValueKey(_method),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            if (showIllustration) ...[
              const _BrandHeader(compact: true),
              const SizedBox(height: 8),
              const SizedBox(height: 150, child: LoginIllustration()),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 16),
            Text(
              email ? 'Gunakan email kantor dan password akun ITSR Anda.' : 'Gunakan Employee Number (NIK) dan password akun ITSR Anda.',
              style: const TextStyle(
                color: AppTheme.muted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFDC2626),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        key: const Key('login_error'),
                        style: const TextStyle(
                          color: Color(0xFF991B1B),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (email)
              TextFormField(
                key: const Key('email_field'),
                controller: _identifier,
                enabled: !_busy,
                autofillHints: const [
                  AutofillHints.email,
                  AutofillHints.username,
                ],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                inputFormatters: [LengthLimitingTextInputFormatter(254)],
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Email kantor Anda',
                  prefixIcon: Icon(Icons.mail_outline),
                ),
                validator: (v) => Validators.email(v),
              )
            else
              TextFormField(
                key: const Key('employee_number_field'),
                controller: _identifier,
                enabled: !_busy,
                autofillHints: const [AutofillHints.username],
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                decoration: const InputDecoration(
                  labelText: 'Employee Number',
                  hintText: '',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: Validators.employeeNumber,
              ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('password_field'),
              controller: _password,
              focusNode: _passwordFocus,
              enabled: !_busy,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _obscure
                      ? 'Tampilkan password'
                      : 'Sembunyikan password',
                  icon: Icon(
                    _obscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: Validators.loginPassword,
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const Key('login_button'),
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Masuk', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              key: const Key('switch_login_method'),
              onPressed: _busy
                  ? null
                  : () => _choose(
                      email ? LoginMethod.company : LoginMethod.email,
                    ),
              child: Text(
                email ? 'Masuk dengan Akun Perusahaan' : 'Masuk dengan Email',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Lupa password? Hubungi administrator IT Support.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (!compact) ...[
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.headset_mic, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 10),
      ],
      Text(
        'IT Support & Service Request',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: compact ? 18 : 22,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF0F172A),
          height: 1.1,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        'Cabang Duri',
        style: TextStyle(
          fontSize: compact ? 12 : 14,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF334155),
        ),
      ),
    ],
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({
    super.key,
    required this.showIllustration,
    required this.onEmail,
    required this.onCompany,
  });
  final bool showIllustration;
  final VoidCallback onEmail;
  final VoidCallback onCompany;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final artHeight = (height * 0.34).clamp(170.0, 300.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BrandHeader(),
        const SizedBox(height: 12),
        if (showIllustration)
          SizedBox(height: artHeight, child: const LoginIllustration()),
        const SizedBox(height: 16),
        const _SloganCarousel(),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            key: const Key('email_login_entry'),
            onPressed: onEmail,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.mail_outline, size: 22),
            label: const Text(
              'Masuk dengan Email',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          children: [
            Expanded(child: Divider(color: AppTheme.border)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'atau',
                style: TextStyle(color: AppTheme.muted, fontSize: 14),
              ),
            ),
            Expanded(child: Divider(color: AppTheme.border)),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            key: const Key('company_login_entry'),
            onPressed: onCompany,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.ink,
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppTheme.border, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.apartment_outlined, size: 22),
            label: const Text(
              'Masuk dengan Akun Perusahaan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Solusi Cepat untuk Kebutuhan IT Anda" + subtitle, swipeable, with dots.
class _SloganCarousel extends StatefulWidget {
  const _SloganCarousel();

  @override
  State<_SloganCarousel> createState() => _SloganCarouselState();
}

class _SloganCarouselState extends State<_SloganCarousel> {
  static const _slides = [
    (
      'Solusi Cepat\nuntuk Kebutuhan IT Anda',
      'Ajukan tiket dengan mudah, pantau status, dan dapatkan solusi lebih cepat.',
    ),
    (
      'Pantau Tiket\nKapan Saja',
      'Lihat progres penanganan dan riwayat tiket Anda secara real-time.',
    ),
    (
      'Notifikasi\nLangsung ke Email',
      'Dapatkan kabar setiap kali tiket Anda diproses atau diselesaikan.',
    ),
  ];

  int _page = 0;

  void _go(int delta) =>
      setState(() => _page = (_page + delta) % _slides.length);

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_page < 0 ? _page + _slides.length : _page];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Natural height (no fixed box), so large text sizes never overflow.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -100) _go(1);
            if (v > 100) _go(_slides.length - 1);
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Column(
              key: ValueKey(_page),
              children: [
                Text(
                  slide.$1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  slide.$2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF475569),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _slides.length; i++)
              GestureDetector(
                onTap: () => setState(() => _page = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == _page
                        ? AppTheme.primary
                        : const Color(0xFFCBD5E1),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Left half on desktop: the large illustration.
class _DesktopHero extends StatelessWidget {
  const _DesktopHero();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(24),
    padding: const EdgeInsets.all(40),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFE0ECFF), Color(0xFFF5F9FF)],
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [const Expanded(child: LoginIllustration())],
    ),
  );
}

/// The IT Support character illustration. Uses the bundled PNG when present
/// and a built-in icon composition otherwise (so a missing/corrupt asset can
/// never break the login page).
class LoginIllustration extends StatelessWidget {
  const LoginIllustration({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Ilustrasi petugas IT Support',
    image: true,
    child: Image.asset(
      LoginScreen.illustrationAsset,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const _FallbackIllustration(),
    ),
  );
}

class _FallbackIllustration extends StatelessWidget {
  const _FallbackIllustration();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final s = c.biggest.shortestSide.isFinite
          ? c.biggest.shortestSide
          : 220.0;
      Widget bubble(IconData icon, double size, {bool light = false}) =>
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: light
                    ? const [Color(0xFFDBEAFE), Color(0xFF93C5FD)]
                    : const [Color(0xFF60A5FA), Color(0xFF1D4ED8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: size * 0.5,
              color: light ? const Color(0xFF1D4ED8) : Colors.white,
            ),
          );
      return Center(
        child: SizedBox(
          width: s * 1.15,
          height: s,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: s * 0.62,
                height: s * 0.62,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF3B82F6), Color(0xFF1E40AF)],
                  ),
                ),
                child: Icon(
                  Icons.support_agent,
                  color: Colors.white,
                  size: s * 0.38,
                ),
              ),
              Positioned(
                left: 0,
                top: s * 0.12,
                child: bubble(Icons.settings, s * 0.24),
              ),
              Positioned(
                left: s * 0.02,
                bottom: s * 0.14,
                child: bubble(Icons.build, s * 0.2, light: true),
              ),
              Positioned(
                right: s * 0.02,
                top: s * 0.04,
                child: bubble(Icons.wifi, s * 0.22, light: true),
              ),
              Positioned(
                right: 0,
                bottom: s * 0.22,
                child: bubble(Icons.desktop_windows, s * 0.24),
              ),
            ],
          ),
        ),
      );
    },
  );
}
