import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:quickeats_shop/core/constants/app_colors.dart';
import 'package:quickeats_shop/models/organisation.dart';
import 'package:quickeats_shop/viewmodels/auth_viewmodel.dart';
import 'package:quickeats_shop/viewmodels/settings_viewmodel.dart';
import 'package:quickeats_shop/views/widgets/password_policy.dart';
import 'package:quickeats_shop/views/widgets/org_codes_field.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Organisation>? _orgDraft; // unsaved edits to the organisation codes
  bool _savingOrgs = false;
  bool _togglingOpen = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: loading notifies listeners, which must not happen mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<SettingsViewModel>().load(); });
  }

  void _toast(String text, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), backgroundColor: error ? AppColors.error : null, behavior: SnackBarBehavior.floating));

  Future<void> _report(Future<String?> action, String success) async {
    final err = await action;
    if (mounted) _toast(err ?? success, error: err != null);
  }

  Future<void> _editName(SettingsViewModel vm) async {
    final values = await showDialog<List<String>>(context: context, builder: (_) => _FieldsDialog(
      title: 'Your name', fields: [_DialogField('Full name', vm.profile!.displayName)]));
    if (values != null) await _report(vm.updateDisplayName(values[0]), 'Name updated');
  }

  Future<void> _editShop(SettingsViewModel vm) async {
    final values = await showDialog<List<String>>(context: context, builder: (_) => _FieldsDialog(
      title: 'Shop details',
      fields: [_DialogField('Shop name', vm.shop!.name), _DialogField('Description', vm.shop!.description, required: false, maxLines: 3)]));
    if (values != null) await _report(vm.updateShopDetails(values[0], values[1]), 'Shop updated');
  }

  Future<void> _changePassword(SettingsViewModel vm) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _PasswordDialog(
      onSubmit: vm.changePassword, email: vm.profile?.email ?? '', name: vm.profile?.displayName ?? ''));
    if (ok == true && mounted) _toast('Password changed');
  }

  Future<void> _setOpen(SettingsViewModel vm, bool open) async {
    setState(() => _togglingOpen = true);
    await _report(vm.setOpen(open), open ? 'Shop is open for orders' : 'Shop is closed. Customers can\'t order.');
    if (mounted) setState(() => _togglingOpen = false);
  }

  Future<void> _saveOrgs(SettingsViewModel vm) async {
    final draft = _orgDraft;
    if (draft == null) return;
    if (draft.isEmpty) { _toast('Keep at least one organisation code', error: true); return; }
    setState(() => _savingOrgs = true);
    final err = await vm.saveOrganisations(draft);
    if (!mounted) return;
    setState(() { _savingOrgs = false; if (err == null) _orgDraft = null; });
    _toast(err ?? 'Organisation codes saved', error: err != null);
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text('You will stop receiving live orders on this device.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log out')),
      ],
    ));
    if (ok != true || !mounted) return;
    context.read<SettingsViewModel>().clear();
    await context.read<AuthViewModel>().logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
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
            TextButton(onPressed: _logout, child: const Text('Log out')),
          ]));
        }
        final shop = vm.shop;
        final orgs = _orgDraft ?? p.shopOrganisations;
        final orgsChanged = _orgDraft != null;

        return RefreshIndicator(onRefresh: vm.load, child: ListView(padding: const EdgeInsets.all(16), children: [
          _Card(child: Row(children: [
            CircleAvatar(radius: 28, backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(p.initials, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 18))),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(p.email, style: const TextStyle(color: AppColors.textSecondary)),
            ])),
          ])),

          if (shop != null) ...[
            const _Section('Shop'),
            _Card(padding: EdgeInsets.zero, child: Column(children: [
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(shop.description.isEmpty ? 'No description' : shop.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editShop(vm),
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: Icon(shop.isOpen ? Icons.lock_open : Icons.lock_outline, color: shop.isOpen ? AppColors.secondary : AppColors.textMuted),
                title: const Text('Open for orders'),
                subtitle: Text(shop.isOpen ? 'Customers can place orders' : 'Closed: customers can\'t order'),
                value: shop.isOpen,
                onChanged: _togglingOpen ? null : (v) => _setOpen(vm, v),
              ),
            ])),

            const _Section('Organisations'),
            _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Customers of these organisations can see and order from your shop.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              OrgCodesField(value: orgs, enabled: !_savingOrgs, onChanged: (v) => setState(() => _orgDraft = v)),
              if (orgsChanged) ...[
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: _savingOrgs ? null : () => setState(() => _orgDraft = null), child: const Text('Discard')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _savingOrgs || orgs.isEmpty ? null : () => _saveOrgs(vm),
                    child: Text(_savingOrgs ? 'Saving…' : 'Save codes')),
                ]),
              ],
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

          const _Section('About'),
          const _Card(padding: EdgeInsets.zero,
            child: ListTile(leading: Icon(Icons.info_outline), title: Text('QuickEats Shop'), subtitle: Text('Version 1.0.0'))),

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
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: AppColors.textSecondary)));
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding, clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
    child: child);
}

class _DialogField {
  final String label, initial;
  final bool required;
  final int maxLines;
  const _DialogField(this.label, this.initial, {this.required = true, this.maxLines = 1});
}

/// Edits one or more text fields; pops with the trimmed values, or null when cancelled.
class _FieldsDialog extends StatefulWidget {
  final String title;
  final List<_DialogField> fields;
  const _FieldsDialog({required this.title, required this.fields});
  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  final _form = GlobalKey<FormState>();
  late final _controllers = [for (final f in widget.fields) TextEditingController(text: f.initial)];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < widget.fields.length; i++)
        TextFormField(
          controller: _controllers[i],
          autofocus: i == 0,
          maxLines: widget.fields[i].maxLines,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: widget.fields[i].label),
          validator: (v) => widget.fields[i].required && (v ?? '').trim().isEmpty ? 'Required' : null,
        ),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () { if (_form.currentState!.validate()) Navigator.pop(context, [for (final c in _controllers) c.text.trim()]); },
        child: const Text('Save')),
    ],
  );

  @override
  void dispose() { for (final c in _controllers) { c.dispose(); } super.dispose(); }
}

/// Current + new + confirm password. Calls [onSubmit] and stays open to show server errors.
class _PasswordDialog extends StatefulWidget {
  final Future<String?> Function(String current, String next) onSubmit;
  final String email, name; // the account's own; the new password must not contain them
  const _PasswordDialog({required this.onSubmit, required this.email, required this.name});
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
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

  @override
  Widget build(BuildContext context) => AlertDialog(
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

  @override
  void dispose() { _current.dispose(); _next.dispose(); _confirm.dispose(); super.dispose(); }
}
