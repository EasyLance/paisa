// Opens a password-protected Excel workbook on the phone, so the password never
// leaves it. An encrypted .xlsx is not a ZIP: it is an old-style "compound file"
// holding two streams, `EncryptionInfo` (how) and `EncryptedPackage` (the ZIP,
// encrypted). Agile encryption, ECMA-376 / MS-OFFCRYPTO §2.3.4, which is what
// current Excel writes. The data-integrity HMAC is not checked: the password
// check below already proves the key, and the server parses what comes out.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class WrongPasswordException implements Exception {
  const WrongPasswordException();
  @override
  String toString() => 'WrongPasswordException';
}

/// The file is encrypted in a way Paisa cannot open, or is not an encrypted workbook.
class UnsupportedEncryptionException implements Exception {
  const UnsupportedEncryptionException(this.message);
  final String message;
  @override
  String toString() => 'UnsupportedEncryptionException($message)';
}

const _signature = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];

/// An Office-encrypted file starts with the compound-file signature; a plain
/// .xlsx starts with `PK`.
bool isOfficeEncrypted(Uint8List bytes) {
  if (bytes.length < 8) return false;
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _signature[i]) return false;
  }
  return true;
}

// ---- compound file ---------------------------------------------------------

const _endOfChain = 0xfffffffe;
const _freeSector = 0xffffffff;

/// Just enough of the compound-file format to read named streams.
class CompoundFile {
  CompoundFile._(this._b, this._sectorSize, this._miniSectorSize, this._miniCutoff, this._fat, this._miniFat, this._entries, this._miniStream);

  final Uint8List _b;
  final int _sectorSize;
  final int _miniSectorSize;
  final int _miniCutoff;
  final List<int> _fat;
  final List<int> _miniFat;
  final List<_Entry> _entries;
  final Uint8List _miniStream;

  static int _u32(Uint8List b, int at) {
    if (at < 0 || at + 4 > b.length) throw const FormatException('Truncated compound file');
    return b[at] | b[at + 1] << 8 | b[at + 2] << 16 | b[at + 3] << 24;
  }

  static int _u16(Uint8List b, int at) {
    if (at < 0 || at + 2 > b.length) throw const FormatException('Truncated compound file');
    return b[at] | b[at + 1] << 8;
  }

  static CompoundFile parse(Uint8List b) {
    if (!isOfficeEncrypted(b) || b.length < 512) throw const FormatException('Not a compound file');
    final sectorSize = 1 << _u16(b, 0x1e);
    final miniSectorSize = 1 << _u16(b, 0x20);
    if (sectorSize != 512 && sectorSize != 4096) throw const FormatException('Odd sector size');
    final firstDir = _u32(b, 0x30);
    final miniCutoff = _u32(b, 0x38);
    final firstMiniFat = _u32(b, 0x3c);
    final firstDifat = _u32(b, 0x44);
    final difatCount = _u32(b, 0x48);

    int offset(int sector) => (sector + 1) * sectorSize;
    Uint8List sectorBytes(int sector) {
      final start = offset(sector);
      if (sector < 0 || start + sectorSize > b.length + sectorSize) throw const FormatException('Sector out of range');
      return Uint8List.sublistView(b, start, (start + sectorSize).clamp(0, b.length));
    }

    // Where the FAT sectors are: 109 in the header, then a chain of DIFAT sectors.
    final fatSectors = <int>[];
    for (var i = 0; i < 109; i++) {
      final id = _u32(b, 0x4c + i * 4);
      if (id != _freeSector) fatSectors.add(id);
    }
    var difat = firstDifat;
    for (var n = 0; n < difatCount && difat != _endOfChain && difat != _freeSector; n++) {
      final s = sectorBytes(difat);
      for (var i = 0; i < sectorSize ~/ 4 - 1; i++) {
        final id = _u32(s, i * 4);
        if (id != _freeSector) fatSectors.add(id);
      }
      difat = _u32(s, sectorSize - 4);
    }
    final fat = <int>[];
    for (final sector in fatSectors) {
      final s = sectorBytes(sector);
      for (var i = 0; i < sectorSize ~/ 4; i++) {
        fat.add(_u32(s, i * 4));
      }
    }

    Uint8List readChain(int start, List<int> table, int size) {
      final out = BytesBuilder(copy: false);
      var sector = start;
      var hops = 0;
      final limit = b.length ~/ 64 + 2;
      while (sector != _endOfChain && sector != _freeSector && out.length < size) {
        if (sector >= table.length || hops++ > limit) throw const FormatException('Broken sector chain');
        out.add(sectorBytes(sector));
        sector = table[sector];
      }
      final all = out.takeBytes();
      return Uint8List.sublistView(all, 0, size < all.length ? size : all.length);
    }

    // The directory is a chain of 128-byte entries.
    final dirBytes = readChain(firstDir, fat, b.length);
    final entries = <_Entry>[];
    for (var at = 0; at + 128 <= dirBytes.length; at += 128) {
      final type = dirBytes[at + 66];
      if (type == 0) continue;
      final nameLength = _u16(dirBytes, at + 64);
      final units = <int>[for (var i = 0; i + 1 < nameLength - 2 && i < 62; i += 2) _u16(dirBytes, at + i)];
      entries.add(_Entry(String.fromCharCodes(units), type, _u32(dirBytes, at + 116), _u32(dirBytes, at + 120)));
    }
    final root = entries.where((e) => e.type == 5).firstOrNull;
    final miniFat = <int>[];
    var miniStream = Uint8List(0);
    if (root != null && firstMiniFat != _endOfChain) {
      final raw = readChain(firstMiniFat, fat, b.length);
      for (var i = 0; i + 4 <= raw.length; i += 4) {
        miniFat.add(_u32(raw, i));
      }
      miniStream = readChain(root.start, fat, root.size);
    }
    return CompoundFile._(b, sectorSize, miniSectorSize, miniCutoff, fat, miniFat, entries, miniStream);
  }

