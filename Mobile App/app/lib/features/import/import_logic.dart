// Pure rules for importing a statement, so they can be tested without a widget.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/api/models.dart';

const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const csvMime = 'text/csv';

/// The server takes a CSV as text of at most 3 MB, counted in characters.
const maxCsvChars = 3 * 1024 * 1024;

/// The server takes the workbook as a base64 string of at most 3 MB, and base64
/// is four characters for every three bytes, so this is the biggest workbook it
/// will accept. The web has the same ceiling.
const maxWorkbookBytes = 3 * 1024 * 1024 ~/ 4 * 3;

/// The server's cap on a file's size. Anything bigger is refused before it is read.
const maxPickedBytes = 10 * 1024 * 1024;

/// Something the person can fix, in words they can act on.
class ImportProblem implements Exception {
  const ImportProblem(this.message);
  final String message;
  @override
  String toString() => 'ImportProblem($message)';
}

enum StatementKind { xlsx, csv, pdf }

/// Which kind of statement a file is, by its name, or null if it is not one.
StatementKind? kindOfName(String name) {
  final dot = name.lastIndexOf('.');
  return switch (dot < 0 ? '' : name.substring(dot + 1).toLowerCase()) {
    'xlsx' => StatementKind.xlsx,
    'csv' => StatementKind.csv,
    'pdf' => StatementKind.pdf,
    _ => null,
  };
}

/// Why a chosen file cannot be imported, judged by its name, or null if it can.
/// Other kinds are named rather than greyed out, so nobody wonders why a file
/// they can see will not work.
String? refusalForName(String name) {
  if (kindOfName(name) != null) return null;
  return name.toLowerCase().endsWith('.xls') ? 'Paisa reads .xlsx files, not the older .xls. Open it in Excel and save it as .xlsx.' : 'Choose an Excel (.xlsx), CSV or PDF statement.';
}

/// What goes to the server. The file's own name is never sent: a bank often puts
/// the account number in it, and the server has no use for it.
class PreparedStatement {
  const PreparedStatement({required this.fileName, required this.contentType, required this.sizeBytes, required this.sha256, required this.content});

  final String fileName;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final String content;

  Map<String, Object?> body({String? accountId}) => {
    'fileName': fileName,
    'contentType': contentType,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'content': content,
    'accountId': ?accountId,
  };
}

/// Check an open (already decrypted) workbook and get it ready to send. The hash
/// is of the workbook itself, so the same statement exported twice, or once
/// protected and once not, is the same file to the server.
PreparedStatement prepareWorkbook(Uint8List workbook) {
  if (workbook.length < 4 || workbook[0] != 0x50 || workbook[1] != 0x4b) {
    throw const ImportProblem('This does not look like an Excel (.xlsx) file.');
  }
  if (workbook.length > maxWorkbookBytes) {
    final mb = (workbook.length / (1024 * 1024)).toStringAsFixed(1);
    throw ImportProblem('This statement is $mb MB and Paisa can import up to about 2.2 MB at once. Download a shorter period from your bank, such as one month, and import each part.');
  }
  return PreparedStatement(fileName: 'statement.xlsx', contentType: xlsxMime, sizeBytes: workbook.length, sha256: sha256.convert(workbook).toString(), content: base64.encode(workbook));
}

/// Windows-1252's 0x80-0x9F, the only bytes where it differs from Latin-1.
const _windows1252 = [
  0x20ac, 0x81, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021, 0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8d, 0x017d, 0x8f, //
  0x90, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014, 0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0x9d, 0x017e, 0x0178,
];

/// A CSV's text: UTF-8 with any byte-order mark removed, or, for a file that is
/// not valid UTF-8 (older bank exports are Windows-1252), read that way instead of failing.
String decodeCsv(Uint8List bytes) {
  String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    text = String.fromCharCodes([for (final b in bytes) b >= 0x80 && b < 0xa0 ? _windows1252[b - 0x80] : b]);
  }
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

/// Check a CSV's text (a bank's own file, or one the phone built from a PDF) and
/// get it ready to send. The hash is of the text as sent, in UTF-8.
PreparedStatement prepareCsv(String text) {
  if (text.trim().isEmpty) throw const ImportProblem('That file has nothing in it, so there is nothing to import.');
  // A spreadsheet or picture renamed to .csv shows up as control characters.
  if (text.contains(RegExp(r'[\u0000-\u0008]'))) throw const ImportProblem('This does not look like a CSV (text) file.');
  final bytes = utf8.encode(text);
  if (text.length > maxCsvChars || bytes.length > maxPickedBytes) {
    final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
    throw ImportProblem('This statement is $mb MB and Paisa can import up to 3 MB of CSV at once. Download a shorter period from your bank, such as one month, and import each part.');
  }
  return PreparedStatement(fileName: 'statement.csv', contentType: csvMime, sizeBytes: bytes.length, sha256: sha256.convert(bytes).toString(), content: text);
}

String _entries(int n) => n == 1 ? '1 entry' : '$n entries';

/// "17 entries imported, 3 already in the ledger" in the web's words.
String importHeadline(ImportResult result) {
  if (result.imported == 0 && result.duplicates > 0) {
    return result.duplicates == 1 ? 'Nothing new: that entry was already in the ledger.' : 'Nothing new: all ${result.duplicates} entries were already in the ledger.';
  }
  if (result.imported == 0) return 'No entries were imported.';
  final done = '${_entries(result.imported)} imported';
  return result.duplicates == 0 ? done : '$done, ${result.duplicates} already in the ledger';
}

String fileSize(int bytes) => bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
