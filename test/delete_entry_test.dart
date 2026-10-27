import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlog/models/travel_entry.dart';
import 'package:wanderlog/services/local_photo_service.dart';
import 'package:wanderlog/services/travel_entry_service.dart';

import 'helpers/upload_fakes.dart';

class DeletionFirestore extends FakeFirebaseFirestore {
  Object? failure;
  Completer<void>? gate;
  int transactions = 0;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    transactions++;
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return super.runTransaction(
      transactionHandler,
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
  }
}

class DeletionPhotos extends LocalPhotoService {
  DeletionPhotos(this.db);
  final FakeFirebaseFirestore db;
  final removed = <String>[];
  Object? failure;

  @override
  Future<void> remove({
    required String uid,
    required String entryId,
    required String relativePath,
  }) async {
    // Falha imediatamente se a implementação apagar a foto antes do documento.
    expect(
      (await db.doc('users/$uid/travel_entries/$entryId').get()).exists,
      isFalse,
    );
    if (failure != null) throw failure!;
    removed.add(relativePath);
  }
}

const localEntry = TravelEntry(
  id: 'viagem',
  placeName: 'Viagem',
  description: 'Uma lembrança',
  isLocalPhoto: true,
  imagePath: 'users/ana/travel_entries/viagem/memoria.png',
);

void main() {
  late DeletionFirestore db;
  late UploadAuth auth;
  late MemoryStorage storage;
  late DeletionPhotos photos;
  late TravelEntryService service;
  setUp(() {
    db = DeletionFirestore();
    auth = UploadAuth();
    storage = MemoryStorage(db);
    photos = DeletionPhotos(db);
    service = TravelEntryService(
      firestore: db,
      auth: auth,
      storage: storage,
      localPhotos: photos,
    );
  });
  tearDown(() => auth.changes.close());

  test(
    'exclui documento antes da foto local e preserva outras memórias',
    () async {
      await service.createEntry(localEntry);
      await db.doc('users/ana/travel_entries/outra').set({
        'placeName': 'Outra',
      });
      final result = await service.deleteEntry(uid: 'ana', entry: localEntry);
      expect(result.cleanupError, isNull);
      expect(photos.removed, [localEntry.imagePath]);
      expect(
        (await db.doc('users/ana/travel_entries/viagem').get()).exists,
        isFalse,
      );
      expect(
        (await db.doc('users/ana/travel_entries/outra').get()).exists,
        isTrue,
      );
      expect(storage.references, 0);
    },
  );

  test('sem foto não acessa arquivos nem Storage', () async {
    const entry = TravelEntry(
      id: 'sem-foto',
      placeName: 'Lugar',
      description: 'Memória',
    );
    await service.createEntry(entry);
    await service.deleteEntry(uid: 'ana', entry: entry);
    expect(photos.removed, isEmpty);
    expect(storage.references, 0);
    expect((await service.watchEntries().first), isEmpty);
  });

  test(
    'usa o caminho atual do servidor e não o caminho antigo da tela',
    () async {
      const stored = TravelEntry(
        id: 'viagem',
        placeName: 'Viagem',
        description: 'Memória',
        isLocalPhoto: true,
        imagePath: 'users/ana/travel_entries/viagem/atual.png',
      );
      await service.createEntry(stored);
      await service.deleteEntry(uid: 'ana', entry: localEntry);
      expect(photos.removed, [stored.imagePath]);
    },
  );

  test(
    'nega outra conta, visitante e caminho alheio antes de excluir',
    () async {
      await service.createEntry(localEntry);
      auth.user = UploadUser('bia');
      expect(
        () => service.deleteEntry(uid: 'ana', entry: localEntry),
        throwsA(isA<FirebaseException>()),
      );
      expect(
        () => service.deleteEntry(uid: 'bia', entry: localEntry),
        throwsFormatException,
      );
      auth.user = null;
      expect(
        () => service.deleteEntry(uid: 'ana', entry: localEntry),
        throwsA(isA<FirebaseException>()),
      );
      expect(db.transactions, 0);
      expect(photos.removed, isEmpty);
      expect(
        (await db.doc('users/ana/travel_entries/viagem').get()).exists,
        isTrue,
      );
    },
  );

  test('falha no Firestore preserva a foto e permite nova tentativa', () async {
    await service.createEntry(localEntry);
    db.failure = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
    );
    await expectLater(
      service.deleteEntry(uid: 'ana', entry: localEntry),
      throwsA(isA<FirebaseException>()),
    );
    expect(photos.removed, isEmpty);
    expect(
      (await db.doc('users/ana/travel_entries/viagem').get()).exists,
      isTrue,
    );
    db.failure = null;
    await service.deleteEntry(uid: 'ana', entry: localEntry);
    expect(photos.removed, [localEntry.imagePath]);
  });

  test(
    'cliques concorrentes compartilham a exclusão e sessão trocada cancela',
    () async {
      await service.createEntry(localEntry);
      db.gate = Completer<void>();
      final first = service.deleteEntry(uid: 'ana', entry: localEntry);
      final second = service.deleteEntry(uid: 'ana', entry: localEntry);
      expect(identical(first, second), isTrue);
      expect(db.transactions, 1);
      auth.user = UploadUser('bia');
      final failure = expectLater(first, throwsA(isA<FirebaseException>()));
      db.gate!.complete();
      await failure;
      expect(photos.removed, isEmpty);
      expect(
        (await db.doc('users/ana/travel_entries/viagem').get()).exists,
        isTrue,
      );
    },
  );

  test(
    'falha de limpeza é informada sem esconder exclusão confirmada',
    () async {
      await service.createEntry(localEntry);
      photos.failure = const LocalPhotoException('Disco indisponível');
      final result = await service.deleteEntry(uid: 'ana', entry: localEntry);
      expect(result.cleanupError, same(photos.failure));
      expect(
        (await db.doc('users/ana/travel_entries/viagem').get()).exists,
        isFalse,
      );
      photos.failure = null;
      await service.deleteEntry(uid: 'ana', entry: localEntry);
      expect(photos.removed, [localEntry.imagePath]);
    },
  );

  test(
    'foto antiga no Storage é removida só após o documento; ausência é aceita',
    () async {
      const entry = TravelEntry(
        id: 'viagem',
        placeName: 'Lugar',
        description: 'Memória',
        imageUrl: 'https://example.com/foto.png',
        imagePath: 'users/ana/travel_entries/viagem/foto.png',
      );
      await service.createEntry(entry);
      await service.deleteEntry(uid: 'ana', entry: entry);
      expect(storage.deleted, [entry.imagePath]);
      expect(photos.removed, isEmpty);
      storage.deleteError = FirebaseException(
        plugin: 'firebase_storage',
        code: 'object-not-found',
      );
      expect(
        (await service.deleteEntry(uid: 'ana', entry: entry)).cleanupError,
        isNull,
      );
    },
  );
}
