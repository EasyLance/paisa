import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/features/import/import_logic.dart';
import 'package:paisa_mobile/features/import/office_crypto.dart';
import 'package:paisa_mobile/features/import/pdf_statement.dart';
import 'package:paisa_mobile/features/import/pdf_table.dart';

import 'pdf_table_test.dart' show readCsv;
import 'support/fakes.dart';

// The PDFs are made by `reportlab` and encrypted by `qpdf` (through `pikepdf`):
// nothing to do with the reader under test. Everything in them is invented. The
// expected rows (`pdf_truth.json`) are what the generator drew, not what this code
// read. Layouts imitate what is believed about two banks; no real statement was
// available.
Uint8List pdf(String name) => File('test/fixtures/$name.pdf').readAsBytesSync();

const password = 'test-password';

final truth = jsonDecode(File('test/fixtures/pdf_truth.json').readAsStringSync()) as Map<String, dynamic>;

/// (file, how it is protected, the password it needs)
const fixtures = [
  ('statement_hdfc_plain', 'not protected', ''),
  ('statement_hdfc_aes256', 'AES-256', password),
  ('statement_sbi_rc4', 'RC4 128-bit', password),
  ('statement_multipage_aes128', 'AES-128, three pages, an embedded TrueType font', password),
  ('statement_alt_aes256', 'AES-256, headings over two lines, words drawn one at a time', password),
  ('statement_centered_aes256', 'AES-256, made by a different library: bordered table, each row\'s text centred between its borders', password),
];

void main() {
  for (final (name, how, pw) in fixtures) {
    group('$name ($how)', () {
      final csv = statementCsvFromPdf(pdf(name), pw);
      final rows = readCsv(csv);
      final expected = (truth['$name.pdf'] as List).cast<Map<String, dynamic>>();

      test('has exactly the payments the PDF drew, and nothing else', () {
        expect(rows.first.take(2), ['Date', 'Narration']);
        final hasRef = rows.first.contains('Ref No');
        expect(rows.length - 1, expected.length);
        for (final (i, row) in rows.skip(1).indexed) {
          final t = expected[i];
          final c = hasRef ? row : [row[0], row[1], '', ...row.skip(2)];
          expect({'date': c[0], 'narration': c[1], 'debit': c[3], 'credit': c[4], 'balance': c[5]}, {
            'date': t['date'],
            'narration': t['narration'],
            'debit': t['debit'],
            'credit': t['credit'],
            'balance': t['balance'],
          }, reason: 'row $i');
          if (hasRef) expect(c[2], t['ref'], reason: 'row $i ref');
        }
      });

      test('reads every amount right: the running balance follows on each row', () {
        BigInt paise(String s) => s.isEmpty ? BigInt.zero : BigInt.parse(s.replaceAll(RegExp(r'[,.]|Cr$'), ''));
        final hasRef = rows.first.contains('Ref No');
        final o = hasRef ? 3 : 2;
        var previous = paise(rows[1][o + 2]) - paise(rows[1][o + 1]) + paise(rows[1][o]);
        for (final row in rows.skip(1)) {
          final balance = paise(row[o + 2]);
          expect(previous + paise(row[o + 1]) - paise(row[o]), balance, reason: row.join(' | '));
          previous = balance;
        }
      });

      test('carries no account details, name, address, page furniture or summary', () {
        for (final leak in ['50100123456789', 'TEST USER', 'EXAMPLE APARTMENTS', 'IFSC', 'Page No', 'Registered', 'SUMMARY', 'Generated', 'computer generated', 'Statement of Account', '000012345678', '37791533954']) {
          expect(csv, isNot(contains(leak)));
        }
      });

      test('is what the server was shown when the reply was recorded', () {
        // Only the AES-256 HDFC-like one was posted to the real API; the rest are
        // covered by the checks above and by the same parser run over them in Node.
        if (name != 'statement_hdfc_aes256') return;
        final recorded = (fixture('import_result_pdf') as Map<String, dynamic>)['body'] as Map<String, dynamic>;
        expect(prepareCsv(csv).sha256, recorded['sha256'], reason: 'the CSV changed: record import_result_pdf and import_result_pdf_again again');
        expect(recorded['imported'], expected.length);
        expect(recorded['warnings'], isEmpty);
      });
    });
  }

  group('the password', () {
    test('only the protected ones ask for it', () {
      expect(pdfNeedsPassword(pdf('statement_hdfc_plain')), isFalse);
      for (final name in ['statement_hdfc_aes256', 'statement_sbi_rc4', 'statement_multipage_aes128', 'statement_alt_aes256', 'statement_centered_aes256', 'statement_scanned_rc4']) {
        expect(pdfNeedsPassword(pdf(name)), isTrue, reason: name);
      }
    });

    test('a wrong or empty one is refused for each way of protecting a file', () {
      for (final name in ['statement_hdfc_aes256', 'statement_sbi_rc4', 'statement_multipage_aes128']) {
        expect(() => statementCsvFromPdf(pdf(name), 'not-it'), throwsA(isA<WrongPasswordException>()), reason: name);
        expect(() => statementCsvFromPdf(pdf(name), ''), throwsA(isA<WrongPasswordException>()), reason: name);
      }
    });

    test('the owner password opens a file too, as in any PDF viewer', () {
      // The fixtures' owner password is the user password plus "-owner".
      expect(statementCsvFromPdf(pdf('statement_hdfc_aes256'), '$password-owner'), statementCsvFromPdf(pdf('statement_hdfc_plain'), ''));
    });

    test('opening the same statement protected or not gives the same table, so the same hashes', () {
      final plain = prepareCsv(statementCsvFromPdf(pdf('statement_hdfc_plain'), ''));
      final locked = prepareCsv(statementCsvFromPdf(pdf('statement_hdfc_aes256'), password));
      expect(locked.sha256, plain.sha256);
    });
  });

  group('what is not a statement', () {
    test('a scanned page, which has no text, says so and asks for another kind of file', () {
      expect(() => statementCsvFromPdf(pdf('statement_scanned_rc4'), password), throwsA(noTextProblem));
      expect(noTextProblem.message, allOf(contains('scanned'), contains('.xlsx')));
    });

    test('something that is not a PDF is refused in words', () {
      expect(() => statementCsvFromPdf(Uint8List.fromList(utf8.encode('Date,Details\n')), ''), throwsA(isA<ImportProblem>().having((e) => e.message, 'message', contains('PDF'))));
      expect(looksLikePdf(pdf('statement_hdfc_plain')), isTrue);
      expect(looksLikePdf(Uint8List(10)), isFalse);
      expect(pdfNeedsPassword(Uint8List(10)), isFalse);
    });

    test('a truncated PDF is reported as damaged, not as a crash', () {
      final bytes = pdf('statement_hdfc_plain');
      expect(() => statementCsvFromPdf(Uint8List.sublistView(bytes, 0, bytes.length ~/ 2), ''), throwsA(isA<ImportProblem>().having((e) => e.message, 'message', contains('could not be read'))));
    });
  });
}