  /// A stream's bytes, or null if there is no stream by that name.
  Uint8List? stream(String name) {
    final entry = _entries.where((e) => e.type == 2 && e.name == name).firstOrNull;
    if (entry == null) return null;
    final out = BytesBuilder(copy: false);
    var sector = entry.start;
    var hops = 0;
    final small = entry.size < _miniCutoff;
    final unit = small ? _miniSectorSize : _sectorSize;
    final table = small ? _miniFat : _fat;
    while (sector != _endOfChain && sector != _freeSector && out.length < entry.size) {
      if (sector >= table.length || hops++ > _b.length) throw const FormatException('Broken stream chain');
      if (small) {
        final at = sector * unit;
        if (at + unit > _miniStream.length) throw const FormatException('Mini sector out of range');
        out.add(Uint8List.sublistView(_miniStream, at, at + unit));
      } else {
        final at = (sector + 1) * unit;
        if (at >= _b.length) throw const FormatException('Sector out of range');
        out.add(Uint8List.sublistView(_b, at, (at + unit).clamp(0, _b.length)));
      }
      sector = table[sector];
    }
    final all = out.takeBytes();
    return Uint8List.sublistView(all, 0, entry.size < all.length ? entry.size : all.length);
  }
}

class _Entry {
  const _Entry(this.name, this.type, this.start, this.size);
  final String name;
  final int type;
  final int start;
  final int size;
}

// ---- agile decryption ------------------------------------------------------

Hash _hashNamed(String name) => switch (name.toUpperCase()) {
  'SHA1' => sha1,
  'SHA256' => sha256,
  'SHA384' => sha384,
  'SHA512' => sha512,
  _ => throw UnsupportedEncryptionException('This file uses the hash $name, which Paisa cannot read'),
};

Map<String, String> _attributes(String xml, String tag) {
  final match = RegExp('<(?:\\w+:)?$tag\\b([^>]*)>').firstMatch(xml);
  if (match == null) throw UnsupportedEncryptionException('The encryption details are missing the $tag section');
  return {for (final m in RegExp(r'([\w:]+)="([^"]*)"').allMatches(match.group(1)!)) m.group(1)!: m.group(2)!};
}

Uint8List _concat(List<List<int>> parts) => Uint8List.fromList([for (final part in parts) ...part]);

Uint8List _u32le(int value) => Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);

Uint8List _aesCbcDecrypt(Uint8List data, Uint8List key, Uint8List iv) {
  final cipher = CBCBlockCipher(AESEngine())..init(false, ParametersWithIV(KeyParameter(key), iv));
  final whole = data.length - data.length % 16;
  final out = Uint8List(whole);
  for (var at = 0; at < whole; at += 16) {
    cipher.processBlock(data, at, out, at);
  }
  return out;
}

// The spec's block keys: which value a derived key is for.
const _verifierInputBlock = [0xfe, 0xa7, 0xd2, 0x76, 0x3b, 0x4b, 0x9e, 0x79];
const _verifierValueBlock = [0xd7, 0xaa, 0x0f, 0x6d, 0x30, 0x61, 0x34, 0x4e];
const _keyValueBlock = [0x14, 0x6e, 0x0b, 0xe7, 0xab, 0xac, 0xd0, 0xd6];

