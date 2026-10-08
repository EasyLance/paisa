import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/api/models.dart';
import 'package:paisa_mobile/features/import/import_logic.dart';

import 'support/fakes.dart';

Uint8List workbook(int length) => Uint8List(length)
  ..[0] = 0x50
  ..[1] = 0x4b;

void main() {
  group('which files are accepted', () {
    test('only .xlsx, whatever the capitals', () {
      expect(refusalForName('statement.xlsx'), isNull);
      expect(refusalForName('STATEMENT.XLSX'), isNull);
    });

    test('everything else is refused with a reason that says what to do', () {
      expect(refusalForName('a.pdf'), contains('PDF'));
      expect(refusalForName('a.csv'), contains('CSV'));
      expect(refusalForName('a.xls'), contains('.xlsx'));
      expect(refusalForName('a.docx'), 'Choose an Excel (.xlsx) statement.');
      expect(refusalForName('noextension'), 'Choose an Excel (.xlsx) statement.');
    });
  });

  group('preparing the upload', () {
    final real = File('test/fixtures/statement.xlsx').readAsBytesSync();

    test('hashes and encodes the workbook itself', () {
      final prepared = prepareWorkbook(real);
      expect(prepared.sha256, sha256.convert(real).toString());
      expect(base64.decode(prepared.content), real);
      expect(prepared.sizeBytes, real.length);
    });

    test('never sends the file name, which a bank may have put the account number in', () {
      final body = prepareWorkbook(real).body();
      expect(body['fileName'], 'statement.xlsx');
      expect(body['contentType'], xlsxMime);
      expect(body.containsKey('accountId'), isFalse);
      expect(prepareWorkbook(real).body(accountId: 'acc_1')['accountId'], 'acc_1');
    });

    test('the ceiling is exactly what fits in the server\'s 3 MB base64 string', () {
      expect(maxWorkbookBytes, 2359296);
      expect(base64.encode(Uint8List(maxWorkbookBytes)).length, lessThanOrEqualTo(3 * 1024 * 1024));
      expect(prepareWorkbook(workbook(maxWorkbookBytes)).sizeBytes, maxWorkbookBytes);
      expect(() => prepareWorkbook(workbook(maxWorkbookBytes + 1)), throwsA(isA<ImportProblem>().having((e) => e.message, 'message', contains('shorter period'))));
      expect(base64.encode(Uint8List(maxWorkbookBytes + 3)).length, greaterThan(3 * 1024 * 1024), reason: 'and a little more would not fit');
    });

    test('something that is not a workbook is refused', () {
      expect(() => prepareWorkbook(Uint8List.fromList([1, 2, 3, 4, 5])), throwsA(isA<ImportProblem>()));
      expect(() => prepareWorkbook(Uint8List(0)), throwsA(isA<ImportProblem>()));
    });
  });

  group('the headline', () {
    ImportResult r(int imported, int duplicates) => ImportResult(imported: imported, duplicates: duplicates, warnings: const []);

    test('uses the web\'s words', () {
      expect(importHeadline(r(17, 3)), '17 entries imported, 3 already in the ledger');
      expect(importHeadline(r(172, 0)), '172 entries imported');
      expect(importHeadline(r(1, 0)), '1 entry imported');
    });

    test('says "nothing new" for a repeat, and does not claim an import that did not happen', () {
      expect(importHeadline(r(0, 7)), 'Nothing new: all 7 entries were already in the ledger.');
      expect(importHeadline(r(0, 1)), 'Nothing new: that entry was already in the ledger.');
      expect(importHeadline(r(0, 0)), 'No entries were imported.');
    });
  });

  test('the reply is read for counts and warnings, and the account number it carries is left alone', () {
    final recorded = (fixture('import_result') as Map<String, dynamic>)['body'] as Map<String, dynamic>;
    expect(recorded.containsKey('account'), isTrue, reason: 'the server does echo it');
    final result = ImportResult.fromJson(recorded);
    expect(result.imported, 7);
    expect(result.duplicates, 0);
    expect(result.warnings, isEmpty);
  });

  test('file sizes read as people write them', () {
    expect(fileSize(900), '1 KB');
    expect(fileSize(13824), '14 KB');
    expect(fileSize(2 * 1024 * 1024), '2.0 MB');
  });
}
