import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:quickeats_customer/core/constants/app_colors.dart';

/// The password rules, the same as the identity service's (domain/password.go), so a
/// password is refused here with the same message before it's sent.
class PasswordPolicy {
  PasswordPolicy._();

  static const minLength = 8;
  static const _maxBytes = 72; // bcrypt only uses the first 72 bytes

  /// The rules shown as a checklist while typing.
  static const requirements = [
    PasswordRequirement('At least 8 characters', _longEnough),
    PasswordRequirement('An uppercase letter (A-Z)', _hasUpper),
    PasswordRequirement('A lowercase letter (a-z)', _hasLower),
    PasswordRequirement('A number (0-9)', _hasDigit),
    PasswordRequirement('A symbol, like ! @ # \$', _hasSymbol),
  ];

  static const _commonWords = {
    'password', 'passw', 'pass', 'qwerty', 'qwertyuiop', 'asdf', 'asdfgh', 'zxcvbn', 'letmein', 'welcome',
    'admin', 'administrator', 'iloveyou', 'monkey', 'dragon', 'football', 'sunshine', 'princess', 'login',
    'master', 'hello', 'freedom', 'whatever', 'trustno', 'abc', 'abcd', 'test', 'user', 'secret', 'changeme',
    'quickeats', 'food', 'canteen',
  };
  static const _leet = {'@': 'a', '4': 'a', '0': 'o', '1': 'i', '!': 'i', '3': 'e', '\$': 's', '5': 's', '7': 't'};

  /// Why [password] isn't allowed, or null when it is. [email] and [name] are the
  /// account's own, which the password must not contain.
  static String? validate(String password, {String email = '', String name = ''}) {
    if (password.isEmpty) return 'Enter a password';
    if (!_longEnough(password)) return 'Password must be at least 8 characters';
    if (utf8.encode(password).length > _maxBytes) return 'Password must be at most 72 characters';
    if (password.trim() != password) return 'Password can\'t start or end with a space';
    if (!_hasUpper(password)) return 'Password needs an uppercase letter';
    if (!_hasLower(password)) return 'Password needs a lowercase letter';
    if (!_hasDigit(password)) return 'Password needs a number';
    if (!_hasSymbol(password)) return 'Password needs a symbol, like ! @ # \$';
    if (_hasRun(password)) return 'Password can\'t have 3 repeated or 4 sequential characters, like aaa or 1234';

    final lowered = password.toLowerCase();
    if (_isCommon(lowered)) return 'Password is too common';
    final local = email.trim().toLowerCase().split('@').first;
    if (local.length >= 3 && lowered.contains(local)) return 'Password can\'t contain your email address';
    for (final part in name.toLowerCase().split(RegExp(r'\s+'))) {
      if (part.runes.length >= 3 && lowered.contains(part)) return 'Password can\'t contain your name';
    }
    return null;
  }

  static bool _isLetter(String c) => c.toLowerCase() != c.toUpperCase();
  static Iterable<String> _chars(String s) => s.runes.map(String.fromCharCode);

  static bool _longEnough(String p) => p.runes.length >= minLength;
  static bool _hasUpper(String p) => _chars(p).any((c) => _isLetter(c) && c == c.toUpperCase());
  static bool _hasLower(String p) => _chars(p).any((c) => _isLetter(c) && c == c.toLowerCase());
  static bool _hasDigit(String p) => p.contains(RegExp(r'[0-9]'));
  static bool _hasSymbol(String p) =>
    _chars(p).any((c) => !_isLetter(c) && !RegExp(r'[0-9]').hasMatch(c) && c.trim().isNotEmpty);

  /// 3 identical characters in a row ("aaa") or 4 consecutive going up or down ("1234", "dcba").
  static bool _hasRun(String p) {
    final rs = p.toLowerCase().runes.toList();
    var same = 1, up = 1, down = 1;
    for (var i = 1; i < rs.length; i++) {
      same = rs[i] == rs[i - 1] ? same + 1 : 1;
      up = rs[i] == rs[i - 1] + 1 ? up + 1 : 1;
      down = rs[i] == rs[i - 1] - 1 ? down + 1 : 1;
      if (same >= 3 || up >= 4 || down >= 4) return true;
    }
    return false;
  }

  /// A common word with at most two characters added, read as is or with swaps like @ for a undone.
  static bool _isCommon(String lowered) {
    String letters(String s) => _chars(s).where(_isLetter).join();
    final unswapped = _chars(lowered).map((c) => _leet[c] ?? c).join();
    for (final candidate in [letters(lowered), letters(unswapped)]) {
      if (_commonWords.contains(candidate)) return true;
      if (_commonWords.any((w) => w.length >= 5 && candidate.contains(w) && candidate.length - w.length <= 2)) return true;
    }
    return false;
  }
}

class PasswordRequirement {
  final String label;
  final bool Function(String) isMet;
  const PasswordRequirement(this.label, this.isMet);
}

/// Live checklist of [PasswordPolicy.requirements] for the password being typed.
class PasswordRequirements extends StatelessWidget {
  final String password;
  const PasswordRequirements({super.key, required this.password});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, left: 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final r in PasswordPolicy.requirements)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Icon(r.isMet(password) ? Icons.check_circle : Icons.radio_button_unchecked, size: 16,
              color: r.isMet(password) ? AppColors.secondary : AppColors.textMuted),
            const SizedBox(width: 8),
            Flexible(child: Text(r.label, style: TextStyle(fontSize: 12,
              color: r.isMet(password) ? AppColors.textPrimary : AppColors.textSecondary))),
          ]),
        ),
    ]),
  );
}
