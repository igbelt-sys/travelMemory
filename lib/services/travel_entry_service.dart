import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/travel_entry.dart';
import 'local_photo_service.dart';
import 'photo_service.dart';

class TravelEntryService {
  TravelEntryService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    LocalPhotoService? localPhotos,
  }) : _providedFirestore = firestore,
       _providedAuth = auth,
       _providedStorage = storage,
       _providedLocalPhotos = localPhotos;

  final FirebaseFirestore? _providedFirestore;
  final FirebaseAuth? _providedAuth;
  final FirebaseStorage? _providedStorage;
  final LocalPhotoService? _providedLocalPhotos;
  late final LocalPhotoService localPhotos =
      _providedLocalPhotos ?? LocalPhotoService(auth: _providedAuth);
  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;
  FirebaseStorage get _storage => _providedStorage ?? FirebaseStorage.instance;

  String _requireUid([String? expectedUid]) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw FirebaseAuthException(code: 'unauthenticated');
    if (expectedUid != null && uid != expectedUid) {
      throw FirebaseAuthException(code: 'permission-denied');
    }
    return uid;
  }

  bool hasSession(String uid) => _auth.currentUser?.uid == uid;

  final _deletions = <String, Future<TravelDeletionResult>>{};

  /// Confirma a exclusão no servidor antes de remover a foto correspondente.
  /// Uma falha de limpeza não desfaz a exclusão já confirmada do documento.
  Future<TravelDeletionResult> deleteEntry({
    required String uid,
    required TravelEntry entry,
  }) {
    _requireUid(uid);
    entry.validate(uid: uid);
    final key = '$uid/${entry.id}';
    return _deletions.putIfAbsent(
      key,
      () => _deleteEntry(uid, entry).whenComplete(() {
        _deletions.remove(key);
      }),
    );
  }

  Future<TravelDeletionResult> _deleteEntry(
    String uid,
    TravelEntry entry,
  ) async {
    final reference = _entries(uid).doc(entry.id);
    // A transação exige conexão e usa os dados atuais do documento, não um
    // caminho de foto recebido de uma tela possivelmente desatualizada.
    final deleted = await _firestore.runTransaction<TravelEntry?>((
      transaction,
    ) async {
      _requireUid(uid);
      final snapshot = await transaction.get(reference);
      _requireUid(uid);
      if (!snapshot.exists) return null;
      final current = snapshot.data()!;
      current.validate(uid: uid);
      transaction.delete(reference);
      return current;
    });
    _requireUid(uid);
    // Documento ausente também confirma a exclusão e permite repetir a
    // limpeza após uma resposta perdida, usando somente o caminho validado.
    final photo = deleted ?? entry;
    if (!photo.hasPhoto) return const TravelDeletionResult();
    try {
      if (photo.isLocalPhoto) {
        await localPhotos.remove(
          uid: uid,
          entryId: photo.id,
          relativePath: photo.imagePath!,
        );
      } else {
        await _storage.ref(photo.imagePath!).delete();
      }
      _requireUid(uid);
      return const TravelDeletionResult();
    } on FirebaseException catch (error) {
      if (error.plugin == 'firebase_storage' &&
          error.code == 'object-not-found') {
        return const TravelDeletionResult();
      }
      return TravelDeletionResult(cleanupError: error);
    } catch (error) {
      return TravelDeletionResult(cleanupError: error);
    }
  }

  Future<TravelUploadAttempt> prepareUpload({
    required String uid,
    required String placeName,
    required String description,
    TravelPhoto? photo,
    GeoPoint? location,
    bool savePhotoLocally = false,
  }) async {
    _requireUid(uid);
    TravelEntry.validateContent(placeName: placeName, description: description);
    TravelEntry.validateLocation(location);
    await photo?.validateDecoded();
    _requireUid(uid);
    final id = createEntryId();
    return TravelUploadAttempt._(
      this,
      uid,
      id,
      placeName.trim(),
      description.trim(),
      photo,
      location,
      savePhotoLocally && photo != null,
    );
  }

  CollectionReference<TravelEntry> _entries(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('travel_entries')
      .withConverter<TravelEntry>(
        fromFirestore: (snapshot, _) => TravelEntry.fromFirestore(snapshot),
        toFirestore: (entry, _) => entry.toFirestore(),
      );

  Stream<List<TravelEntry>> watchEntries([String? uid]) {
    final owner = _requireUid(uid);
    return _entries(
      owner,
    ).orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      _requireUid(owner); // Não emitir dados de uma sessão anterior.
      return snapshot.docs.map((doc) => doc.data()).toList(growable: false);
    });
  }

  /// Reserva um ID localmente, sem gravar um documento incompleto.
  String createEntryId() => _entries(_requireUid()).doc().id;

  /// Persiste os metadados da memória sem acessar arquivos ou Storage.
  Future<String> createEntry(TravelEntry entry) async {
    final uid = _requireUid();
    entry.validate(uid: uid);
    await _entries(uid).doc(entry.id).set(entry);
    return entry.id;
  }

  Future<void> create({
    required String uid,
    required String placeName,
    required String description,
    TravelPhoto? photo,
    required void Function(double) onProgress,
    GeoPoint? location,
  }) async {
    final attempt = await prepareUpload(
      uid: uid,
      placeName: placeName,
      description: description,
      photo: photo,
      location: location,
    );
    await attempt.save(onProgress: onProgress);
  }
}

