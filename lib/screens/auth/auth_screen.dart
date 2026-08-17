import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../config/theme.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../services/apple_auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  late final Future<bool> _appleAvailable;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final supportsNativeApple =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    _appleAvailable = supportsNativeApple
        ? AppleAuthService.isAvailable()
        : Future<bool>.value(false);
  }

  Future<void> _signInWithApple() async {
    final ok = await context.read<AuthProvider>().signInWithApple();
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(bool isLogin) async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    bool ok;
    if (isLogin) {
      ok = await auth.signIn(email, password);
    } else {
      ok = await auth.signUp(email, password);
    }
    if (ok && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.authAccount),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          tabs: [
            Tab(text: context.l10n.login),
            Tab(text: context.l10n.register),
          ],
        ),
      ),
      body: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          return Form(
            key: _formKey,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildForm(isLogin: true, auth: auth),
                _buildForm(isLogin: false, auth: auth),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm({required bool isLogin, required AuthProvider auth}) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 32),
        Text(
          isLogin ? l10n.welcomeBack : l10n.createAccount,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          isLogin ? l10n.loginSubtitle : l10n.registerSubtitle,
          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 32),
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: l10n.email,
            prefixIcon: const Icon(Icons.email_outlined),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return l10n.enterEmail;
            if (!v.contains('@')) return l10n.invalidEmail;
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: l10n.password,
            prefixIcon: const Icon(Icons.lock_outlined),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return l10n.enterPassword;
            if (v.length < 6) return l10n.passwordMinLength;
            return null;
          },
        ),
        const SizedBox(height: 24),
        if (auth.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              auth.error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: auth.isLoading ? null : () => _submit(isLogin),
            child: auth.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isLogin ? l10n.login : l10n.register),
          ),
        ),
        if (isLogin)
          FutureBuilder<bool>(
            future: _appleAvailable,
            builder: (context, snapshot) {
              if (snapshot.data != true) return const SizedBox.shrink();
              return Column(
                children: [
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(l10n.orUseApple),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: SignInWithAppleButton(
                      onPressed: auth.isLoading ? null : _signInWithApple,
                      style: Theme.of(context).brightness == Brightness.dark
                          ? SignInWithAppleButtonStyle.white
                          : SignInWithAppleButtonStyle.black,
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                    ),
                  ),
                ],
              );
            },
          ),
        const SizedBox(height: 16),
        if (isLogin)
          Center(
            child: Text(
              l10n.localDataMergeNotice,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
