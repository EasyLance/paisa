import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/features/import/pdf_table.dart';

/// A word 4 units wide for every character, 7.5 tall, `y` down the page.
PositionedWord w(String text, double x0, double y, {bool before = false, bool after = false}) => PositionedWord(text, x0, x0 + text.length * 4, y, 7.5, spaceBefore: before, spaceAfter: after);

/// A right-aligned amount whose right edge is at [right].
PositionedWord amt(String text, double right, double y) => PositionedWord(text, right - text.length * 4, right, y, 7.5);

/// Words of a phrase at [x0], a 4-unit space between them.
List<PositionedWord> phrase(String text, double x0, double y) {
  final out = <PositionedWord>[];
  var x = x0;
  for (final word in text.split(' ')) {
    out.add(w(word, x, y));
    x += word.length * 4 + 4;
  }
  return out;
}

/// A HDFC-like heading at [y]: left-aligned text columns, amounts to the right.
List<PositionedWord> hdfcHeading(double y) => [
  w('Date', 30, y),
  w('Narration', 75, y),
  ...phrase('Chq./Ref.No.', 250, y),
  ...phrase('Value Dt', 320, y),
  ...phrase('Withdrawal Amt.', 380, y),
  ...phrase('Deposit Amt.', 450, y),
  ...phrase('Closing Balance', 510, y),
];

List<PositionedWord> hdfcRow(double y, String date, String narration, String ref, {String debit = '', String credit = '', required String balance}) => [
  w(date, 30, y),
  ...phrase(narration, 75, y),
  if (ref.isNotEmpty) w(ref, 250, y),
  w(date, 320, y),
  if (debit.isNotEmpty) amt(debit, 430, y),
  if (credit.isNotEmpty) amt(credit, 497, y),
  amt(balance, 565, y),
];

/// Mini RFC 4180 reader, written separately from the code under test.
List<List<String>> readCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"' && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (c == '\n') {
      row.add(field.toString());
      rows.add(row);
      row = [];
      field = StringBuffer();
    } else {
      field.write(c);
    }
  }
  return rows;
}

