import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/features/import/import_logic.dart';
import 'package:paisa_mobile/features/import/import_providers.dart';
import 'package:crypto/crypto.dart';
import 'package:paisa_mobile/features/import/office_crypto.dart';
import 'package:paisa_mobile/features/import/pdf_statement.dart';

import 'support/fakes.dart';

Uint8List fixtureBytes(String name) => File('test/fixtures/$name').readAsBytesSync();

/// Opens Activity and the import screen at 360dp. The picker answers with
/// [picked] and opening a protected file runs inline, without an isolate.
Future<FakeServer> pumpImport(WidgetTester tester, {PickedFile? picked, String role = 'book_owner', FakeServer? server}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final s = (server ?? FakeServer())..roles = [role];
  final harness = Harness(
    auth: FakeAuth(signedIn: true),
    server: s,
    extra: [
      statementPickerProvider.overrideWithValue(() async => picked),
      decryptorProvider.overrideWithValue((file, password) async => decryptOfficeXlsx(file, password)),
      pdfReaderProvider.overrideWithValue((pdf, password) async => statementCsvFromPdf(pdf, password)),
    ],
  );
  await tester.pumpWidget(await harness.app());
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Activity')));
  await tester.pumpAndSettle();
  if (role == 'book_owner' || role == 'editor') {
    await tester.tap(find.byTooltip('Import a statement'));
    await tester.pumpAndSettle();
  }
  return s;
}

Future<void> choose(WidgetTester tester) async {
  await tester.tap(find.text('Choose a statement file'));
  await tester.pumpAndSettle();
}

