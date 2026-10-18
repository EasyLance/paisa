// Rebuilds a bank statement's table of payments from words with positions, and
// writes it as CSV for the server's own statement parser. Pure Dart over a plain
// list of words so it is tested without a PDF; `pdf_statement.dart` is the part
// that reads a real file.
//
// Believed layout (no real bank PDF was available to check it against): one
// header row naming Date, a description, Withdrawal/Debit, Deposit/Credit and
// optionally Balance and a reference; every payment starts with its date on the
// left; a long description wraps onto the lines below it; the table may carry on
// over several pages with or without the header repeated.
import 'import_logic.dart';

/// One word on a page. `y` grows **down** the page; `height` is the font height.
class PositionedWord {
  const PositionedWord(this.text, this.x0, this.x1, this.y, this.height, {this.spaceBefore = false, this.spaceAfter = false});

  final String text;
  final double x0;
  final double x1;
  final double y;
  final double height;

  /// Whether the PDF's own text had a space just before or after this word. It is
  /// what tells a wrapped description's line break at a space from one in a word.
  final bool spaceBefore;
  final bool spaceAfter;

  @override
  String toString() => 'PositionedWord($text @ ${x0.toStringAsFixed(1)}..${x1.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

const noTextProblem = ImportProblem(
  'There is no text in this PDF, so it is probably a scanned picture of the statement. Paisa cannot read pictures. Download the statement from your bank as an Excel (.xlsx) or CSV file instead.',
);
const noTableProblem = ImportProblem(
  'Paisa could not find the table of payments in this PDF. It looks for a row of headings with Date, a description (Narration or Particulars), Withdrawal or Debit, and Deposit or Credit. Download the statement from your bank as an Excel (.xlsx) or CSV file instead.',
);
const noRowsProblem = ImportProblem(
  'Paisa found the columns of the table but no payments under them, each starting with its date. Download the statement from your bank as an Excel (.xlsx) or CSV file instead.',
);

/// CSV with only a header row and one row for each payment, in the column names
/// the server looks for. Everything else on the pages is dropped here.
String statementCsvFromWords(List<List<PositionedWord>> pages) {
  final all = [for (final page in pages) ...page];
  if (all.isEmpty) throw noTextProblem;
  final heights = [for (final w in all) w.height]..sort();
  final bodyHeight = heights[heights.length ~/ 2];

  final lines = [for (var p = 0; p < pages.length; p++) ..._linesOf(p, pages[p], bodyHeight * 0.45)];
  final header = _findHeader(lines);
  if (header == null) throw noTableProblem;

  // Everything from the header down, page by page. A line that starts with a date
  // (and carries an amount: a date alone is a footer such as "01-SEP-2026 10:15
  // Page 1") starts a payment. The other lines belong to the payment above or
  // below them, which `_share` decides from the gaps.
  final seq = lines.sublist(header.end - 1);
  final rows = <_Row>[];
  final anchorAt = <int>[];
  for (var i = 1; i < seq.length; i++) {
    final date = _leadingDate(seq[i].words);
    if (date != null && seq[i].words.any((w) => _amount.hasMatch(w.text))) {
      rows.add(_Row(seq[i], date));
      anchorAt.add(i);
    }
  }
  if (rows.isEmpty) throw noRowsProblem;
  for (var r = 0; r <= rows.length; r++) {
    final from = r == 0 ? 0 : anchorAt[r - 1];
    final to = r == rows.length ? seq.length : anchorAt[r];
    final before = seq[from];
    final between = seq.sublist(from + 1, to);
    final onPage = [
      for (final l in between)
        if (l.page == before.page) l,
    ];
    final previous = r == 0 ? null : rows[r - 1];
    final next = r == rows.length ? null : rows[r];
    if (next != null && next.first.page == before.page) {
      final toPrevious = _share(before, onPage, next.first);
      previous?.below.addAll(onPage.take(toPrevious));
      next.above.addAll(onPage.skip(toPrevious));
    } else {
      // The page ends here: what follows the last payment is its tail, or footer.
      previous?.below.addAll(onPage);
      // Over the page, a repeated heading says where the next table starts.
      final rest = between.skip(onPage.length).toList();
      final h = rest.lastIndexWhere((l) => _isHeader(_cellsOf(l.words)));
      if (next != null && h >= 0) {
        final after = rest.sublist(h + 1).where((l) => l.page == next.first.page).toList();
        next.above.addAll(after.skip(_share(rest[h], after, next.first)));
      }
    }
  }

  bool isLastOnPage(int i) => i == rows.length - 1 || rows[i + 1].first.page != rows[i].first.page;
  final inkLines = <_Line>[header.line, if (header.second != null) header.second!];
  for (var i = 0; i < rows.length; i++) {
    inkLines.addAll(rows[i].above);
    inkLines.add(rows[i].first);
    var previous = rows[i].first;
    for (final line in rows[i].below) {
      // The last payment on a page is followed by footers and summaries, so only
      // lines close under it can be its own.
      if (isLastOnPage(i) && line.y - previous.y > 1.6 * line.height) break;
      inkLines.add(line);
      previous = line;
    }
  }
  // ponytail: one set of columns for every page, from the first heading. A
  // statement that shifts its columns between pages would need them per page.
  final columns = _Columns.build(header.cells, [for (final l in inkLines) ...l.words], bodyHeight * 0.45);

  // Lines under the last payment on a page only continue it if they sit as close
  // as the wrapped lines inside the other payments do.
  var tailGap = 1.6 * bodyHeight;
  var widest = 0.0;
  for (var i = 0; i < rows.length; i++) {
    if (!isLastOnPage(i)) {
      rows[i].attach(columns, null);
      widest = [widest, ...rows[i].gaps].reduce((a, b) => a > b ? a : b);
    }
  }
  if (widest > 0) tailGap = widest * 1.1;
  for (var i = 0; i < rows.length; i++) {
    if (isLastOnPage(i)) rows[i].attach(columns, tailGap);
  }

  // A bank that wraps descriptions at a fixed number of characters cuts words in
  // two, so nearly every wrapped line is exactly as long as the longest. A bank
  // that wraps at spaces leaves lines of all lengths. Three wrapped lines is the
  // least that says which this is.
  final wrapped = [for (final row in rows) ...row.lengths.take(row.lengths.length - 1)];
  final longest = wrapped.fold(0, (a, b) => a > b ? a : b);
  final cutLength = wrapped.length >= 3 && wrapped.where((n) => n == longest).length >= 0.7 * wrapped.length ? longest : 0;

  final hasRef = columns.has('ref');
  final hasBalance = columns.has('balance');
  final out = StringBuffer('Date,Narration,${hasRef ? 'Ref No,' : ''}Debit,Credit${hasBalance ? ',Balance' : ''}\n');
  for (final row in rows) {
    final cells = row.cells(columns, cutLength);
    out.writeln(
      [
        row.date,
        cells['text'],
        if (hasRef) cells['ref'],
        cells['debit'],
        cells['credit'],
        if (hasBalance) cells['balance'],
      ].map((v) => _csvField(v ?? '')).join(','),
    );
  }
  return out.toString();
}

/// How many of [between], the lines between one payment's line [before] and the
/// next [after], belong to the payment before. A bank may set a wrapped
/// description at the top of its row, the middle or the bottom; either way the
/// row's own lines sit closer together than the padding between two rows, so the
/// widest gap is the border. With no clear widest gap (rows packed as tightly as
/// wrapped lines) a line is taken to continue the payment above it.
int _share(_Line before, List<_Line> between, _Line after) {
  if (between.isEmpty) return 0;
  final ys = [before.y, for (final l in between) l.y, after.y];
  final gaps = [for (var i = 0; i < ys.length - 1; i++) ys[i + 1] - ys[i]];
  var widest = 0;
  for (var i = 1; i < gaps.length; i++) {
    if (gaps[i] > gaps[widest]) widest = i;
  }
  final others = [
    for (var i = 0; i < gaps.length; i++)
      if (i != widest) gaps[i],
  ];
  final second = others.reduce((a, b) => a > b ? a : b);
  return gaps[widest] > 1.15 * second ? widest : between.length;
}

String _csvField(String value) => value.contains(RegExp('[",\n\r]')) ? '"${value.replaceAll('"', '""')}"' : value;

// ---- lines -----------------------------------------------------------------

class _Line {
  _Line(this.page, this.words)
    : y = words.map((w) => w.y).reduce((a, b) => a + b) / words.length,
      height = words.map((w) => w.height).reduce((a, b) => a > b ? a : b);

