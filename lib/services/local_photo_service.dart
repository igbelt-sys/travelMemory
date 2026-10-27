import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';

import '../models/travel_entry.dart';
import 'photo_service.dart';
import 'local_photo_platform_stub.dart'
    if (dart.library.io) 'local_photo_platform_io.dart'
    as disk;

class LocalPhotoException implements Exception {
  const LocalPhotoException(this.message);
  final String message;
}

/// Paths relativos ao diretório permanente do app; nunca usa o cache da galeria.
class LocalPhotoService {
  LocalPhotoService({FirebaseAuth? auth, Future<String> Function()? rootPath})
    : _providedAuth = auth,
      _root = rootPath ?? disk.rootPath;
  final FirebaseAuth? _providedAuth;
  final Future<String> Function() _root;
  static bool get supported => disk.supported;

  void _check(String uid, String entryId, String relativePath) {
    final current = (_providedAuth ?? FirebaseAuth.instance).currentUser?.uid;
    if (current == null) throw FirebaseAuthException(code: 'unauthenticated');
    if (current != uid) throw FirebaseAuthException(code: 'permission-denied');
    final segment = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');
    final parts = relativePath.split('/');
    if (!segment.hasMatch(uid) ||
        !segment.hasMatch(entryId) ||
        parts.length != 5 ||
        parts[0] != 'users' ||
        parts[1] != uid ||
        parts[2] != 'travel_entries' ||
        parts[3] != entryId ||
        !TravelEntry.isSupportedFileName(parts[4])) {
      throw const FormatException(
        'O caminho local da foto não pertence a este registro e usuário.',
      );
    }
  }

  Future<void> write({
    required String uid,
    required String entryId,
    required String relativePath,
    required TravelPhoto photo,
  }) async {
    _check(uid, entryId, relativePath);
    if (!supported) {
      throw const LocalPhotoException(
        'Fotos locais estão disponíveis no aplicativo instalado no dispositivo.',
      );
    }
    await photo.validateDecoded();
    final extension = relativePath.split('.').last;
    if (extension != photo.extension &&
        !(photo.extension == 'jpg' && extension == 'jpeg')) {
      throw const FormatException(
        'A extensão deve corresponder ao formato real da foto.',
      );
    }
    final root = await _root();
    _check(uid, entryId, relativePath);
    try {
      await disk.write(root, relativePath, photo.bytes);
    } catch (_) {
      throw const LocalPhotoException(
        'Não foi possível guardar a foto neste dispositivo. Confira o espaço livre e tente novamente.',
      );
    }
    _check(uid, entryId, relativePath);
  }

  Future<Uint8List?> read({
    required String uid,
    required String entryId,
    required String relativePath,
  }) async {
    _check(uid, entryId, relativePath);
    if (!supported) return null;
    final root = await _root();
    _check(uid, entryId, relativePath);
    Uint8List? bytes;
    try {
      bytes = await disk.read(root, relativePath);
    } catch (_) {
      throw const LocalPhotoException(
        'Não foi possível abrir a foto neste dispositivo.',
      );
    }
    _check(uid, entryId, relativePath);
    return bytes;
  }

  Future<void> remove({
    required String uid,
    required String entryId,
    required String relativePath,
  }) async {
    _check(uid, entryId, relativePath);
    if (!supported) return;
    final root = await _root();
    _check(uid, entryId, relativePath);
    await disk.remove(root, relativePath);
  }
}
