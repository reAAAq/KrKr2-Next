import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// XP3 archive magic header (11 bytes).
const List<int> _xp3Magic = [
  0x58, 0x50, 0x33, // "XP3"
  0x0d, 0x0a, // CR LF
  0x20, // space
  0x0a, // LF
  0x1a, // EOF
  0x8b, 0x67, // KANJI-CODE
  0x01, // version/encoding
];

const int _indexEncodeRaw = 0;
const int _indexEncodeZlib = 1;
const int _indexEncodeMask = 0x07;
const int _indexContinue = 0x80;

const int _segmEncodeZlib = 1;
const int _segmEncodeMask = 0x07;

// ---------------------------------------------------------------------------
// Data types for parsed XP3 entries
// ---------------------------------------------------------------------------

class _Xp3Segment {
  final int flags;
  final int start; // absolute position in archive
  final int orgSize; // uncompressed size
  final int arcSize; // compressed size in archive

  _Xp3Segment({
    required this.flags,
    required this.start,
    required this.orgSize,
    required this.arcSize,
  });

  bool get isCompressed =>
      (flags & _segmEncodeMask) == _segmEncodeZlib;
}

class _Xp3Entry {
  final String name;
  final int orgSize;
  final int arcSize;
  final int fileHash;
  final List<_Xp3Segment> segments;

  _Xp3Entry({
    required this.name,
    required this.orgSize,
    required this.arcSize,
    required this.fileHash,
    required this.segments,
  });
}

// ---------------------------------------------------------------------------
// Low-level helpers
// ---------------------------------------------------------------------------

int _readU16LE(Uint8List data, int offset) =>
    data[offset] | (data[offset + 1] << 8);

int _readU32LE(Uint8List data, int offset) =>
    data[offset] |
    (data[offset + 1] << 8) |
    (data[offset + 2] << 16) |
    (data[offset + 3] << 24);

int _readU64LE(Uint8List data, int offset) {
  // Dart int is 64-bit on VM; on web this would overflow, but Flutter
  // mobile/desktop always runs on the VM.
  int lo = _readU32LE(data, offset) & 0xFFFFFFFF;
  int hi = _readU32LE(data, offset + 4) & 0xFFFFFFFF;
  return (hi << 32) | lo;
}

Uint8List _writeU16LE(int v) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);