Future<void> tapImport(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Import statement');
  // A list builds only what is near the screen, and a PDF's notes push the button
  // past that, so scroll the form first.
  if (button.evaluate().isEmpty) {
    await tester.drag(find.byType(ListView).hitTestable().last, const Offset(0, -600));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  final plain = fixtureBytes('statement.xlsx');
  final plainFile = (name: 'My Statement 4521.xlsx', bytes: plain);
  final protectedFile = (name: 'AccountStatement_08092026.xlsx', bytes: fixtureBytes('statement_encrypted_sha1_aes128.xlsx'));
  final csvBytes = fixtureBytes('statement.csv');
  final csvFile = (name: 'Statement 4521.csv', bytes: csvBytes);
  final pdfPlain = (name: 'Statement 4521.pdf', bytes: fixtureBytes('statement_hdfc_plain.pdf'));
  final pdfLocked = (name: 'AccountStatement_08092026.pdf', bytes: fixtureBytes('statement_hdfc_aes256.pdf'));

  group('who can import', () {
    testWidgets('an editor can, and sees the privacy note before choosing anything', (tester) async {
      await pumpImport(tester, picked: plainFile);
      expect(find.text('Your bank details are not saved'), findsOneWidget);
      expect(find.textContaining('account number, name, address'), findsOneWidget);
      expect(find.text('Choose a statement file'), findsOneWidget);
    });

    testWidgets('a reviewer and a viewer are not offered it', (tester) async {
      for (final role in ['reviewer', 'viewer']) {
        await pumpImport(tester, role: role);
        expect(find.byTooltip('Import a statement'), findsNothing, reason: role);
      }
    });
  });

  group('a plain workbook', () {
    testWidgets('goes up under a generic name, with its hash, and shows the counts', (tester) async {
      final server = await pumpImport(tester, picked: plainFile);
      await choose(tester);
      expect(find.text('My Statement 4521.xlsx'), findsOneWidget, reason: 'the name is shown on screen to the person');
      expect(find.byType(TextField), findsNothing, reason: 'no password asked for a file that has none');
      await tapImport(tester);

      final sent = server.importBodies.single;
      expect(sent['fileName'], 'statement.xlsx', reason: 'the real name is never sent');
      expect(sent['contentType'], xlsxMime);
      expect(base64.decode(sent['content'] as String), plain);
      expect(sent['sha256'], prepareWorkbook(plain).sha256);
      expect(sent.containsKey('accountId'), isFalse);
      expect(find.text('7 entries imported'), findsOneWidget);
      expect(find.text('No problems found'), findsOneWidget);
    });

    testWidgets('importing it again says nothing is new', (tester) async {
      final server = await pumpImport(tester, picked: plainFile);
      await choose(tester);
      await tapImport(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Import a statement'));
      await tester.pumpAndSettle();
      await choose(tester);
      await tapImport(tester);
      expect(server.importBodies, hasLength(2));
      expect(find.text('Nothing new: all 7 entries were already in the ledger.'), findsOneWidget);
    });

    testWidgets('the chosen account is sent', (tester) async {
      final server = await pumpImport(tester, picked: plainFile);
      await choose(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Primary bank').last);
      await tester.pumpAndSettle();
      await tapImport(tester);
      expect(server.importBodies.single['accountId'], 'account_primary');
    });

    testWidgets('warnings are listed, and the rows are said to have been imported', (tester) async {
      final server = FakeServer()
        ..importOverride = (
          status: 201,
          body: {'imported': 5, 'duplicates': 0, 'warnings': ['Balance does not follow on 04/08/26 (NEFT CR) — imported the stated amount anyway'], 'account': {'number': 'X'}},
        );
      await pumpImport(tester, picked: plainFile, server: server);
      await choose(tester);
      await tapImport(tester);
      expect(find.text('Check these'), findsOneWidget);
      expect(find.textContaining('Balance does not follow on 04/08/26'), findsOneWidget);
      expect(find.textContaining('imported with the amounts the statement states'), findsOneWidget);
      expect(find.textContaining('X'), findsNothing, reason: 'the echoed account number is never shown');
    });
  });

  group('a password-protected workbook', () {
    testWidgets('asks for the password and says it stays on the phone', (tester) async {
      await pumpImport(tester, picked: protectedFile);
      await choose(tester);
      expect(find.textContaining('password protected'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Statement password'), findsOneWidget);
      expect(find.text('Used on this phone to open the file. It is never sent or saved.'), findsOneWidget);
    });

    testWidgets('a wrong password says so and sends nothing', (tester) async {
      final server = await pumpImport(tester, picked: protectedFile);
      await choose(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Statement password'), 'not-it');
      await tapImport(tester);
      expect(find.text('That password did not open the file. Check it and try again.'), findsOneWidget);
      expect(server.importBodies, isEmpty);
    });

    testWidgets('no password at all is asked for, not tried', (tester) async {
      final server = await pumpImport(tester, picked: protectedFile);
      await choose(tester);
      await tapImport(tester);
      expect(find.textContaining('Enter the statement'), findsOneWidget);
      expect(server.importBodies, isEmpty);
    });

    testWidgets('the right password sends the opened workbook, never the password', (tester) async {
      final server = await pumpImport(tester, picked: protectedFile);
      await choose(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Statement password'), 'test-password');
      await tapImport(tester);

      final sent = server.importBodies.single;
      expect(base64.decode(sent['content'] as String), plain, reason: 'the server gets the ordinary workbook');
      expect(sent['sha256'], prepareWorkbook(plain).sha256, reason: 'hashed as the opened workbook, so it matches a plain export of the same statement');
      expect(jsonEncode(sent), isNot(contains('test-password')));
      expect(find.text('7 entries imported'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'the password field is gone with the file');
    });

    testWidgets('the password can be shown and hidden', (tester) async {
      await pumpImport(tester, picked: protectedFile);
      await choose(tester);
      EditableText field() => tester.widget<EditableText>(find.descendant(of: find.widgetWithText(TextField, 'Statement password'), matching: find.byType(EditableText)));
      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(field().obscureText, isFalse);
    });

    testWidgets('a kind of protection that cannot be opened says what to do', (tester) async {
      // A compound file that is not an agile-encrypted workbook.
      final bogus = Uint8List(1024)..setRange(0, 8, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]);
      await pumpImport(tester, picked: (name: 'old.xlsx', bytes: bogus));
      await choose(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Statement password'), 'x');
      await tapImport(tester);
      expect(find.textContaining('damaged or is not an Excel file'), findsOneWidget);
    });
  });

  group('a CSV', () {
    testWidgets('goes up as the text it is, under a generic name, with its hash, and shows the counts', (tester) async {
      final server = await pumpImport(tester, picked: csvFile);
      await choose(tester);
      expect(find.text('Statement 4521.csv'), findsOneWidget, reason: 'the name is shown on screen to the person');
      expect(find.byType(TextField), findsNothing, reason: 'a CSV has no password');
      expect(find.textContaining('table of payments'), findsNothing, reason: 'the PDF note is only for a PDF');
      await tapImport(tester);

      final sent = server.importBodies.single;
      expect(sent['fileName'], 'statement.csv', reason: 'the real name is never sent');
      expect(sent['contentType'], 'text/csv');
      expect(sent['content'], utf8.decode(csvBytes));
      expect(sent['sha256'], sha256.convert(csvBytes).toString());
      expect(sent['sizeBytes'], csvBytes.length);
      expect(find.text('4 entries imported'), findsOneWidget);
      expect(find.text('No problems found'), findsOneWidget);
    });

    testWidgets('importing it again says nothing is new', (tester) async {
      await pumpImport(tester, picked: csvFile);
      await choose(tester);
      await tapImport(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Import a statement'));
      await tester.pumpAndSettle();
      await choose(tester);
      await tapImport(tester);
      expect(find.text('Nothing new: all 4 entries were already in the ledger.'), findsOneWidget);
    });

    testWidgets('an older export that is not UTF-8 is read, not refused', (tester) async {
      final latin = Uint8List.fromList([...utf8.encode('Date,Details,Debit,Credit\n01/09/2026,Caf'), 0xe9, ...utf8.encode(' bill,10.00,\n')]);
      final server = await pumpImport(tester, picked: (name: 'old.csv', bytes: latin));
      await choose(tester);
      await tapImport(tester);
      expect(server.importBodies.single['content'], 'Date,Details,Debit,Credit\n01/09/2026,Café bill,10.00,\n');
    });

    testWidgets('a CSV the server cannot read is shown in its own words, and kept for another try', (tester) async {
      final recorded = fixture('import_error_csv_unparseable') as Map<String, dynamic>;
      final server = FakeServer()..importOverride = (status: recorded['status'] as int, body: recorded['body'] as Map<String, dynamic>);
      await pumpImport(tester, picked: csvFile, server: server);
      await choose(tester);
      await tapImport(tester);
      expect(find.text('No transaction table found. The statement needs a header row with Date, Debit and Credit columns.'), findsOneWidget);
      expect(find.text('Statement 4521.csv'), findsOneWidget);
    });

    testWidgets('a CSV over the server\'s 3 MB is refused before it is sent', (tester) async {
      final big = Uint8List.fromList(utf8.encode('Date,Debit\n${'a' * maxCsvChars}'));
      final server = await pumpImport(tester, picked: (name: 'big.csv', bytes: big));
      await choose(tester);
      await tapImport(tester);
      expect(find.textContaining('3 MB of CSV'), findsOneWidget);
      expect(server.importBodies, isEmpty);
    });
  });

  group('a PDF', () {
    testWidgets('that is not protected is read on the phone, and only its table of payments goes up', (tester) async {
      final server = await pumpImport(tester, picked: pdfPlain);
      server.csvImportFixture = 'import_result_pdf';
      await choose(tester);
      expect(find.text('Statement 4521.pdf'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'no password asked for a file that has none');
      expect(find.textContaining('reads this PDF on your phone and sends only its table of payments'), findsOneWidget);
      expect(find.textContaining('not matched against the same statement imported from Excel or CSV'), findsOneWidget);
      await tapImport(tester);

      final sent = server.importBodies.single;
      expect(sent['fileName'], 'statement.csv', reason: 'what goes up is a CSV, under a fixed name');
      expect(sent['contentType'], 'text/csv');
      final content = sent['content'] as String;
      expect(content.split('\n').first, 'Date,Narration,Ref No,Debit,Credit,Balance');
      expect(content, isNot(contains('50100123456789')), reason: 'the account number stays on the phone');
      expect(content, isNot(contains('TEST USER')));
      expect(sent['sha256'], sha256.convert(utf8.encode(content)).toString(), reason: 'hashed as sent');
      expect(sent['sizeBytes'], utf8.encode(content).length);
      expect(find.text('14 entries imported'), findsOneWidget);
      expect(find.text('No problems found'), findsOneWidget);
    });

    testWidgets('importing it again says nothing is new', (tester) async {
      final server = await pumpImport(tester, picked: pdfPlain);
      server.csvImportFixture = 'import_result_pdf';
      await choose(tester);
      await tapImport(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Import a statement'));
      await tester.pumpAndSettle();
      await choose(tester);
      await tapImport(tester);
      expect(server.importBodies, hasLength(2));
      expect(server.importBodies.first['sha256'], server.importBodies.last['sha256']);
      expect(find.text('Nothing new: all 14 entries were already in the ledger.'), findsOneWidget);
    });

    testWidgets('that is protected asks for the password and says it stays on the phone', (tester) async {
      await pumpImport(tester, picked: pdfLocked);
      await choose(tester);
      expect(find.textContaining('password protected'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Statement password'), findsOneWidget);
      expect(find.text('Used on this phone to open the file. It is never sent or saved.'), findsOneWidget);
    });

    testWidgets('a wrong password says so and sends nothing; none at all is asked for, not tried', (tester) async {
      final server = await pumpImport(tester, picked: pdfLocked);
      await choose(tester);
      await tapImport(tester);
      expect(find.textContaining('Enter the statement'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Statement password'), 'not-it');
      await tapImport(tester);
      expect(find.text('That password did not open the file. Check it and try again.'), findsOneWidget);
      expect(server.importBodies, isEmpty);
    });

    testWidgets('the right password sends the table, never the password, and the field goes with the file', (tester) async {
      final server = await pumpImport(tester, picked: pdfLocked);
      server.csvImportFixture = 'import_result_pdf';
      await choose(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Statement password'), 'test-password');
      await tapImport(tester);

      final sent = server.importBodies.single;
      expect(jsonEncode(sent), isNot(contains('test-password')));
      expect(sent['content'], statementCsvFromPdf(fixtureBytes('statement_hdfc_plain.pdf'), ''), reason: 'the same table as the same statement unprotected');
      expect(sent['sha256'], isNot(sha256.convert(pdfLocked.bytes).toString()), reason: 'the hash is of what is sent, not of the PDF');
      expect(find.text('14 entries imported'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a scanned statement says there is no text in it, and what to do', (tester) async {
      final server = await pumpImport(tester, picked: (name: 'scan.pdf', bytes: fixtureBytes('statement_scanned_rc4.pdf')));
      await choose(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Statement password'), 'test-password');
      await tapImport(tester);
      expect(find.textContaining('There is no text in this PDF'), findsOneWidget);
      expect(find.textContaining('Excel (.xlsx) or CSV'), findsOneWidget);
      expect(server.importBodies, isEmpty);
    });

    testWidgets('a file named .pdf that is not one is refused when chosen', (tester) async {
      final server = await pumpImport(tester, picked: (name: 'statement.pdf', bytes: Uint8List.fromList(utf8.encode('Date,Details\n'))));
      await choose(tester);
      expect(find.textContaining('does not look like a PDF'), findsOneWidget);
      expect(find.text('Choose a statement file'), findsOneWidget);
      expect(server.importBodies, isEmpty);
    });
  });

  group('files that cannot be imported', () {
    for (final entry in {'statement.xls': 'not the older .xls', 'statement.docx': 'Choose an Excel (.xlsx), CSV or PDF statement.'}.entries) {
      testWidgets('${entry.key} is refused with its reason, and nothing is selected', (tester) async {
        final server = await pumpImport(tester, picked: (name: entry.key, bytes: Uint8List(10)));
        await choose(tester);
        expect(find.textContaining(entry.value), findsOneWidget);
        expect(find.text('Choose a statement file'), findsOneWidget);
        expect(server.importBodies, isEmpty);
      });
    }

    testWidgets('a workbook over the size the server accepts is refused before it is sent', (tester) async {
      final big = Uint8List(maxWorkbookBytes + 1)..[0] = 0x50..[1] = 0x4b;
      final server = await pumpImport(tester, picked: (name: 'big.xlsx', bytes: big));
      await choose(tester);
      await tapImport(tester);
      expect(find.textContaining('shorter period'), findsOneWidget);
      expect(server.importBodies, isEmpty);
    });

    testWidgets('an empty file is said to be empty, not offered for import', (tester) async {
      final server = await pumpImport(tester, picked: (name: 'statement.xlsx', bytes: Uint8List(0)));
      await choose(tester);
      expect(find.textContaining('That file is empty'), findsOneWidget);
      expect(find.text('Choose a statement file'), findsOneWidget);
      expect(server.importBodies, isEmpty);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      await pumpImport(tester);
      await choose(tester);
      expect(find.text('Choose a statement file'), findsOneWidget);
    });
  });

  group('when the server says no', () {
    testWidgets('too many rows is shown in the server\'s own words, and the file is kept for another try', (tester) async {
      final recorded = fixture('import_error_too_many_rows') as Map<String, dynamic>;
      final server = FakeServer()..importOverride = (status: recorded['status'] as int, body: recorded['body'] as Map<String, dynamic>);
      await pumpImport(tester, picked: plainFile, server: server);
      await choose(tester);
      await tapImport(tester);
      expect(find.textContaining('This statement has 2001 rows; 2000 is the most that can be imported at once'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Import statement'), findsOneWidget);
      expect(find.text('My Statement 4521.xlsx'), findsOneWidget);
    });

    testWidgets('an unreadable file is shown in the server\'s own words', (tester) async {
      final recorded = fixture('import_error_unparseable') as Map<String, dynamic>;
      final server = FakeServer()..importOverride = (status: recorded['status'] as int, body: recorded['body'] as Map<String, dynamic>);
      await pumpImport(tester, picked: plainFile, server: server);
      await choose(tester);
      await tapImport(tester);
      expect(find.text('Not a valid .xlsx file (no ZIP directory found).'), findsOneWidget);
    });

    testWidgets('no connection says nothing was imported', (tester) async {
      final server = FakeServer();
      await pumpImport(tester, picked: plainFile, server: server);
      await choose(tester);
      server.offline = true;
      await tapImport(tester);
      expect(find.textContaining('Cannot reach Paisa'), findsOneWidget);
    });
  });
}
