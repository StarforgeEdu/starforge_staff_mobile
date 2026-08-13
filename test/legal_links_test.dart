import 'package:flutter_test/flutter_test.dart';
import 'package:starforge_staff/core/legal_links.dart';

void main() {
  test('privacy policy release link accepts only credential-free HTTPS', () {
    expect(
      privacyPolicyUriFrom('https://starforge.example/privacy'),
      Uri.parse('https://starforge.example/privacy'),
    );

    for (final unsafe in const [
      '',
      'http://starforge.example/privacy',
      'file:///private/policy.html',
      'intent://privacy',
      'javascript:alert(1)',
      'https://user:secret@starforge.example/privacy',
      'https:///privacy',
    ]) {
      expect(privacyPolicyUriFrom(unsafe), isNull, reason: unsafe);
    }
  });
}
