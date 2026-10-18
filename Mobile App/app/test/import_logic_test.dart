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
    test('.xlsx, .csv and .pdf, whatever the capitals', () {
      for (final name in ['statement.xlsx', 'STATEMENT.XLSX', 'a.csv', 'A.Csv', 'a.pdf', 'AccountStatement_08092026.PDF']) {
        expect(refusalForName(name), isNull, reason: name);
      }
      expect(kindOfName('a.xlsx'), StatementKind.xlsx);
      expect(kindOfName('a.csv'), StatementKind.csv);
      expect(kindOfName('a.PDF'), StatementKind.pdf);
    });

    test('everything else is refused with a reason that says what to do', () {
      expect(refusalForName('a.xls'), contains('.xlsx'));
      expect(refusalForName('a.docx'), 'Choose an Excel (.xlsx), CSV or PDF statement.');
      expect(refusalForName('noextension'), 'Choose an Excel (.xlsx), CSV or PDF statement.');
      expect(kindOfName('a.xls'), isNull);
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

    test('a workbook goes up as a workbook', () {
      final body = prepareWorkbook(real).body();
      expect(body['fileName'], 'statement.xlsx');
      expect(body['contentType'], xlsxMime);
    });

    test('something that is not a workbook is refused', () {
      expect(() => prepareWorkbook(Uint8List.fromList([1, 2, 3, 4, 5])), throwsA(isA<ImportProblem>()));
      expect(() => prepareWorkbook(Uint8List(0)), throwsA(isA<ImportProblem>()));
    });
  });

  group('a CSV', () {
    final bankCsv = File('test/fixtures/statement.csv').readAsBytesSync();

    test('is sent as the text it is, under a fixed name, hashed as sent', () {
      final prepared = prepareCsv(decodeCsv(bankCsv));
      final body = prepared.body();
      expect(body['fileName'], 'statement.csv', reason: 'never the real name');
      expect(body['contentType'], 'text/csv');
      expect(body['content'], utf8.decode(bankCsv));
      expect(prepared.sha256, sha256.convert(bankCsv).toString());
      expect(prepared.sizeBytes, bankCsv.length);
      expect(prepared.body(accountId: 'acc_1')['accountId'], 'acc_1');
    });

    test('is the same file the recorded reply was for', () {
      final recorded = (fixture('import_result_csv') as Map<String, dynamic>)['body'] as Map<String, dynamic>;
      expect(prepareCsv(decodeCsv(bankCsv)).sha256, recorded['sha256']);
      expect(recorded['contentType'], 'text/csv');
      final result = ImportResult.fromJson(recorded);
      expect((result.imported, result.duplicates), (4, 0));
      expect(result.warnings, isEmpty);
      final again = ImportResult.fromJson((fixture('import_result_csv_again') as Map<String, dynamic>)['body'] as Map<String, dynamic>);
      expect((again.imported, again.duplicates), (0, 4));
    });

    test('loses a byte-order mark and keeps everything else', () {
      expect(decodeCsv(Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode('Date,Debit\n')])), 'Date,Debit\n');
      expect(decodeCsv(Uint8List.fromList(utf8.encode('Date,Details\n01/09/2026,"UPI ₹ café"\n'))), contains('₹ café'));
    });

    test('is read as Windows-1252 when it is not UTF-8, instead of failing', () {
      // 0xE9 is é, 0x92 is a curly apostrophe and 0xA0 a no-break space in Windows-1252.
      final bytes = Uint8List.fromList([...'Caf'.codeUnits, 0xe9, ...' Joe'.codeUnits, 0x92, ...'s'.codeUnits, 0xa0, ...'bill'.codeUnits]);
      expect(() => utf8.decode(bytes), throwsFormatException, reason: 'the setup: this is not valid UTF-8');
      expect(decodeCsv(bytes), 'Caf\u00e9 Joe\u2019s\u00a0bill');
    });

    test('an empty file, or one that is not text, is refused in words', () {
      expect(() => prepareCsv(''), throwsA(isA<ImportProblem>().having((e) => e.message, 'message', contains('nothing in it'))));
      expect(() => prepareCsv('  \n '), throwsA(isA<ImportProblem>()));
      expect(() => prepareCsv(decodeCsv(Uint8List.fromList([0x50, 0x4b, 3, 4, 0, 0, 0]))), throwsA(isA<ImportProblem>().having((e) => e.message, 'message', contains('CSV'))));
    });

    test('the ceiling is the server\'s 3 MB of text, counted in characters', () {
      expect(maxCsvChars, 3145728);
      final ok = 'Date,Debit\n${'a' * (maxCsvChars - 11)}';
      expect(ok.length, maxCsvChars);
      expect(prepareCsv(ok).sizeBytes, maxCsvChars);
      expect(() => prepareCsv('$ok!'), throwsA(isA<ImportProblem>().having((e) => e.message, 'message', allOf(contains('3 MB'), contains('shorter period')))));
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
