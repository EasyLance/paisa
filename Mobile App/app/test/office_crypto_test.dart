import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/features/import/office_crypto.dart';

// The fixtures are synthetic (no real account) and were encrypted by an
// independent library (Python's msoffcrypto-tool) with the password
// "test-password", so these tests check the phone against someone else's
// implementation of the spec, not against itself. Two schemes: SHA-1 with
// AES-128, which is what Excel wrote for the real statement this was built for,
// and SHA-512 with AES-256, the library's default.
Uint8List load(String name) => File('test/fixtures/$name').readAsBytesSync();

void main() {
  final plain = load('statement.xlsx');

  for (final scheme in ['sha1_aes128', 'sha512_aes256']) {
    group(scheme, () {
      final encrypted = load('statement_encrypted_$scheme.xlsx');

      test('is recognised as encrypted, and a plain workbook is not', () {
        expect(isOfficeEncrypted(encrypted), isTrue);
        expect(isOfficeEncrypted(plain), isFalse);
      });

      test('opens with the right password and gives back the original workbook byte for byte', () {
        expect(decryptOfficeXlsx(encrypted, 'test-password'), plain);
      });

      test('says so for a wrong password, and for one that differs only in case', () {
        expect(() => decryptOfficeXlsx(encrypted, 'wrong'), throwsA(isA<WrongPasswordException>()));
        expect(() => decryptOfficeXlsx(encrypted, 'Test-Password'), throwsA(isA<WrongPasswordException>()));
        expect(() => decryptOfficeXlsx(encrypted, ''), throwsA(isA<WrongPasswordException>()));
      });
    });
  }

  test('a file that is not a compound file is refused, not crashed on', () {
    expect(() => decryptOfficeXlsx(plain, 'x'), throwsA(isA<UnsupportedEncryptionException>()));
    expect(() => decryptOfficeXlsx(Uint8List(0), 'x'), throwsA(isA<UnsupportedEncryptionException>()));
  });

  test('a damaged encrypted file is refused, not crashed on', () {
    final encrypted = load('statement_encrypted_sha1_aes128.xlsx');
    for (final cut in [600, 1500, encrypted.length ~/ 2]) {
      expect(() => decryptOfficeXlsx(Uint8List.sublistView(encrypted, 0, cut), 'test-password'), throwsA(anyOf(isA<UnsupportedEncryptionException>(), isA<WrongPasswordException>())));
    }
  });
}