class TravelDeletionResult {
  const TravelDeletionResult({this.cleanupError});
  final Object? cleanupError;
}

class TravelUploadException implements Exception {
  const TravelUploadException(
    this.original, {
    this.cleanupError,
    this.needsReconciliation = false,
  });
  final Object original;
  final Object? cleanupError;
  final bool needsReconciliation;
}

/// Uma tentativa mantém o mesmo documento e o mesmo objeto em todas as retomadas.
class TravelUploadAttempt {
  TravelUploadAttempt._(
    this._service,
    this.uid,
    this.entryId,
    this.placeName,
    this.description,
    this.photo,
    this.location,
    this.savePhotoLocally,
  );

  final TravelEntryService _service;
  final String uid;
  final String entryId;
  final String placeName;
  final String description;
  final TravelPhoto? photo;
  final GeoPoint? location;
  final bool savePhotoLocally;
  String? get imagePath => photo == null
      ? null
      : 'users/$uid/travel_entries/$entryId/memoria.${photo!.extension}';
  Reference get _reference => _service._storage.ref(imagePath!);
  Future<void>? _running;
  UploadTask? _task;
  bool _cancelled = false;
  bool _sessionLost = false;
  bool _uploaded = false;
  bool _uploadStarted = false;
  bool _localCopyStarted = false;
  bool _localCopied = false;
  bool _writeSubmitted = false;
  bool _saved = false;
  bool _needsReconciliation = false;
  bool _cleaningUp = false;
  Object? _lastError;
  String? _imageUrl;

  bool get canCancel =>
      _running != null && !_writeSubmitted && !_saved && !_cleaningUp;
  bool get canEdit => _running == null && !_needsReconciliation && !_saved;
  bool get needsReconciliation => _needsReconciliation;
  bool get isCleaningUp => _cleaningUp;
  Object? get lastError => _lastError;

  void _reportProgress(void Function(double) callback, double value) {
    try {
      callback(value);
    } catch (_) {
      // Feedback não pode alterar o resultado da gravação ou ocultar sua causa.
    }
  }

  void _checkActive() {
    if (_sessionLost || !_service.hasSession(uid)) {
      throw FirebaseAuthException(code: 'unauthenticated');
    }
    if (_cancelled) {
      throw FirebaseException(plugin: 'firebase_storage', code: 'canceled');
    }
  }

  Future<bool> cancel() async {
    if (!canCancel) {
      return false; // Uma escrita Firestore já enviada não pode ser cancelada.
    }
    _cancelled = true;
    try {
      await _task?.cancel();
    } catch (_) {
      /* O await do envio trata a falha. */
    }
    return true;
  }

  Future<void> save({required void Function(double) onProgress}) {
    final running = _running;
    if (running != null) return running;
    _cancelled = false;
    _running = _run(onProgress).whenComplete(() {
      _running = null;
    });
    return _running!;
  }

  bool _matches(TravelEntry entry) =>
      entry.createdAt != null &&
      entry.placeName == placeName &&
      entry.description == description &&
      entry.imagePath == imagePath &&
      entry.isLocalPhoto == savePhotoLocally &&
      entry.location == location;

  Future<void> _run(void Function(double) onProgress) async {
    StreamSubscription<TaskSnapshot>? progress;
    StreamSubscription<User?>? session;
    var checkingPrevious = _needsReconciliation;
    _lastError = null;
    try {
      _checkActive();
      if (_saved) return;
      session = _service._auth.authStateChanges().listen(
        (user) {
          if (user?.uid != uid) {
            _sessionLost = true;
            unawaited(cancel());
          }
        },
        onError: (Object _) {
          _sessionLost = true;
          unawaited(cancel());
        },
      );

      if (_needsReconciliation) {
        // Não criar um segundo documento se a confirmação anterior foi perdida.
        final previous = await _service
            ._entries(uid)
            .doc(entryId)
            .get(const GetOptions(source: Source.server));
        _checkActive();
        if (previous.metadata.hasPendingWrites) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'unavailable',
          );
        }
        if (previous.exists) {
          if (!_matches(previous.data()!)) {
            throw const FormatException(
              'Um envio anterior foi confirmado. Confira seu diário antes de continuar.',
            );
          }
          _saved = true;
          return;
        }
        _needsReconciliation = false;
        _writeSubmitted = false;
        checkingPrevious = false;
      }

