// Reads a bank's PDF statement on the phone: opens it (with the password, if it
// has one), takes the words and their positions off each page, and hands them to
// `pdf_table.dart`. Pure Dart (`pdf_cos`, `pdf_document`, `pdf_graphics`, all
// Apache-2.0), so it runs in `flutter test` and needs no native code. The
// password is used here and nowhere else.
import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart' as cos;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'import_logic.dart';
import 'office_crypto.dart' show UnsupportedEncryptionException, WrongPasswordException;
import 'pdf_table.dart';

bool looksLikePdf(Uint8List bytes) {
  final head = String.fromCharCodes(bytes.take(1024));
  return head.contains('%PDF-');
}

/// Whether this PDF asks for a password to open. A file locked only against
/// printing or copying opens without one, so it is not "protected" here.
bool pdfNeedsPassword(Uint8List bytes) {
  if (!looksLikePdf(bytes)) return false;
  try {
    PdfDocument.open(bytes);
    return false;
  } on cos.CosPasswordException {
    return true;
  } catch (_) {
    // Damaged files are reported when the import is tried, with the reason.
    return false;
  }
}

/// The statement's table as CSV, ready to send. Throws [WrongPasswordException],
/// [UnsupportedEncryptionException] or an [ImportProblem] in words for the person.
String statementCsvFromPdf(Uint8List bytes, String password) {
  if (!looksLikePdf(bytes)) throw const ImportProblem('This does not look like a PDF file.');
  // The reader rebuilds a cut-off file as best it can and finds no text in it,
  // which would read as "scanned". Every complete PDF ends with %%EOF.
  if (!String.fromCharCodes(bytes.skip(bytes.length > 1024 ? bytes.length - 1024 : 0)).contains('%%EOF')) throw _damaged;
  final PdfDocument document;
  try {
    document = PdfDocument.open(bytes, password: password);
  } on cos.CosPasswordException {
    throw const WrongPasswordException();
  } on cos.UnsupportedEncryptionException {
    throw const UnsupportedEncryptionException(
      'This PDF is protected in a way Paisa cannot open. Ask the bank for an unprotected copy, or open it in a PDF viewer and print it to a new PDF',
    );
  } on cos.CosParseException {
    throw _damaged;
  }
  try {
    return statementCsvFromWords([for (var i = 0; i < document.pageCount; i++) _wordsOf(PdfTextExtractor.extract(document, i))]);
  } on ImportProblem {
    rethrow;
  } catch (_) {
    throw _damaged;
  }
}

const _damaged = ImportProblem('This PDF could not be read. It may be damaged. Download the statement from your bank again.');

/// A run is one piece of text the PDF drew; it is cut into words at its spaces,
/// each placed using the PDF's own advance for every character.
List<PositionedWord> _wordsOf(PdfPageText page) {
  final words = <PositionedWord>[];
  for (final run in page.runs) {
    final text = run.text;
    if (text.isEmpty) continue;
    final m = run.transform;
    final height = run.bounds.height > 0 ? run.bounds.height : m.a.abs();
    // Where character i starts, in page space. Without the PDF's advances, spread
    // the run evenly over its box.
    final offsets = run.charOffsets;
    double at(int i) => offsets != null && i < offsets.length ? m.e + m.a * offsets[i] : run.bounds.left + run.bounds.width * i / text.length;
    var i = 0;
    while (i < text.length) {
      if (_isSpace(text.codeUnitAt(i))) {
        i++;
        continue;
      }
      var j = i;
      while (j < text.length && !_isSpace(text.codeUnitAt(j))) {
        j++;
      }
      words.add(PositionedWord(text.substring(i, j), at(i), at(j), -m.f, height, spaceBefore: i > 0, spaceAfter: j < text.length));
      i = j;
    }
  }
  return _joinTouching(words);
}

bool _isSpace(int unit) => unit == 0x20 || unit == 0xa0 || unit == 0x09 || unit == 0x0a || unit == 0x0d;

/// A PDF that kerns a number by drawing it in pieces ("1,0" then "00.00") leaves
/// the pieces touching; they are one word.
List<PositionedWord> _joinTouching(List<PositionedWord> words) {
  final out = <PositionedWord>[];
  for (final word in words) {
    final last = out.isEmpty ? null : out.last;
    if (last != null &&
        !last.spaceAfter &&
        !word.spaceBefore &&
        (last.y - word.y).abs() < 0.3 * word.height &&
        word.x0 >= last.x1 - 0.1 * word.height &&
        word.x0 - last.x1 < 0.1 * word.height) {
      out[out.length - 1] = PositionedWord(
        '${last.text}${word.text}',
        last.x0,
        word.x1,
        last.y,
        last.height,
        spaceBefore: last.spaceBefore,
        spaceAfter: word.spaceAfter,
      );
    } else {
      out.add(word);
    }
  }
  return out;
}
