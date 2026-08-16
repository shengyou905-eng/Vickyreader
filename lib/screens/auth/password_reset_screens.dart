import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../services/auth_service.dart';
import 'auth_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AuthService.requestPasswordReset(
      _emailController.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _sent = !result.containsKey('error');
      _error = result['error']?.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.forgotPasswordTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              Text(
                context.l10n.forgotPasswordTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.forgotPasswordSubtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: context.l10n.email,
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return context.l10n.enterEmail;
                  if (!email.contains('@')) return context.l10n.invalidEmail;
                  return null;
                },
              ),
              const SizedBox(height: 20),
              if (_sent)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    context.l10n.passwordResetEmailSent,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.l10n.sendResetEmail),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  final String token;

  const ResetPasswordScreen({super.key, required this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  bool _complete = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await AuthService.resetPassword(
      widget.token,
      _passwordController.text,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _complete = result['reset'] == true;
      _error = result['error']?.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.resetPasswordTitle)),
      body: SafeArea(
        child: _complete
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.passwordResetSuccess,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const AuthScreen()),
                        ),
                        child: Text(context.l10n.backToLogin),
                      ),
                    ],
                  ),
                ),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const SizedBox(height: 24),
                    Text(
                      context.l10n.resetPasswordTitle,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Text(context.l10n.resetPasswordSubtitle),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: context.l10n.newPassword,
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => (value?.length ?? 0) < 6
                          ? context.l10n.passwordMinLength
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: context.l10n.confirmNewPassword,
                        prefixIcon: const Icon(Icons.lock_reset_rounded),
                      ),
                      validator: (value) => value != _passwordController.text
                          ? context.l10n.passwordsDoNotMatch
                          : null,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(context.l10n.resetPassword),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