  final int page;
  final List<PositionedWord> words;
  final double y;
  final double height;

  String get text => words.map((w) => w.text).join(' ');
}

List<_Line> _linesOf(int page, List<PositionedWord> words, double tolerance) {
  final byY = [...words]..sort((a, b) => a.y.compareTo(b.y));
  final groups = <List<PositionedWord>>[];
  var sum = 0.0;
  for (final word in byY) {
    if (groups.isNotEmpty && (word.y - sum / groups.last.length).abs() <= tolerance) {
      groups.last.add(word);
      sum += word.y;
    } else {
      groups.add([word]);
      sum = word.y;
    }
  }
  return [for (final group in groups) _Line(page, _dedupe(group..sort((a, b) => a.x0.compareTo(b.x0))))];
}

/// Some PDFs draw a word twice, a hair apart, to fake bold.
List<PositionedWord> _dedupe(List<PositionedWord> sorted) {
  final out = <PositionedWord>[];
  for (final word in sorted) {
    if (out.isNotEmpty && out.last.text == word.text && (out.last.x0 - word.x0).abs() < 0.5 * word.height) continue;
    out.add(word);
  }
  return out;
}

// ---- header ----------------------------------------------------------------

class _Cell {
  _Cell(PositionedWord first, this.cls) : x0 = first.x0, x1 = first.x1;
  String? cls;
  double x0;
  double x1;
  double get center => (x0 + x1) / 2;
}

/// What a heading word means, or null. Matches parts of words because a bank
/// runs them together ("Chq./Ref.No.").
String? _classOf(String raw) {
  final w = raw.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
  if (w.isEmpty) return null;
  if (w.contains('narration') || w.contains('description') || w.contains('particular') || w.contains('detail') || w.contains('remark')) return 'text';
  if (w.contains('withdraw') || w == 'debit' || w == 'debits' || w == 'dr') return 'debit';
  if (w.contains('deposit') || w == 'credit' || w == 'credits' || w == 'cr') return 'credit';
  if (w.contains('balance')) return 'balance';
  if (w.contains('chq') || w.contains('cheque') || w.startsWith('ref')) return 'ref';
  if (w == 'date' || w == 'dt') return 'date';
  if (w == 'value') return 'value';
  return null;
}

/// Splits a row of headings into cells: a new cell starts at a wide gap, or at a
/// word that means something different from the cell so far ("Debit Credit").
List<_Cell> _cellsOf(List<PositionedWord> words) {
  final cells = <_Cell>[];
  for (final word in words) {
    final cls = _classOf(word.text);
    if (cells.isNotEmpty) {
      final cell = cells.last;
      final wide = word.x0 - cell.x1 > 0.9 * word.height;
      final differs = cls != null && cell.cls != null && cls != cell.cls && !(cell.cls == 'value' && cls == 'date');
      if (!wide && !differs) {
        cell.x1 = word.x1 > cell.x1 ? word.x1 : cell.x1;
        if (word.x0 < cell.x0) cell.x0 = word.x0;
        if (cell.cls == 'value' && cls == 'date') {
          cell.cls = 'vdate';
        } else {
          cell.cls ??= cls;
        }
        continue;
      }
    }
    cells.add(_Cell(word, cls));
  }
  return [
    for (final cell in cells)
      if (cell.cls != null && cell.cls != 'value') cell,
  ];
}

bool _isHeader(List<_Cell> cells) {
  final have = {for (final c in cells) c.cls};
  return have.containsAll(const ['date', 'text', 'debit', 'credit']);
}

class _Header {
  _Header(this.line, this.second, this.cells, this.end);
  final _Line line;
  final _Line? second;
  final List<_Cell> cells;

