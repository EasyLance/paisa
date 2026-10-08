import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/features/import/import_logic.dart';
import 'package:paisa_mobile/features/import/import_providers.dart';
import 'package:paisa_mobile/features/import/office_crypto.dart';

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
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  final plain = fixtureBytes('statement.xlsx');
  final plainFile = (name: 'My Statement 4521.xlsx', bytes: plain);
  final protectedFile = (name: 'AccountStatement_08092026.xlsx', bytes: fixtureBytes('statement_encrypted_sha1_aes128.xlsx'));

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

  group('files that cannot be imported', () {
    for (final entry in {'statement.pdf': 'PDF statements cannot be imported yet', 'statement.csv': 'CSV statements cannot be imported from the phone yet', 'statement.xls': 'not the older .xls'}.entries) {
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