void main() {
  group('a table that looks like a bank\'s', () {
    final page = [
      ...phrase('Example Bank - Statement of Account', 30, 20),
      ...phrase('Account No : 50100123456789', 30, 40),
      ...hdfcHeading(80),
      ...hdfcRow(100, '01/08/26', 'UPI-FRESH MART-fresh1@oksbi', '417776317066', debit: '450.50', balance: '73,784.03'),
      ...hdfcRow(120, '03/08/26', 'NEFT CR-ACME LTD', '890682883607', credit: '1,23,456.78', balance: '1,97,240.81'),
      ...phrase('STATEMENT SUMMARY :-', 30, 160),
      ...phrase('Generated On: 01-SEP-2026', 30, 180),
    ];

    test('keeps the header and the payments, and nothing else on the page', () {
      final csv = statementCsvFromWords([page]);
      expect(readCsv(csv), [
        ['Date', 'Narration', 'Ref No', 'Debit', 'Credit', 'Balance'],
        ['01/08/2026', 'UPI-FRESH MART-fresh1@oksbi', '417776317066', '450.50', '', '73,784.03'],
        ['03/08/2026', 'NEFT CR-ACME LTD', '890682883607', '', '1,23,456.78', '1,97,240.81'],
      ]);
      expect(csv, isNot(contains('50100123456789')));
      expect(csv, isNot(contains('Example Bank')));
      expect(csv, isNot(contains('SUMMARY')));
    });

    test('keeps Indian grouping as printed, for the server to read', () {
      expect(statementCsvFromWords([page]), contains('"1,23,456.78"'));
    });

    test('reads the same rows when the words come in any order', () {
      expect(statementCsvFromWords([page.reversed.toList()]), statementCsvFromWords([page]));
    });

    test('a baseline that wobbles a little still makes one line', () {
      final wobbly = [for (final (i, word) in page.indexed) PositionedWord(word.text, word.x0, word.x1, word.y + (i.isEven ? 0.6 : -0.6), word.height)];
      expect(statementCsvFromWords([wobbly]), statementCsvFromWords([page]));
    });

    test('a description with a comma or a quote is quoted', () {
      final csv = statementCsvFromWords([
        [...hdfcHeading(80), ...hdfcRow(100, '01/08/26', 'SHOP, "BEST" STORE', '', debit: '10.00', balance: '90.00')],
      ]);
      expect(readCsv(csv)[1][1], 'SHOP, "BEST" STORE');
    });
  });

  group('where the headings sit does not decide the columns', () {
    // SBI-like: headings centred over left-aligned text and right-aligned amounts.
    List<PositionedWord> sbi(double y) => [
      w('Txn', 38, y),
      w('Date', 58, y),
      ...phrase('Value Date', 88, y),
      w('Description', 208, y),
      ...phrase('Ref No./Cheque No.', 318, y),
      w('Debit', 396, y),
      w('Credit', 460, y),
      w('Balance', 516, y),
    ];
    List<PositionedWord> sbiRow(double y, List<String> date, String narration, String ref, {String debit = '', String credit = '', required String balance}) => [
      for (var i = 0; i < date.length; i++) w(date[i], 30.0 + i * 14, y),
      for (var i = 0; i < date.length; i++) w(date[i], 85.0 + i * 14, y),
      ...phrase(narration, 140, y),
      w(ref, 320, y),
      if (debit.isNotEmpty) amt(debit, 440, y),
      if (credit.isNotEmpty) amt(credit, 500, y),
      amt(balance, 565, y),
    ];

    test('a date written as 1 Sep 2026 is three words and one date, in the first date column', () {
      final csv = statementCsvFromWords([
        [
          ...sbi(80),
          ...sbiRow(100, ['1', 'Sep', '2026'], 'WDL TFR UPI/DR/1/SHOBHA M/Paid', '152449390926', debit: '999.00', balance: '73,235.53'),
          ...sbiRow(120, ['12', 'Sep', '2026'], 'DEP TFR UPI/CR/1/BOAZ M R', '', credit: '5,000.00', balance: '78,235.53'),
        ],
      ]);
      final rows = readCsv(csv);
      expect(rows[1], ['01/09/2026', 'WDL TFR UPI/DR/1/SHOBHA M/Paid', '152449390926', '999.00', '', '73,235.53']);
      expect(rows[2][0], '12/09/2026');
      expect(rows[2][5], '78,235.53');
    });
  });

  group('dates', () {
    String? dateOf(List<String> first) {
      final csv = statementCsvFromWords([
        [
          ...hdfcHeading(80),
          ...[for (final (i, t) in first.indexed) w(t, 30.0 + i * 14, 100)],
          ...phrase('RENT', 75, 100),
          amt('10.00', 430, 100),
          amt('90.00', 565, 100),
        ],
      ]);
      final rows = readCsv(csv);
      return rows.length > 1 ? rows[1][0] : null;
    }

    test('01/08/26, 01-08-2026, 1.8.26, 01-Aug-2026, 01/Aug/26 and 01 Aug 2026 all become dd/mm/yyyy', () {
      expect(dateOf(['01/08/26']), '01/08/2026');
      expect(dateOf(['01-08-2026']), '01/08/2026');
      expect(dateOf(['1.8.26']), '01/08/2026');
      expect(dateOf(['01-Aug-2026']), '01/08/2026');
      expect(dateOf(['01/Aug/26']), '01/08/2026');
      expect(dateOf(['01', 'Aug', '2026']), '01/08/2026');
      expect(dateOf(['1', 'September,', '26']), '01/09/2026');
    });

    test('a month or day that does not exist is not a date, so there is no payment', () {
      expect(() => dateOf(['31/13/26']), throwsA(noRowsProblem));
      expect(() => dateOf(['32/01/26']), throwsA(noRowsProblem));
      expect(() => dateOf(['01-Foo-2026']), throwsA(noRowsProblem));
    });
  });

  group('a description that wraps', () {
    List<PositionedWord> wrapped(double y, String date, List<String> lines, {required String debit, required String balance}) => [
      w(date, 30, y),
      for (final (i, line) in lines.indexed) ...phrase(line, 75, y + i * 9.5),
      amt(debit, 430, y),
      amt(balance, 565, y),
    ];

    test('is read as one description, and nothing from the next payment joins it', () {
      final csv = statementCsvFromWords([
        [
          ...hdfcHeading(80),
          ...wrapped(100, '01/08/26', ['UPI-FRESH MART-fresh1@oksbi-', 'FDRL0001234-417776317066-PAID VIA', 'UPI'], debit: '450.50', balance: '73,784.03'),
          ...hdfcRow(140, '02/08/26', 'ATM WDL KOCHI', '', debit: '2,000.00', balance: '71,784.03'),
        ],
      ]);
      final rows = readCsv(csv);
      expect(rows, hasLength(3));
      expect(rows[1][1], 'UPI-FRESH MART-fresh1@oksbi- FDRL0001234-417776317066-PAID VIA UPI');
      expect(rows[2][1], 'ATM WDL KOCHI');
    });

    test('cut at a fixed width, a word is put back together, and a space the PDF drew is kept', () {
      // Wrapped lines nearly all 21 characters: a fixed-width wrap. The first
      // line break is inside "royal99@oksbi"; the second has a space the PDF drew.
      List<PositionedWord> fixed(double y, String date, List<(String, bool, bool)> lines) => [
        w(date, 30, y),
        for (final (i, (text, before, after)) in lines.indexed) ...[
          for (final (j, word) in text.trim().split(' ').indexed)
            PositionedWord(
              word,
              75.0 + j * 40,
              75.0 + j * 40 + word.length * 4,
              y + i * 9.5,
              7.5,
              spaceBefore: before && j == 0,
              spaceAfter: after && j == text.trim().split(' ').length - 1,
            ),
        ],
        amt('450.50', 430, y),
        amt('73,784.03', 565, y),
      ];
      final csv = statementCsvFromWords([
        [
          ...hdfcHeading(80),
          ...fixed(100, '01/08/26', [('UPI-FRESH-royal99@oks', false, false), ('bi-FDRL0001234-417776', false, false), ('317066 PAID', false, true), ('VIA UPI', false, false)]),
          ...fixed(150, '02/08/26', [('UPI-FRESH-royal99@oks', false, false), ('bi-FDRL0001234-417776', false, false), ('317066', false, false)]),
        ],
      ]);
      final rows = readCsv(csv);
      expect(rows[1][1], 'UPI-FRESH-royal99@oksbi-FDRL0001234-417776317066 PAID VIA UPI');
      expect(rows[2][1], 'UPI-FRESH-royal99@oksbi-FDRL0001234-417776317066');
    });
  });

  group('where a wrapped description sits in its row', () {
    // Three lines of 9.5 with 8 of padding between rows. [anchor] is which of the
    // three carries the date and the amounts: 0 top, 1 middle, 2 bottom.
    List<PositionedWord> row(double top, int anchor, String name, String date, String debit, String balance) {
      final lines = ['$name first', '$name second line', '$name third'];
      final y = top + anchor * 9.5;
      return [
        for (final (i, line) in lines.indexed) ...phrase(line, 75, top + i * 9.5),
        w(date, 30, y),
        amt(debit, 430, y),
        amt(balance, 565, y),
      ];
    }

    for (final (anchor, where) in [(0, 'top'), (1, 'middle'), (2, 'bottom')]) {
      test('at the $where, each payment gets its own lines', () {
        final csv = statementCsvFromWords([
          [...hdfcHeading(80), ...row(100, anchor, 'AAA', '01/08/26', '10.00', '90.00'), ...row(100 + 28.5 + 8, anchor, 'BBB', '02/08/26', '20.00', '70.00'), ...row(100 + 2 * (28.5 + 8), anchor, 'CCC', '03/08/26', '5.00', '65.00')],
        ]);
        expect([for (final r in readCsv(csv).skip(1)) r[1]], ['AAA first AAA second line AAA third', 'BBB first BBB second line BBB third', 'CCC first CCC second line CCC third']);
      });
    }

    test('packed as tightly as the wrapped lines themselves, a line continues the payment above', () {
      final csv = statementCsvFromWords([
        [
          ...hdfcHeading(80),
          ...row(100, 0, 'AAA', '01/08/26', '10.00', '90.00'),
          ...row(128.5, 0, 'BBB', '02/08/26', '20.00', '70.00'),
        ],
      ]);
      expect([for (final r in readCsv(csv).skip(1)) r[1]], ['AAA first AAA second line AAA third', 'BBB first BBB second line BBB third']);
    });
  });

  group('a table over several pages', () {
    test('carries on with the heading repeated, and drops each page\'s own top and bottom', () {
      List<PositionedWord> furniture(int n) => [...phrase('Example Bank Statement of Account', 30, 20), ...phrase('Account No : 50100123456789 (continued)', 30, 32), ...phrase('Page No .: $n', 250, 800), ...phrase('01-SEP-2026 10:15 Page $n of 2', 30, 812)];
      final csv = statementCsvFromWords([
        [
          ...furniture(1),
          ...hdfcHeading(80),
          ...hdfcRow(100, '01/08/26', 'RENT', '', debit: '100.00', balance: '900.00'),
          ...hdfcRow(120, '02/08/26', 'SALARY', '', credit: '500.00', balance: '1,400.00'),
        ],
        [
          ...furniture(2),
          ...hdfcHeading(80),
          ...hdfcRow(100, '03/08/26', 'GROCERIES', '', debit: '50.00', balance: '1,350.00'),
          ...phrase('STATEMENT SUMMARY :-', 30, 150),
        ],
      ]);
      final rows = readCsv(csv);
      expect([for (final r in rows.skip(1)) r[1]], ['RENT', 'SALARY', 'GROCERIES']);
      expect(csv, isNot(contains('Page')));
      expect(csv, isNot(contains('50100123456789')));
    });

    test('carries on with no heading on the later pages, and a first line that is not a payment is not one', () {
      final csv = statementCsvFromWords([
        [...hdfcHeading(80), ...hdfcRow(100, '01/08/26', 'RENT', '', debit: '100.00', balance: '900.00')],
        [
          ...phrase('Statement of Account (contd.)', 30, 20),
          ...phrase('and a note that wraps along the narration column', 75, 40),
          ...hdfcRow(100, '03/08/26', 'GROCERIES', '', debit: '50.00', balance: '850.00'),
        ],
      ]);
      final rows = readCsv(csv);
      expect([for (final r in rows.skip(1)) r[1]], ['RENT', 'GROCERIES']);
    });

    test('a line under the last payment on a page is a footer unless it sits as close as the other wrapped lines', () {
      List<PositionedWord> page(double footerY) => [
        ...hdfcHeading(80),
        ...hdfcRow(100, '01/08/26', 'RENT', '', debit: '100.00', balance: '900.00'),
        ...phrase('Opening Balance Dr Count', 75, footerY),
      ];
      expect(readCsv(statementCsvFromWords([page(130)]))[1][1], 'RENT');
      expect(readCsv(statementCsvFromWords([page(109.5)]))[1][1], 'RENT', reason: 'a summary heading is not a description even when close');
    });
  });

  group('the heading', () {
    test('a heading stacked over two lines is found', () {
      final stacked = [
        w('Tran', 28, 80),
        w('Date', 28, 90),
        w('Particulars', 140, 90),
        w('Chq', 330, 80),
        w('No.', 330, 90),
        amt('Withdrawal', 455, 80),
        amt('(Dr)', 455, 90),
        amt('Deposit', 515, 80),
        amt('(Cr)', 515, 90),
        amt('Balance', 575, 90),
      ];
      final csv = statementCsvFromWords([
        [
          ...stacked,
          w('01-Aug-2026', 28, 110),
          ...phrase('RENT', 100, 110),
          w('4455', 330, 110),
          amt('100.00', 455, 110),
          amt('900.00Cr', 575, 110),
        ],
      ]);
      expect(readCsv(csv)[1], ['01/08/2026', 'RENT', '4455', '100.00', '', '900.00Cr']);
    });

    test('a statement with no reference or balance column gets none', () {
      final csv = statementCsvFromWords([
        [
          w('Date', 30, 80),
          w('Particulars', 75, 80),
          amt('Debit', 430, 80),
          amt('Credit', 497, 80),
          w('01/08/26', 30, 100),
          ...phrase('RENT', 75, 100),
          amt('10.00', 430, 100),
        ],
      ]);
      expect(readCsv(csv), [
        ['Date', 'Narration', 'Debit', 'Credit'],
        ['01/08/2026', 'RENT', '10.00', ''],
      ]);
    });

    test('words that merely contain a heading word are not a heading', () {
      expect(() => statementCsvFromWords([phrase('Date of Statement : 01/09/2026 Details of the account balance', 30, 40)]), throwsA(noTableProblem));
    });
  });

  group('what it refuses, and says', () {
    test('a page with no text at all is a picture', () {
      expect(() => statementCsvFromWords([[], []]), throwsA(noTextProblem));
      expect(noTextProblem.message, contains('scanned'));
    });

    test('text with no table is not a statement', () {
      expect(() => statementCsvFromWords([phrase('Dear customer, your statement is attached.', 30, 40)]), throwsA(noTableProblem));
    });

    test('a heading with nothing under it is not a statement either', () {
      expect(() => statementCsvFromWords([hdfcHeading(80)]), throwsA(noRowsProblem));
    });

    test('a single amount column with Dr/Cr marks is not understood, and says what is needed', () {
      expect(() => statementCsvFromWords([[w('Date', 30, 80), w('Narration', 75, 80), w('Amount', 400, 80), w('Balance', 500, 80), w('01/08/26', 30, 100), amt('10.00', 440, 100)]]), throwsA(noTableProblem));
      expect(noTableProblem.message, contains('Withdrawal or Debit'));
    });
  });

  test('a row that is a date and a note, with no amount, is not a payment', () {
    final csv = statementCsvFromWords([
      [...hdfcHeading(80), ...hdfcRow(100, '01/08/26', 'RENT', '', debit: '100.00', balance: '900.00'), ...phrase('02/08/26 Statement generated', 30, 112)],
    ]);
    expect(readCsv(csv), hasLength(2));
  });
}