  /// Index of the first line after the heading.
  final int end;
}

_Header? _findHeader(List<_Line> lines) {
  for (var i = 0; i < lines.length; i++) {
    final cells = _cellsOf(lines[i].words);
    if (!_isHeader(cells)) continue;
    // The line may be the lower half of a stacked heading ("Chq" over "No.").
    // The line above belongs to it when it is close and mostly heading words.
    if (i > 0 && lines[i - 1].page == lines[i].page) {
      final above = lines[i - 1];
      final classed = above.words.where((w) => _classOf(w.text) != null).length;
      if (lines[i].y - above.y <= 1.8 * above.height && classed * 2 >= above.words.length) {
        final merged = _cellsOf([...above.words, ...lines[i].words]..sort((p, q) => p.x0.compareTo(q.x0)));
        if (_isHeader(merged)) return _Header(above, lines[i], merged, i + 1);
      }
    }
    return _Header(lines[i], null, cells, i + 1);
  }
  // Some banks stack a heading over two lines ("Withdrawal" above "Amt.").
  for (var i = 0; i + 1 < lines.length; i++) {
    final a = lines[i];
    final b = lines[i + 1];
    if (a.page != b.page || b.y - a.y > 2.2 * a.height) continue;
    final cells = _cellsOf([...a.words, ...b.words]..sort((p, q) => p.x0.compareTo(q.x0)));
    if (_isHeader(cells)) return _Header(a, b, cells, i + 2);
  }
  return null;
}

// ---- columns ---------------------------------------------------------------

/// The table's columns, found from where ink is, not from where the headings
/// are: a heading may be centred over a left-aligned column or right-aligned over
/// numbers. A vertical strip no word crosses, on any row, is a gutter.
class _Columns {
  _Columns(this.bands, this.cells);

