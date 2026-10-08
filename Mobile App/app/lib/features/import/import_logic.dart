// Pure rules for importing a statement, so they can be tested without a widget.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/api/models.dart';

const xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

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

/// Why a chosen file cannot be imported, judged by its name, or null if it can.
/// Other kinds are named rather than greyed out, so nobody wonders why a file
/// they can see will not work.
String? refusalForName(String name) {
  final dot = name.lastIndexOf('.');
  final extension = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'xlsx' => null,
    'xls' => 'Paisa reads .xlsx files, not the older .xls. Open it in Excel and save it as .xlsx.',
    'pdf' => 'PDF statements cannot be imported yet. Download the statement from your bank as an Excel (.xlsx) file.',
    'csv' => 'CSV statements cannot be imported from the phone yet. Download the statement from your bank as an Excel (.xlsx) file.',
    _ => 'Choose an Excel (.xlsx) statement.',
  };
}

/// What goes to the server. The file's own name is never sent: a bank often puts
/// the account number in it, and the server has no use for it.
class PreparedStatement {
  const PreparedStatement({required this.sizeBytes, required this.sha256, required this.content});

  final int sizeBytes;
  final String sha256;
  final String content;

  Map<String, Object?> body({String? accountId}) => {
    'fileName': 'statement.xlsx',
    'contentType': xlsxMime,
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
  return PreparedStatement(sizeBytes: workbook.length, sha256: sha256.convert(workbook).toString(), content: base64.encode(workbook));
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
