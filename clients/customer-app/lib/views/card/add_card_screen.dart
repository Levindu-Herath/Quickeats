import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:quickeats_customer/core/constants/app_colors.dart';
import 'package:quickeats_customer/viewmodels/card_viewmodel.dart';
import 'package:quickeats_customer/views/card/card_visual.dart';

/// Form to add a card (replacing the current one). Pops with true once saved, so
/// callers like checkout can carry on straight away.
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key});
  @override State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _holder = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final c in [_number, _holder, _expiry]) { c.addListener(() => setState(() {})); }
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) context.read<CardViewModel>().clearErrors(); });
  }

  @override
  void dispose() {
    for (final c in [_number, _holder, _expiry, _cvv]) { c.dispose(); }
    super.dispose();
  }

  String get _digits => _number.text.replaceAll(' ', '');

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final parts = _expiry.text.split('/');
    final vm = context.read<CardViewModel>();
    final ok = await vm.addCard(
      number: _digits,
      holderName: _holder.text.trim(),
      expMonth: int.parse(parts[0]),
      expYear: 2000 + int.parse(parts[1]),
      cvv: _cvv.text,
    );
    if (ok && mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CardViewModel>();
    final brand = detectCardBrand(_digits);
    return Scaffold(
      appBar: AppBar(title: const Text('Add Card', style: TextStyle(fontWeight: FontWeight.w700)), backgroundColor: AppColors.white, elevation: 0),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CardVisual(brand: brand, number: _number.text, holder: _holder.text, expiry: _expiry.text),
        const SizedBox(height: 25),

        TextFormField(
          controller: _number,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.creditCardNumber],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(19), _CardNumberFormatter()],
          decoration: _decoration('Card number', Icons.credit_card, errorText: vm.fieldErrors['number'],
              suffix: brand == 'Card' ? null : Padding(padding: const EdgeInsets.only(right: 12), child: Text(brand, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)))),
          validator: (_) {
            final d = _digits;
            if (d.length < 13) return 'Enter the full card number';
            if (!_luhnValid(d)) return 'This card number is not valid';
            return null;
          },
        ),
        const SizedBox(height: 14),

        TextFormField(
          controller: _holder,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.creditCardName],
          decoration: _decoration('Name on card', Icons.person_outline, errorText: vm.fieldErrors['holderName']),
          validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the name on the card' : null,
        ),
        const SizedBox(height: 14),

        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: TextFormField(
            controller: _expiry,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.creditCardExpirationDate],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4), _ExpiryFormatter()],
            decoration: _decoration('Expiry (MM/YY)', Icons.event_outlined, errorText: vm.fieldErrors['expiry']),
            validator: _validateExpiry,
          )),
          const SizedBox(width: 12),
          Expanded(child: TextFormField(
            controller: _cvv,
            keyboardType: TextInputType.number,
            obscureText: true,
            autofillHints: const [AutofillHints.creditCardSecurityCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: _decoration('CVV', Icons.lock_outline, errorText: vm.fieldErrors['cvv']),
            validator: (v) => (v == null || v.length < 3) ? 'Enter the 3 or 4 digit code' : null,
          )),
        ]),
        const SizedBox(height: 16),

        if (vm.error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(vm.error!, style: const TextStyle(color: AppColors.error))),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.shield_outlined, size: 18, color: AppColors.textSecondary),
            SizedBox(width: 8),
            Expanded(child: Text('We only keep the last 4 digits. Your CVV is never stored.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
          ]),
        ),
        const SizedBox(height: 20),

        SizedBox(height: 54, child: FilledButton(
          onPressed: vm.isSaving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: vm.isSaving
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save card', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        )),
      ]))),
    );
  }

  InputDecoration _decoration(String label, IconData icon, {String? errorText, Widget? suffix}) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    suffixIcon: suffix,
    suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    errorText: errorText,
    filled: true,
    fillColor: AppColors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  String? _validateExpiry(String? v) {
    final parts = (v ?? '').split('/');
    if (parts.length != 2 || parts[1].length != 2) return 'Use MM/YY';
    final month = int.tryParse(parts[0]) ?? 0;
    final year = 2000 + (int.tryParse(parts[1]) ?? 0);
    if (month < 1 || month > 12) return 'Invalid month';
    final now = DateTime.now();
    if (year < now.year || (year == now.year && month < now.month)) return 'Card has expired';
    return null;
  }
}

bool _luhnValid(String digits) {
  var sum = 0;
  var dbl = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var d = int.parse(digits[i]);
    if (dbl) { d *= 2; if (d > 9) d -= 9; }
    sum += d;
    dbl = !dbl;
  }
  return sum % 10 == 0;
}

/// Groups card digits in fours: 4242 4242 4242 4242.
class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(' ', '');
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Inserts the slash in MM/YY.
class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll('/', '');
    final text = digits.length > 2 ? '${digits.substring(0, 2)}/${digits.substring(2)}' : digits;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