  final List<_Band> bands;
  final List<_Cell> cells;

  static _Columns build(List<_Cell> cells, List<PositionedWord> ink, double gutter) {
    final sorted = [...ink]..sort((a, b) => a.x0.compareTo(b.x0));
    final bands = <_Band>[];
    for (final word in sorted) {
      if (bands.isNotEmpty && word.x0 - bands.last.x1 < gutter) {
        if (word.x1 > bands.last.x1) bands.last.x1 = word.x1;
      } else {
        bands.add(_Band(word.x0, word.x1));
      }
    }
    for (final cell in cells) {
      var best = bands.first;
      for (final band in bands) {
        if ((cell.center - (band.x0 + band.x1) / 2).abs() < (cell.center - (best.x0 + best.x1) / 2).abs()) best = band;
        if (cell.center >= band.x0 && cell.center <= band.x1) {
          best = band;
          break;
        }
      }
      best.cells.add(cell);
    }
    // A strip with no heading is a chance gap inside a column, not a column:
    // it joins the neighbour across the narrower gutter.
    while (true) {
      final i = bands.indexWhere((b) => b.cells.isEmpty);
      if (i < 0) break;
      final left = i > 0 ? bands[i].x0 - bands[i - 1].x1 : double.infinity;
      final right = i < bands.length - 1 ? bands[i + 1].x0 - bands[i].x1 : double.infinity;
      if (left == double.infinity && right == double.infinity) break;
      final into = left <= right ? bands[i - 1] : bands[i + 1];
      into.x0 = into.x0 < bands[i].x0 ? into.x0 : bands[i].x0;
      into.x1 = into.x1 > bands[i].x1 ? into.x1 : bands[i].x1;
      bands.removeAt(i);
    }
    return _Columns(bands, cells);
  }

