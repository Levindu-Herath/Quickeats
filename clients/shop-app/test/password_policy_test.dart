import 'package:flutter_test/flutter_test.dart';
import 'package:quickeats_shop/views/widgets/password_policy.dart';

// The same cases as the identity service's domain/password_test.go.
void main() {
  String? check(String pw) => PasswordPolicy.validate(pw, email: 'nimal.perera@ruh.ac.lk', name: 'Nimal Perera');

  test('accepts strong passwords', () {
    for (final pw in ['Canteen#Dev2026', 'Kottu&Tea49', 'Mango juice 4 me!', 'Ünïcode-Pässwörd7', 'Ab1!' * 18]) {
      expect(check(pw), isNull, reason: pw);
    }
  });

  test('rejects weak passwords with the reason', () {
    const cases = {
      'Ab1!xyz': 'at least 8',
      ' Kottu&Tea49': 'start or end with a space',
      'kottu&tea49': 'uppercase',
      'KOTTU&TEA49': 'lowercase',
      'Kottu&Teaxy': 'number',
      'KottuTea4913': 'symbol',
      'Kottu&Teaaa49': 'repeated or 4 sequential',
      'Kottu&Tea1234': 'repeated or 4 sequential',
      'Kottu&Tea9876': 'repeated or 4 sequential',
      'Password1!': 'too common',
      'P@ssw0rd!!9': 'too common',
      'Qwerty@2024': 'too common',
      'Welcome@123x': 'too common',
      'Dr@g0n!x9': 'too common',
      'Nimal.Perera#5': 'email',
      'Perera#Rocks5': 'name',
    };
    cases.forEach((pw, want) => expect(check(pw), contains(want), reason: pw));
    expect(check('Ab1!' * 18 + 'x'), contains('at most 72'));
  });

  test('checklist', () {
    final met = PasswordPolicy.requirements.map((r) => r.isMet('Kottu&Tea')).toList();
    expect(met, [true, true, true, false, true]); // no number yet
  });
}
