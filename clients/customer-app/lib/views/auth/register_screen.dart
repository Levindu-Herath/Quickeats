import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:quickeats_customer/core/constants/app_colors.dart';
import 'package:quickeats_customer/core/di/service_locator.dart';
import 'package:quickeats_customer/models/organisation.dart';
import 'package:quickeats_customer/services/account_service.dart';
import 'package:quickeats_customer/viewmodels/auth_viewmodel.dart';
import 'package:quickeats_customer/views/widgets/password_policy.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

enum _CodeState { empty, checking, found, notFound, failed }

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _orgSlug = TextEditingController();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  Timer? _debounce;
  _CodeState _codeState = _CodeState.empty;
  Organisation? _org;

  // Check the organisation code shortly after the user stops typing.
  void _onCodeChanged(String value) {
    _debounce?.cancel();
    final code = value.trim();
    if (code.isEmpty) { setState(() { _codeState = _CodeState.empty; _org = null; }); return; }
    setState(() => _codeState = _CodeState.checking);
    _debounce = Timer(const Duration(milliseconds: 450), () => _lookup(code));
  }

  Future<void> _lookup(String code) async {
    try {
      final org = await getIt<AccountService>().lookupOrganisation(code);
      if (!mounted || _orgSlug.text.trim() != code) return; // a newer code was typed
      setState(() { _org = org; _codeState = org == null ? _CodeState.notFound : _CodeState.found; });
      if (_email.text.isNotEmpty) _form.currentState?.validate();
    } catch (_) {
      if (mounted) setState(() { _org = null; _codeState = _CodeState.failed; });
    }
  }

  String? _validateEmail(String? v) {
    final email = (v ?? '').trim();
    if (email.isEmpty) return 'Required';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return 'Enter a valid email address';
    final org = _org;
    if (org != null && !org.acceptsEmail(email)) return 'Use your ${org.domainsLabel} email';
    return null;
  }

  Future<void> _submit(AuthViewModel vm) async {
    if (!_form.currentState!.validate() || _org == null) return;
    final ok = await vm.register(_org!.slug, _email.text.trim(), _password.text, _name.text.trim());
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created! Please sign in.')));
      context.go('/login');
    }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(backgroundColor: AppColors.white, appBar: AppBar(backgroundColor: AppColors.white, elevation: 0),
      body: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Form(key: _form, child: Consumer<AuthViewModel>(builder: (_, vm, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Create Account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Join your university food network', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 32),
            TextFormField(
              controller: _orgSlug,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              onChanged: _onCodeChanged,
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return 'Required';
                if (_codeState == _CodeState.notFound) return 'No organisation uses this code';
                return null;
              },
              decoration: _decoration('Organisation Code', Icons.school_outlined, hint: 'e.g. ruh-eng',
                suffix: _codeState == _CodeState.checking
                  ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : _codeState == _CodeState.found ? const Icon(Icons.check_circle, color: AppColors.secondary) : null),
            ),
            _OrgHint(state: _codeState, org: _org),
            const SizedBox(height: 16),
            TextFormField(controller: _name, textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              decoration: _decoration('Full Name', Icons.person_outlined)),
            const SizedBox(height: 16),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, autocorrect: false,
              validator: _validateEmail,
              decoration: _decoration('Organisation Email', Icons.email_outlined,
                hint: _org != null ? 'name${_org!.emailDomains.isEmpty ? '' : '@${_org!.emailDomains.first.replaceFirst('*.', 'dept.')}'}' : null)),
            const SizedBox(height: 16),
            TextFormField(controller: _password, obscureText: !_showPassword,
              onChanged: (_) => setState(() {}),
              validator: (v) => PasswordPolicy.validate(v ?? '', email: _email.text, name: _name.text),
              decoration: _decoration('Password', Icons.lock_outline,
                suffix: IconButton(icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword)))),
            PasswordRequirements(password: _password.text),
            if (vm.error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(vm.error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
            const SizedBox(height: 24),
            SizedBox(height: 50, child: FilledButton(
              onPressed: vm.isLoading || _codeState != _CodeState.found ? null : () => _submit(vm),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: vm.isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Register', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            )),
            const SizedBox(height: 16),
            TextButton(onPressed: () => context.go('/login'), child: const Text('Already have an account? Sign In')),
            const SizedBox(height: 24),
          ],
        ))),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon, {String? hint, Widget? suffix}) => InputDecoration(
    labelText: label, hintText: hint, prefixIcon: Icon(icon), suffixIcon: suffix,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: AppColors.surface);

  @override void dispose() { _debounce?.cancel(); _orgSlug.dispose(); _email.dispose(); _name.dispose(); _password.dispose(); super.dispose(); }
}

/// Explains what the typed organisation code means for the email field.
class _OrgHint extends StatelessWidget {
  final _CodeState state;
  final Organisation? org;
  const _OrgHint({required this.state, required this.org});

  @override Widget build(BuildContext context) {
    final (IconData? icon, Color color, String? text) = switch (state) {
      _CodeState.found => (Icons.verified_outlined, AppColors.secondary, '${org!.name}\nSign up with your ${org!.domainsLabel} email.'),
      _CodeState.notFound => (Icons.error_outline, AppColors.error, 'No organisation uses this code. Check it with your university.'),
      _CodeState.failed => (Icons.wifi_off, AppColors.error, 'Couldn\'t check the code. Check your connection.'),
      _ => (null, AppColors.textSecondary, null),
    };
    if (text == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color, height: 1.35))),
      ]),
    );
  }
}