  bool has(String cls) => cells.any((c) => c.cls == cls);

  String? classOf(PositionedWord word) {
    final center = (word.x0 + word.x1) / 2;
    _Band? band;
    var distance = double.infinity;
    for (final candidate in bands) {
      final d = center < candidate.x0 ? candidate.x0 - center : (center > candidate.x1 ? center - candidate.x1 : 0.0);
      if (d < distance) {
        distance = d;
        band = candidate;
      }
    }
    if (band == null || band.cells.isEmpty) return null;
    if (band.cells.length == 1) return band.cells.first.cls;
    // Two headings share a strip. Numbers go to the nearer amount heading by left
    // edge, right edge or middle; anything else is left-aligned text and belongs
    // to the last heading that starts at or before it.
    final amountCells = [
      for (final c in band.cells)
        if (_numeric.contains(c.cls)) c,
    ];
    final textCells = [
      for (final c in band.cells)
        if (!_numeric.contains(c.cls)) c,
    ]..sort((a, b) => a.x0.compareTo(b.x0));
    if ((_amount.hasMatch(word.text) && amountCells.isNotEmpty) || textCells.isEmpty) {
      _Cell? best;
      var bestDistance = double.infinity;
      for (final cell in amountCells) {
        final d = [(word.x0 - cell.x0).abs(), (word.x1 - cell.x1).abs(), (center - cell.center).abs()].reduce((a, b) => a < b ? a : b);
        if (d < bestDistance) {
          bestDistance = d;
          best = cell;
        }
      }
      return best?.cls;
    }
    var chosen = textCells.first;
    for (final cell in textCells) {
      if (cell.x0 <= word.x0 + 0.5 * word.height) chosen = cell;
    }
    return chosen.cls;
  }
}

const _numeric = {'debit', 'credit', 'balance'};

class _Band {
  _Band(this.x0, this.x1);
  double x0;
  double x1;
  final cells = <_Cell>[];
}

// ---- rows ------------------------------------------------------------------

const _months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};

class _LeadingDate {
  const _LeadingDate(this.text, this.words);
  final String text;
  final int words;
}

/// A date at the start of the line: 01/08/26, 01-08-2026, 01 Aug 2026, 01-Aug-26.
/// Written as dd/mm/yyyy, which is what the server reads.
_LeadingDate? _leadingDate(List<PositionedWord> words) {
  String? format(String d, String m, String y) {
    final day = int.parse(d);
    final month = int.tryParse(m) ?? _months[m.toLowerCase().substring(0, 3)];
    if (month == null || month < 1 || month > 12 || day < 1 || day > 31) return null;
    final year = y.length == 2 ? '20$y' : y;
    return '${day.toString().padLeft(2, '0')}/${month.toString().padLeft(2, '0')}/$year';
  }

  final numeric = RegExp(r'^(\d{1,2})[/\-.](\d{1,2}|[A-Za-z]{3,9})[/\-.](\d{4}|\d{2})$').firstMatch(words.first.text);
  if (numeric != null) {
    final text = format(numeric[1]!, numeric[2]!, numeric[3]!);
    return text == null ? null : _LeadingDate(text, 1);
  }
  if (words.length >= 3 &&
      RegExp(r'^\d{1,2}$').hasMatch(words[0].text) &&
      RegExp(r'^[A-Za-z]{3,9},?$').hasMatch(words[1].text) &&
      RegExp(r'^(\d{4}|\d{2})$').hasMatch(words[2].text)) {
    final text = format(words[0].text, words[1].text.replaceAll(',', ''), words[2].text);
    return text == null ? null : _LeadingDate(text, 3);
  }
  return null;
}

// ponytail: needs the paise, as every Indian statement prints them; a bank that
// prints "1,000" with none would need this loosened.
final _amount = RegExp(r'^-?[\d,]+\.\d{2}(cr|dr)?$', caseSensitive: false);

