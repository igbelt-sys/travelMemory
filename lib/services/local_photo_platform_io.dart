import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const supported = true;
Future<String> rootPath() async =>
    (await getApplicationDocumentsDirectory()).path;
File _file(String root, String relativePath) =>
    File(p.joinAll([root, ...relativePath.split('/')]));

Future<void> write(String root, String relativePath, Uint8List bytes) async {
  final file = _file(root, relativePath);
  await file.parent.create(recursive: true);
  if (await file.exists()) {
    final previous = await file.readAsBytes();
    if (previous.length == bytes.length) {
      var equal = true;
      for (var i = 0; i < bytes.length; i++) {
        if (previous[i] != bytes[i]) {
          equal = false;
          break;
        }
      }
      if (equal) return;
    }
    throw const FileSystemException('Já existe outra foto neste registro.');
  }
  final staging = File('${file.path}.pending');
  try {
    await staging.writeAsBytes(bytes, flush: true);
    await staging.rename(file.path);
  } finally {
    if (await staging.exists()) await staging.delete();
  }
}

Future<Uint8List?> read(String root, String relativePath) async {
  final file = _file(root, relativePath);
  if (!await file.exists()) return null;
  // Não carregar um arquivo corrompido/crescido além do limite da galeria.
  if (await file.length() > 10 * 1024 * 1024) {
    throw const FileSystemException('Foto inválida.');
  }
  return file.readAsBytes();
}

Future<void> remove(String root, String relativePath) async {
  final file = _file(root, relativePath);
  if (await file.exists()) await file.delete();
}
