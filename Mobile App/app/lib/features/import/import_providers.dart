import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'import_logic.dart';
import 'office_crypto.dart';

typedef PickedFile = ({String name, Uint8List bytes});

/// Asks the phone for a file. A provider so a test can answer without a dialog.
final statementPickerProvider = Provider<Future<PickedFile?> Function()>((ref) => _pickFromPhone);

// ponytail: xls, csv and pdf are offered in the picker only so they can be
// refused with a reason (refusalForName). Drop them from this list if the picker
// ever greys them out too confusingly.
Future<PickedFile?> _pickFromPhone() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx', 'xls', 'csv', 'pdf']);
  if (file == null) return null;
  const tooBig = ImportProblem('That file is over 10 MB, which is more than a statement should be.');
  // Refuse on the size the picker reported before reading anything into memory.
  if ((file.lengthSync() ?? 0) > maxPickedBytes) throw tooBig;
  final bytes = await file.readAsBytes();
  if (bytes.length > maxPickedBytes) throw tooBig;
  return (name: file.name, bytes: bytes);
}

typedef Decryptor = Future<Uint8List> Function(Uint8List file, String password);

/// Opening a protected workbook stretches the password with 100,000 hashes, which
/// would freeze the screen for a moment, so it runs off the main isolate.
final decryptorProvider = Provider<Decryptor>((ref) => (file, password) => Isolate.run(() => decryptOfficeXlsx(file, password)));