final _endOfTable = RegExp(
  r'statement summary|opening balance|closing balance|brought forward|carried forward|total|generated|computer generated|page no|end of statement|registered office',
  caseSensitive: false,
);

class _Row {
  _Row(this.first, _LeadingDate date) : date = date.text, _dateWords = date.words;

  final _Line first;
  final String date;
  final int _dateWords;
  final above = <_Line>[];
  final below = <_Line>[];

  /// Where the payment's own line is among [lines].
  var _anchor = 0;

  /// Each line's words by column, for the first line and every line attached.
  final lines = <Map<String, List<PositionedWord>>>[];

  /// Gaps between the lines that were attached under the first.
  final gaps = <double>[];
  final pieces = <String>[];
  final _edges = <(bool, bool)>[];

  /// A line's length in characters as the PDF drew it, spaces at its ends included.
  final lengths = <int>[];

  void attach(_Columns columns, double? maxGap) {
    lines.clear();
    gaps.clear();
    pieces.clear();
    _edges.clear();
    lengths.clear();
    Map<String, List<PositionedWord>> split(List<PositionedWord> words) {
      final by = <String, List<PositionedWord>>{};
      for (final word in words) {
        final cls = columns.classOf(word);
        if (cls != null) (by[cls] ??= []).add(word);
      }
      return by;
    }

    void note(Map<String, List<PositionedWord>> by) {
      lines.add(by);
      final text = by['text'] ?? const [];
      pieces.add(text.map((w) => w.text).join(' '));
      final edges = (text.isNotEmpty && text.first.spaceBefore, text.isNotEmpty && text.last.spaceAfter);
      _edges.add(edges);
      lengths.add(pieces.last.length + (edges.$1 ? 1 : 0) + (edges.$2 ? 1 : 0));
    }

    // Lines above the payment's own: nearest first, until one is not a description.
    final heads = <Map<String, List<PositionedWord>>>[];
    for (final line in above.reversed) {
      final by = split(line.words);
      if (by.keys.any((k) => k != 'text' && k != 'ref')) break;
      heads.insert(0, by);
    }
    heads.forEach(note);
    _anchor = lines.length;
    note(split(first.words.sublist(_dateWords)));
    var previous = first;
    for (final line in below) {
      if (maxGap != null && line.y - previous.y > maxGap) break;
      final by = split(line.words);
      // Only the description (and a reference) may carry on; an amount or a date
      // means this is something else.
      if (by.keys.any((k) => k != 'text' && k != 'ref')) break;
      if (maxGap != null && _endOfTable.hasMatch(line.text)) break;
      note(by);
      gaps.add(line.y - previous.y);
      previous = line;
    }
  }

  Map<String, String> cells(_Columns columns, int cutLength) {
    String join(String cls) => [for (final by in lines) ...?by[cls]].map((w) => w.text).join(' ');
    String amount(String cls) => [
      for (final by in lines.skip(_anchor).take(1)) ...?by[cls],
    ].map((w) => w.text).join('').replaceFirst(RegExp(r'^(rs\.?|inr|₹)', caseSensitive: false), '').replaceAll(RegExp(r'^-+$'), '');
    final text = StringBuffer();
    for (var i = 0; i < pieces.length; i++) {
      if (pieces[i].isEmpty) continue;
      if (text.isNotEmpty) {
        // ponytail: with a fixed-width wrap, a line of full length is taken to be
        // cut inside a word unless the PDF's own text has a space there. A
        // statement with fewer than three wrapped lines is joined with spaces, so
        // a cut word can show a stray space; the words are all there.
        final space = _edges[i - 1].$2 || _edges[i].$1 || cutLength == 0 || lengths[i - 1] < cutLength;
        if (space) text.write(' ');
      }
      text.write(pieces[i]);
    }
    return {'text': text.toString(), 'ref': join('ref'), 'debit': amount('debit'), 'credit': amount('credit'), 'balance': amount('balance')};
  }
}
