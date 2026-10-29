import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:quickeats_shop/core/constants/app_colors.dart';
import 'package:quickeats_shop/models/organisation.dart';
import 'package:quickeats_shop/viewmodels/auth_viewmodel.dart';
import 'package:quickeats_shop/views/widgets/org_codes_field.dart';
import 'package:quickeats_shop/views/widgets/password_policy.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  List<Organisation> _orgs = [];
  bool _orgsMissing = false;
  final _shopNameController = TextEditingController();
  final _shopDescController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    for (final c in [_shopNameController, _shopDescController, _nameController, _emailController, _passwordController]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => _goToLogin(context)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Form(
              key: _formKey,
              child: Consumer<AuthViewModel>(
                builder: (context, vm, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Register your shop', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Start receiving orders from your campus', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                    const SizedBox(height: 32),

                    _sectionLabel('Serves'),
                    OrgCodesField(value: _orgs, onChanged: (orgs) => setState(() { _orgs = orgs; _orgsMissing = false; })),
                    if (_orgsMissing)
                      const Padding(padding: EdgeInsets.only(top: 6),
                        child: Text('Add at least one organisation code', style: TextStyle(color: AppColors.error, fontSize: 12.5))),
                    const SizedBox(height: 24),

                    _sectionLabel('Shop'),
                    _field(_shopNameController, 'Shop Name', Icons.storefront_outlined),
                    const SizedBox(height: 16),
                    _field(_shopDescController, 'Short Description (optional)', Icons.notes_outlined, required: false),
                    const SizedBox(height: 24),

                    _sectionLabel('Owner account'),
                    _field(_nameController, 'Your Name', Icons.person_outline),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: _inputDecoration('Email', Icons.email_outlined).copyWith(helperText: 'Any email works, e.g. Gmail'),
                      validator: (v) {
                        final email = (v ?? '').trim();
                        if (email.isEmpty) return 'Required';
                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ? null : 'Enter a valid email address';
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      onChanged: (_) => setState(() {}),
                      decoration: _inputDecoration('Password', Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textMuted),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) => PasswordPolicy.validate(v ?? '', email: _emailController.text, name: _nameController.text),
                    ),
                    PasswordRequirements(password: _passwordController.text),

                    if (vm.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(vm.error!, style: TextStyle(color: AppColors.error, fontSize: 13)),
                      ),

                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: vm.isLoading ? null : () => _handleRegister(vm),
                        style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: vm.isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Create Shop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(onPressed: () => _goToLogin(context), child: const Text('Already registered? Sign In')),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.textMuted)),
  );

  Widget _field(TextEditingController c, String label, IconData icon, {String? hint, bool required = true, TextInputType? keyboard}) => TextFormField(
    controller: c,
    keyboardType: keyboard,
    decoration: _inputDecoration(label, icon).copyWith(hintText: hint),
    validator: required ? (v) => v == null || v.trim().isEmpty ? 'Required' : null : null,
  );

  InputDecoration _inputDecoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: AppColors.textMuted),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.primary, width: 2)),
    filled: true,
    fillColor: AppColors.surface,
  );

  void _goToLogin(BuildContext context) {
    context.read<AuthViewModel>().clearError();
    context.go('/login');
  }

  Future<void> _handleRegister(AuthViewModel vm) async {
    final formOk = _formKey.currentState!.validate();
    setState(() => _orgsMissing = _orgs.isEmpty);
    if (!formOk || _orgs.isEmpty) return;
    final ok = await vm.registerShop(
      orgSlugs: _orgs.map((o) => o.slug).toList(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      displayName: _nameController.text.trim(),
      shopName: _shopNameController.text.trim(),
      shopDescription: _shopDescController.text.trim(),
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop created! Sign in to start taking orders.')));
      context.go('/login');
    }
  }
}
