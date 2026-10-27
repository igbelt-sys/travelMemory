import 'dart:typed_data';

const supported = false;
Future<String> rootPath() =>
    throw UnsupportedError('Fotos locais indisponíveis nesta plataforma.');
Future<void> write(String root, String relativePath, Uint8List bytes) =>
    throw UnsupportedError('Fotos locais indisponíveis nesta plataforma.');
Future<Uint8List?> read(String root, String relativePath) async => null;
Future<void> remove(String root, String relativePath) async {}