/// The workbook inside an encrypted .xlsx, as ordinary .xlsx bytes. Throws
/// [WrongPasswordException] for a wrong password and
/// [UnsupportedEncryptionException] for anything it cannot read.
///
/// Slow on purpose: the password is stretched with 100,000 hashes, so run it off
/// the main isolate.
Uint8List decryptOfficeXlsx(Uint8List file, String password) {
  try {
    return _decrypt(file, password);
  } on FormatException {
    throw const UnsupportedEncryptionException('This file looks damaged or is not an Excel file Paisa can open');
  } on RangeError {
    throw const UnsupportedEncryptionException('This file looks damaged or is not an Excel file Paisa can open');
  }
}

Uint8List _decrypt(Uint8List file, String password) {
  final container = CompoundFile.parse(file);
  final info = container.stream('EncryptionInfo');
  final package = container.stream('EncryptedPackage');
  if (info == null || package == null || info.length < 8) {
    throw const UnsupportedEncryptionException('This does not look like a password-protected Excel file');
  }
  final major = info[0] | info[1] << 8;
  final minor = info[2] | info[3] << 8;
  if (major != 4 || minor != 4) {
    throw const UnsupportedEncryptionException('This file uses an older kind of Excel password protection. Open it in Excel and save it again as a new .xlsx, then try again');
  }
  final xml = utf8.decode(info.sublist(8), allowMalformed: true);
  final data = _attributes(xml, 'keyData');
  final key = _attributes(xml, 'encryptedKey');
  for (final section in [data, key]) {
    if (section['cipherAlgorithm'] != 'AES' || section['cipherChaining'] != 'ChainingModeCBC') {
      throw const UnsupportedEncryptionException('This file uses a kind of encryption Paisa cannot read');
    }
  }

  try {
    final hash = _hashNamed(key['hashAlgorithm'] ?? '');
    final keyBytes = int.parse(key['keyBits']!) ~/ 8;
    final salt = base64.decode(key['saltValue']!);
    final spin = int.parse(key['spinCount']!);
    final hashSize = int.parse(key['hashSize']!);

    var h = Uint8List.fromList(hash.convert(_concat([salt, _utf16le(password)])).bytes);
    for (var i = 0; i < spin; i++) {
      h = Uint8List.fromList(hash.convert(_concat([_u32le(i), h])).bytes);
    }
    Uint8List derive(List<int> block) {
      final d = hash.convert(_concat([h, block])).bytes;
      // Cut to the key length, or pad with 0x36 if the hash is shorter than the key.
      return Uint8List.fromList(d.length >= keyBytes ? d.sublist(0, keyBytes) : [...d, ...List.filled(keyBytes - d.length, 0x36)]);
    }

    final saltBytes = Uint8List.fromList(salt);
    final verifierInput = _aesCbcDecrypt(Uint8List.fromList(base64.decode(key['encryptedVerifierHashInput']!)), derive(_verifierInputBlock), saltBytes);
    final verifierValue = _aesCbcDecrypt(Uint8List.fromList(base64.decode(key['encryptedVerifierHashValue']!)), derive(_verifierValueBlock), saltBytes);
    final expected = hash.convert(verifierInput.sublist(0, int.parse(key['saltSize']!))).bytes;
    for (var i = 0; i < hashSize; i++) {
      if (expected[i] != verifierValue[i]) throw const WrongPasswordException();
    }
    final secret = _aesCbcDecrypt(Uint8List.fromList(base64.decode(key['encryptedKeyValue']!)), derive(_keyValueBlock), saltBytes).sublist(0, keyBytes);

    // The package: an 8-byte length, then 4096-byte segments, each with its own IV.
    final dataHash = _hashNamed(data['hashAlgorithm'] ?? '');
    final dataSalt = base64.decode(data['saltValue']!);
    final blockSize = int.parse(data['blockSize']!);
    final length = ByteData.sublistView(package).getUint32(0, Endian.little);
    final body = Uint8List.sublistView(package, 8);
    final out = BytesBuilder(copy: false);
    for (var segment = 0, at = 0; at < body.length; segment++, at += 4096) {
      final end = at + 4096 < body.length ? at + 4096 : body.length;
      final iv = Uint8List.fromList(dataHash.convert(_concat([dataSalt, _u32le(segment)])).bytes.sublist(0, blockSize));
      out.add(_aesCbcDecrypt(Uint8List.sublistView(body, at, end), secret, iv));
    }
    final all = out.takeBytes();
    final result = Uint8List.sublistView(all, 0, length < all.length ? length : all.length);
    if (result.length < 4 || result[0] != 0x50 || result[1] != 0x4b) throw const WrongPasswordException();
    return Uint8List.fromList(result);
  } on FormatException {
    throw const UnsupportedEncryptionException('The encryption details in this file could not be read');
  }
}

Uint8List _utf16le(String text) {
  final units = text.codeUnits;
  final out = Uint8List(units.length * 2);
  for (var i = 0; i < units.length; i++) {
    out[i * 2] = units[i] & 0xff;
    out[i * 2 + 1] = units[i] >> 8;
  }
  return out;
}