      // Uma tarefa pode ter gravado o objeto e perdido a resposta final. Antes
      // de reenviar, confira o objeto desta tentativa, mesmo sem um ACK local.
      if (photo != null && savePhotoLocally && !_localCopied) {
        _localCopyStarted = true;
        await _service.localPhotos.write(
          uid: uid,
          entryId: entryId,
          relativePath: imagePath!,
          photo: photo!,
        );
        _localCopied = true;
      }
      _checkActive();
      if (photo != null && !savePhotoLocally && _uploadStarted) {
        try {
          await _reference.getMetadata();
          _uploaded = true;
        } on FirebaseException catch (error) {
          if (error.code != 'object-not-found') rethrow;
          _uploaded = false;
          _imageUrl = null;
        }
      }
      _checkActive();
      if (photo != null && !savePhotoLocally && !_uploaded) {
        _uploadStarted = true;
        final task = _reference.putData(
          photo!.bytes,
          SettableMetadata(contentType: photo!.contentType),
        );
        _task = task;
        progress = task.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes > 0) {
            _reportProgress(
              onProgress,
              (snapshot.bytesTransferred / snapshot.totalBytes).clamp(0, 1),
            );
          }
        }, onError: (Object _) {});
        await task;
        _uploaded = true;
      }
      _checkActive();
      if (photo != null && !savePhotoLocally) {
        _imageUrl ??= await _reference.getDownloadURL();
      }
      _checkActive();
      _reportProgress(onProgress, 1);
      _writeSubmitted = true;
      await _service.createEntry(
        TravelEntry(
          id: entryId,
          placeName: placeName,
          description: description,
          imageUrl: _imageUrl,
          imagePath: imagePath,
          isLocalPhoto: savePhotoLocally,
          location: location,
        ),
      );
      _saved = true;
      _checkActive(); // Não sinalizar sucesso para uma sessão que foi encerrada.
    } catch (caught) {
      final error =
          _sessionLost &&
              caught is FirebaseException &&
              caught.code == 'canceled'
          ? FirebaseAuthException(code: 'unauthenticated')
          : caught;
      if (_saved) throw TravelUploadException(error);
      const rejected = {
        'permission-denied',
        'unauthenticated',
        'invalid-argument',
        'failed-precondition',
      };
      _needsReconciliation =
          _needsReconciliation ||
          (_writeSubmitted &&
              !(caught is FirebaseException && rejected.contains(caught.code)));
      Object? cleanupError;
      _lastError = error;
      // Uma resposta incerta pode anteceder uma confirmação tardia da escrita.
      // Não apagar a foto até reconciliar: a ausência momentânea do documento
      // nas regras do Storage não significa que a escrita foi rejeitada.
      if ((_uploadStarted || _localCopyStarted) &&
          !checkingPrevious &&
          !_needsReconciliation) {
        _cleaningUp = true;
        _reportProgress(onProgress, 1);
        try {
          // Somente este objeto. As regras negam exclusão se o documento existe.
          if (savePhotoLocally) {
            if (_writeSubmitted) {
              final confirmed = await _service
                  ._entries(uid)
                  .doc(entryId)
                  .get(const GetOptions(source: Source.server));
              if (confirmed.exists || confirmed.metadata.hasPendingWrites) {
                _needsReconciliation = true;
                throw const LocalPhotoException(
                  'A foto foi mantida enquanto a confirmação do registro é verificada.',
                );
              }
            }
            await _service.localPhotos.remove(
              uid: uid,
              entryId: entryId,
              relativePath: imagePath!,
            );
            _localCopied = false;
          } else {
            await _reference.delete();
          }
          _uploaded = false;
          _imageUrl = null;
        } on FirebaseException catch (failure) {
          if (failure.code != 'object-not-found') cleanupError = failure;
        } catch (failure) {
          cleanupError = failure;
        } finally {
          _cleaningUp = false;
        }
      }
      if (!_needsReconciliation) _writeSubmitted = false;
      throw TravelUploadException(
        error,
        cleanupError: cleanupError,
        needsReconciliation: _needsReconciliation,
      );
    } finally {
      _task = null;
      await progress?.cancel();
      await session?.cancel();
    }
  }
}