Uint8List _writeU32LE(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

Uint8List _writeU64LE(int v) =>
    Uint8List(8)..buffer.asByteData().setInt64(0, v, Endian.little);

/// Find a named chunk inside [data] starting at [start] within [size] bytes.
/// Returns `(chunkDataStart, chunkDataSize)` or `null` if not found.
(int, int)? _findChunk(
    Uint8List data, List<int> name, int start, int size) {
  int pos = 0;
  int cur = start;
  while (pos < size) {
    bool match = true;
    for (int i = 0; i < 4; i++) {
      if (data[cur + i] != name[i]) {
        match = false;
        break;
      }
    }
    cur += 4;
    final chunkSize = _readU64LE(data, cur);
    cur += 8;
    if (match) {
      return (cur, chunkSize);
    }
    cur += chunkSize;
    pos += chunkSize + 12;
  }
  return null;
}

// Chunk name constants
const _cnFile = [0x46, 0x69, 0x6c, 0x65]; // "File"
const _cnInfo = [0x69, 0x6e, 0x66, 0x6f]; // "info"
const _cnSegm = [0x73, 0x65, 0x67, 0x6d]; // "segm"
const _cnAdlr = [0x61, 0x64, 0x6c, 0x72]; // "adlr"

// ---------------------------------------------------------------------------
// XP3 Extract
// ---------------------------------------------------------------------------

/// Extract an XP3 archive at [xp3Path] into [destDir].
///
/// [onProgress] is called with a value between 0.0 and 1.0.
Future<void> xp3Extract(
  String xp3Path,
  String destDir, {
  void Function(double progress, String currentFile)? onProgress,
}) async {
  final file = File(xp3Path);
  final raf = await file.open(mode: FileMode.read);
  try {
    // 1. Read & verify magic
    final magic = await raf.read(11);
    for (int i = 0; i < 11; i++) {
      if (magic[i] != _xp3Magic[i]) {
        throw FormatException('Not a valid XP3 archive');
      }
    }

    // 2. Read index offset
    final idxOfsBytes = await raf.read(8);
    final indexOffset = _readU64LE(idxOfsBytes, 0);

    // 3. Parse index
    final entries = <_Xp3Entry>[];
    await raf.setPosition(indexOffset);

    while (true) {
      final flagBytes = await raf.read(1);
      final indexFlag = flagBytes[0];

      Uint8List indexData;
      if ((indexFlag & _indexEncodeMask) == _indexEncodeZlib) {
        final compSizeBytes = await raf.read(8);
        final orgSizeBytes = await raf.read(8);
        final compSize = _readU64LE(compSizeBytes, 0);
        final orgSize = _readU64LE(orgSizeBytes, 0);
        final compressed = await raf.read(compSize);
        indexData = Uint8List.fromList(zlib.decode(compressed));
        if (indexData.length != orgSize) {
          throw FormatException('Index decompression size mismatch');
        }
      } else if ((indexFlag & _indexEncodeMask) == _indexEncodeRaw) {
        final sizBytes = await raf.read(8);
        final size = _readU64LE(sizBytes, 0);
        indexData = await raf.read(size);
      } else {
        throw FormatException('Unknown index encoding');
      }

      // Parse File chunks from indexData
      int fileStart = 0;
      int fileSize = indexData.length;
      while (true) {
        final fileChunk = _findChunk(indexData, _cnFile, fileStart, fileSize);
        if (fileChunk == null) break;
        final (fcStart, fcSize) = fileChunk;

        // info
        final infoChunk =
            _findChunk(indexData, _cnInfo, fcStart, fcSize);
        if (infoChunk == null) {
          throw FormatException('Missing info chunk');
        }
        final (infoStart, _) = infoChunk;
        final orgSize = _readU64LE(indexData, infoStart + 4);
        final arcSize = _readU64LE(indexData, infoStart + 12);
        final nameLen = _readU16LE(indexData, infoStart + 20);
        final nameBytes =
            indexData.sublist(infoStart + 22, infoStart + 22 + nameLen * 2);
        final name = _utf16LEToString(nameBytes);

        // segm
        final segmChunk =
            _findChunk(indexData, _cnSegm, fcStart, fcSize);
        if (segmChunk == null) {
          throw FormatException('Missing segm chunk');
        }
        final (segmStart, segmSize) = segmChunk;
        final segCount = segmSize ~/ 28;
        final segments = <_Xp3Segment>[];
        for (int i = 0; i < segCount; i++) {
          final base = segmStart + i * 28;
          segments.add(_Xp3Segment(
            flags: _readU32LE(indexData, base),
            start: _readU64LE(indexData, base + 4),
            orgSize: _readU64LE(indexData, base + 12),
            arcSize: _readU64LE(indexData, base + 20),
          ));
        }

        // adlr
        final adlrChunk =
            _findChunk(indexData, _cnAdlr, fcStart, fcSize);
        final fileHash =
            adlrChunk != null ? _readU32LE(indexData, adlrChunk.$1) : 0;

        entries.add(_Xp3Entry(
          name: name,
          orgSize: orgSize,
          arcSize: arcSize,
          fileHash: fileHash,
          segments: segments,
        ));

        // Advance past this File chunk
        fileStart = fcStart + fcSize;
        fileSize = indexData.length - fileStart;
      }

      if ((indexFlag & _indexContinue) == 0) break;
    }

    // 4. Extract files
    for (int idx = 0; idx < entries.length; idx++) {
      final entry = entries[idx];
      final relativePath = entry.name.replaceAll('\\', '/');
      onProgress?.call(idx / entries.length, relativePath);

      final outPath = p.join(destDir, relativePath);
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);

      final sink = outFile.openWrite();
      try {
        for (final seg in entry.segments) {
          await raf.setPosition(seg.start);
          final rawData = await raf.read(seg.arcSize);
          if (seg.isCompressed) {
            sink.add(zlib.decode(rawData));
          } else {
            sink.add(rawData);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
    }

    onProgress?.call(1.0, '');
  } finally {
    await raf.close();
  }
}

// ---------------------------------------------------------------------------
// XP3 Pack
// ---------------------------------------------------------------------------

/// Simple Adler-like hash matching the KRKR2 engine's file hash.
int _calcFileHash(Uint8List data) {
  int hash = 0;
  for (int i = 0; i < data.length; i++) {
    hash = (hash + data[i]) & 0xFFFFFFFF;
  }
  return hash;
}

/// Pack a directory at [sourceDir] into an XP3 archive at [xp3Path].
///
/// Files are stored uncompressed (RAW).
/// [onProgress] is called with a value between 0.0 and 1.0.
Future<void> xp3Pack(
  String sourceDir,
  String xp3Path, {
  void Function(double progress, String currentFile)? onProgress,
}) async {
  final srcDir = Directory(sourceDir);
  final allFiles = <File>[];
  await for (final entity in srcDir.list(recursive: true)) {
    if (entity is File) {
      allFiles.add(entity);
    }
  }
  allFiles.sort((a, b) => a.path.compareTo(b.path));

  final outFile = File(xp3Path);
  final raf = await outFile.open(mode: FileMode.write);
  try {
    // 1. Write XP3 header (11 bytes)
    await raf.writeFrom(Uint8List.fromList(_xp3Magic));

    // 2. Write placeholder for index offset (8 bytes)
    final indexOffsetPos = await raf.position();
    await raf.writeFrom(_writeU64LE(0));

    // 3. Write file data and collect index info
    final indexEntries = <_PackEntry>[];

    for (int i = 0; i < allFiles.length; i++) {
      final file = allFiles[i];
      final relativePath =
          unorm.nfc(p.relative(file.path, from: sourceDir)).replaceAll('/', '\\');
      onProgress?.call(i / allFiles.length, relativePath);

      final fileData = await file.readAsBytes();
      final dataOffset = await raf.position();
      await raf.writeFrom(fileData);

      indexEntries.add(_PackEntry(
        name: relativePath,
        orgSize: fileData.length,
        arcSize: fileData.length,
        dataOffset: dataOffset,
        fileHash: _calcFileHash(fileData),
      ));
    }

    // 4. Build and write index
    final indexPosition = await raf.position();

    // Build index data buffer
    final indexBuf = BytesBuilder(copy: false);
    for (final entry in indexEntries) {
      // Build sub-chunks first to know File chunk size
      final infoBuf = BytesBuilder(copy: false);
      infoBuf.add(_writeU32LE(0)); // flags
      infoBuf.add(_writeU64LE(entry.orgSize)); // OrgSize
      infoBuf.add(_writeU64LE(entry.arcSize)); // ArcSize
      final nameUtf16 = _stringToUtf16LE(entry.name);
      infoBuf.add(_writeU16LE(nameUtf16.length ~/ 2)); // name length in code units
      infoBuf.add(nameUtf16);
      final infoData = infoBuf.toBytes();

      final segmBuf = BytesBuilder(copy: false);
      segmBuf.add(_writeU32LE(0)); // flags = RAW
      segmBuf.add(_writeU64LE(entry.dataOffset)); // Start
      segmBuf.add(_writeU64LE(entry.orgSize)); // OrgSize
      segmBuf.add(_writeU64LE(entry.arcSize)); // ArcSize
      final segmData = segmBuf.toBytes();

      final adlrData = _writeU32LE(entry.fileHash);

      // File chunk = info chunk + segm chunk + adlr chunk
      final fileBuf = BytesBuilder(copy: false);
      // info sub-chunk header
      fileBuf.add(Uint8List.fromList(_cnInfo));
      fileBuf.add(_writeU64LE(infoData.length));
      fileBuf.add(infoData);
      // segm sub-chunk header
      fileBuf.add(Uint8List.fromList(_cnSegm));
      fileBuf.add(_writeU64LE(segmData.length));
      fileBuf.add(segmData);
      // adlr sub-chunk header
      fileBuf.add(Uint8List.fromList(_cnAdlr));
      fileBuf.add(_writeU64LE(adlrData.length));
      fileBuf.add(adlrData);

      final fileData = fileBuf.toBytes();

      // File chunk header
      indexBuf.add(Uint8List.fromList(_cnFile));
      indexBuf.add(_writeU64LE(fileData.length));
      indexBuf.add(fileData);
    }

    final indexData = indexBuf.toBytes();

    // Write index: flag (1 byte) + size (8 bytes) + data
    await raf.writeFrom(Uint8List.fromList([_indexEncodeRaw])); // raw
    await raf.writeFrom(_writeU64LE(indexData.length));
    await raf.writeFrom(indexData);

    // 5. Go back and write the real index offset
    await raf.setPosition(indexOffsetPos);
    await raf.writeFrom(_writeU64LE(indexPosition));

    onProgress?.call(1.0, '');
  } finally {
    await raf.close();
  }
}

class _PackEntry {
  final String name;
  final int orgSize;
  final int arcSize;
  final int dataOffset;
  final int fileHash;

  _PackEntry({
    required this.name,
    required this.orgSize,
    required this.arcSize,
    required this.dataOffset,
    required this.fileHash,
  });
}

// ---------------------------------------------------------------------------
// XP3 List
// ---------------------------------------------------------------------------

/// Information about a file inside an XP3 archive.
class Xp3FileInfo {
  final String name;
  final int size;

  Xp3FileInfo({required this.name, required this.size});

  @override
  String toString() => '$name ($size bytes)';
}

/// List all files in an XP3 archive.
Future<List<Xp3FileInfo>> xp3List(String xp3Path) async {
  final file = File(xp3Path);
  final raf = await file.open(mode: FileMode.read);
  try {
    final magic = await raf.read(11);
    for (int i = 0; i < 11; i++) {
      if (magic[i] != _xp3Magic[i]) {
        throw FormatException('Not a valid XP3 archive');
      }
    }

    final idxOfsBytes = await raf.read(8);
    final indexOffset = _readU64LE(idxOfsBytes, 0);
    await raf.setPosition(indexOffset);

    final result = <Xp3FileInfo>[];

    while (true) {
      final flagBytes = await raf.read(1);
      final indexFlag = flagBytes[0];

      Uint8List indexData;
      if ((indexFlag & _indexEncodeMask) == _indexEncodeZlib) {
        final compSizeBytes = await raf.read(8);
        final orgSizeBytes = await raf.read(8);
        final compSize = _readU64LE(compSizeBytes, 0);
        final orgSize = _readU64LE(orgSizeBytes, 0);
        final compressed = await raf.read(compSize);
        indexData = Uint8List.fromList(zlib.decode(compressed));
        if (indexData.length != orgSize) {
          throw FormatException('Index decompression size mismatch');
        }
      } else if ((indexFlag & _indexEncodeMask) == _indexEncodeRaw) {
        final sizBytes = await raf.read(8);
        final size = _readU64LE(sizBytes, 0);
        indexData = await raf.read(size);
      } else {
        throw FormatException('Unknown index encoding');
      }

      int fileStart = 0;
      int fileSize = indexData.length;
      while (true) {
        final fileChunk = _findChunk(indexData, _cnFile, fileStart, fileSize);
        if (fileChunk == null) break;
        final (fcStart, fcSize) = fileChunk;

        final infoChunk =
            _findChunk(indexData, _cnInfo, fcStart, fcSize);
        if (infoChunk == null) break;
        final (infoStart, _) = infoChunk;
        final orgSize = _readU64LE(indexData, infoStart + 4);
        final nameLen = _readU16LE(indexData, infoStart + 20);
        final nameBytes =
            indexData.sublist(infoStart + 22, infoStart + 22 + nameLen * 2);
        final name = _utf16LEToString(nameBytes);

        result.add(Xp3FileInfo(name: name, size: orgSize));

        fileStart = fcStart + fcSize;
        fileSize = indexData.length - fileStart;
      }

      if ((indexFlag & _indexContinue) == 0) break;
    }

    return result;
  } finally {
    await raf.close();
  }
}

// ---------------------------------------------------------------------------
// UTF-16 LE helpers
// ---------------------------------------------------------------------------

String _utf16LEToString(Uint8List bytes) {
  final codeUnits = <int>[];
  for (int i = 0; i < bytes.length; i += 2) {
    codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(codeUnits);
}

Uint8List _stringToUtf16LE(String s) {
  final buf = BytesBuilder(copy: false);
  for (int i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    buf.addByte(code & 0xFF);
    buf.addByte((code >> 8) & 0xFF);
  }
  return buf.toBytes();
}
