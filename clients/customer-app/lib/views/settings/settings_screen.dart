import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:quickeats_customer/core/constants/app_colors.dart';
import 'package:quickeats_customer/viewmodels/auth_viewmodel.dart';
import 'package:quickeats_customer/viewmodels/cart_viewmodel.dart';
import 'package:quickeats_customer/viewmodels/settings_viewmodel.dart';
import 'package:quickeats_customer/views/widgets/password_policy.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<SettingsViewModel>().load(); }); }

  void _toast(String text, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), backgroundColor: error ? AppColors.error : null, behavior: SnackBarBehavior.floating));

  Future<void> _editName(SettingsViewModel vm) async {
    final name = await showDialog<String>(context: context,
      builder: (_) => _TextDialog(title: 'Your name', initial: vm.profile?.displayName ?? '', label: 'Full name'));
    if (name == null || !mounted) return;
    final err = await vm.updateDisplayName(name);
    if (mounted) _toast(err ?? 'Name updated', error: err != null);
  }

  Future<void> _changePassword(SettingsViewModel vm) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _PasswordDialog(
      onSubmit: vm.changePassword, email: vm.profile?.email ?? '', name: vm.profile?.displayName ?? ''));
    if (ok == true && mounted) _toast('Password changed');
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text('Your cart will be cleared on this device.'),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log out'))],
    ));
    if (ok != true || !mounted) return;
    context.read<CartViewModel>().clear();
    context.read<SettingsViewModel>().clear();
    await context.read<AuthViewModel>().logout();
    if (mounted) context.go('/login');
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.white, foregroundColor: AppColors.textPrimary, elevation: 0),
      body: Consumer<SettingsViewModel>(builder: (_, vm, __) {
        final p = vm.profile;
        if (p == null && vm.isLoading) return const Center(child: CircularProgressIndicator());
        if (p == null) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(vm.error ?? 'Could not load your account', style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: vm.load, child: const Text('Try again')),
            const SizedBox(height: 8),
            TextButton(onPressed: _logout, child: const Text('Log out')),
          ]));
        }
        return RefreshIndicator(onRefresh: vm.load, child: ListView(padding: const EdgeInsets.all(16), children: [
          // Profile header
          _Card(child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: AppColors.primaryLight,
              child: Text(p.initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 18))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(p.email, style: const TextStyle(color: AppColors.textSecondary)),
            ])),
          ])),
          if (p.organisation != null) ...[
            const SizedBox(height: 12),
            _Card(child: Row(children: [
              const Icon(Icons.school_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.organisation!.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Code ${p.organisation!.slug} · You see shops for this organisation',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ])),
            ])),
          ],

          const _Section('Account'),
          _Card(padding: EdgeInsets.zero, child: Column(children: [
            ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Name'), subtitle: Text(p.displayName),
              trailing: const Icon(Icons.chevron_right), onTap: () => _editName(vm)),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right), onTap: () => _changePassword(vm)),
          ])),

          const _Section('Notifications'),
          _Card(padding: EdgeInsets.zero, child: SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Order alerts on this phone'),
            subtitle: const Text(kIsWeb ? 'Not available in the web version' : 'Confirmed, preparing, ready for pickup…'),
            value: vm.orderAlertsEnabled && !kIsWeb,
            onChanged: kIsWeb ? null : vm.setOrderAlerts,
          )),

          const _Section('About'),
          const _Card(padding: EdgeInsets.zero,
            child: ListTile(leading: Icon(Icons.info_outline), title: Text('QuickEats'), subtitle: Text('Version 1.0.0'))),

          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error),
              minimumSize: const Size.fromHeight(48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 24),
        ]));
      }),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: AppColors.textSecondary)));
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});
  @override Widget build(BuildContext context) => Container(
    padding: padding, clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: child);
}

/// Single text field dialog; pops with the trimmed text, or null when cancelled.
class _TextDialog extends StatefulWidget {
  final String title, initial, label;
  const _TextDialog({required this.title, required this.initial, required this.label});
  @override State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _c = TextEditingController(text: widget.initial);
  final _form = GlobalKey<FormState>();
  @override Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(key: _form, child: TextFormField(controller: _c, autofocus: true, textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(labelText: widget.label),
      validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : ((v ?? '').trim().length > 100 ? 'Too long' : null))),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () { if (_form.currentState!.validate()) Navigator.pop(context, _c.text.trim()); }, child: const Text('Save')),
    ],
  );
  @override void dispose() { _c.dispose(); super.dispose(); }
}

/// Current + new + confirm password. Calls [onSubmit] and stays open to show server errors.
class _PasswordDialog extends StatefulWidget {
  final Future<String?> Function(String current, String next) onSubmit;
  final String email, name; // the account's own; the new password must not contain them
  const _PasswordDialog({required this.onSubmit, required this.email, required this.name});
  @override State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController(), _next = TextEditingController(), _confirm = TextEditingController();
  final _visible = [false, false, false]; // current, new, confirm
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _next.addListener(() => setState(() {})); // keeps the checklist up to date
  }

  Widget _passwordField(int i, TextEditingController c, String label, String? Function(String?) validator) => TextFormField(
    controller: c,
    obscureText: !_visible[i],
    validator: validator,
    decoration: InputDecoration(labelText: label, suffixIcon: IconButton(
      icon: Icon(_visible[i] ? Icons.visibility : Icons.visibility_off),
      tooltip: _visible[i] ? 'Hide password' : 'Show password',
      onPressed: () => setState(() => _visible[i] = !_visible[i]),
    )),
  );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    final err = await widget.onSubmit(_current.text, _next.text);
    if (!mounted) return;
    if (err == null) { Navigator.pop(context, true); return; }
    setState(() { _busy = false; _error = err; });
  }

  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    scrollable: true,
    content: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      _passwordField(0, _current, 'Current password', (v) => (v ?? '').isEmpty ? 'Required' : null),
      _passwordField(1, _next, 'New password', (v) {
        if ((v ?? '') == _current.text && _current.text.isNotEmpty) return 'Must be different from the current password';
        return PasswordPolicy.validate(v ?? '', email: widget.email, name: widget.name);
      }),
      PasswordRequirements(password: _next.text),
      _passwordField(2, _confirm, 'Confirm new password', (v) => v != _next.text ? 'Passwords don\'t match' : null),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
        child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
    ])),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Change')),
    ],
  );

  @override void dispose() { _current.dispose(); _next.dispose(); _confirm.dispose(); super.dispose(); }
}
