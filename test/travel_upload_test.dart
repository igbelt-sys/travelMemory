import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlog/services/travel_entry_service.dart';
import 'package:wanderlog/services/photo_service.dart';

import 'helpers/upload_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeFirebaseFirestore db;
  late UploadAuth auth;
  late MemoryStorage storage;
  late UploadService service;
  setUp(() {
    db = FakeFirebaseFirestore();
    auth = UploadAuth();
    storage = MemoryStorage(db);
    service = UploadService(db, auth, storage);
  });
  tearDown(() async {
    await auth.changes.close();
    await storage.task?.progress.close();
  });

  Future<TravelUploadAttempt> prepare({GeoPoint? location}) async =>
      service.prepareUpload(
        uid: 'ana',
        placeName: 'Praia',
        description: 'Uma memória',
        photo: await validPhoto(),
        location: location,
      );

  test(
    'sem foto salva GeoPoint e confirma uma única escrita sem tocar no Storage',
    () async {
      service.writeGate = Completer<void>();
      final attempt = await service.prepareUpload(
        uid: 'ana',
        placeName: 'Praia',
        description: 'Sem foto',
        location: const GeoPoint(-22.70584, -47.27556),
      );
      final first = attempt.save(onProgress: (_) {});
      expect(identical(first, attempt.save(onProgress: (_) {})), isTrue);
      await service.enteredWrite.future;
      expect(service.writes, 1);
      expect(storage.references, 0);
      service.writeGate!.complete();
      await first;
      await attempt.save(onProgress: (_) {});
      final saved =
          (await db.doc('users/ana/travel_entries/${attempt.entryId}').get())
              .data()!;
      expect(saved['imageUrl'], isNull);
      expect(saved['imagePath'], isNull);
      expect(saved['location'], const GeoPoint(-22.70584, -47.27556));
      expect(saved['createdAt'], isA<Timestamp>());
      expect(service.writes, 1);
      expect(storage.references, 0);
    },
  );

  test('sem foto e sem coordenadas salva null sem chamar Storage', () async {
    final attempt = await service.prepareUpload(
      uid: 'ana',
      placeName: 'Passeio',
      description: 'Memória',
    );
    await attempt.save(onProgress: (_) {});
    expect(service.written!.location, isNull);
    expect(storage.references, 0);
  });

  test(
    'sem foto preserva erro de escrita e retoma mesmo ID sem limpeza de imagem',
    () async {
      service.writeError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      final attempt = await service.prepareUpload(
        uid: 'ana',
        placeName: 'Passeio',
        description: 'Memória',
      );
      await expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(isA<TravelUploadException>()),
      );
      expect(storage.references, 0);
      service.writeError = null;
      await attempt.save(onProgress: (_) {});
      expect(service.reservations, 1);
      expect(
        (await db.collection('users/ana/travel_entries').get()).docs,
        hasLength(1),
      );
    },
  );

  test('sem foto reconcilia confirmação perdida sem duplicar', () async {
    service.afterWriteError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'deadline-exceeded',
    );
    final attempt = await service.prepareUpload(
      uid: 'ana',
      placeName: 'Passeio',
      description: 'Memória',
    );
    await expectLater(
      attempt.save(onProgress: (_) {}),
      throwsA(isA<TravelUploadException>()),
    );
    expect(attempt.needsReconciliation, isTrue);
    await attempt.save(onProgress: (_) {});
    expect(service.writes, 1);
    expect(storage.references, 0);
  });

  test('campos inválidos não reservam ID nem iniciam upload', () async {
    await expectLater(
      service.prepareUpload(
        uid: 'ana',
        placeName: '',
        description: 'Memória',
        photo: await validPhoto(),
      ),
      throwsFormatException,
    );
    expect(service.reservations, 0);
    expect(storage.puts, 0);
  });

  test(
    'valida antes de reservar ou enviar e salva GeoPoint com timestamp',
    () async {
      final attempt = await prepare(location: const GeoPoint(0, 0));
      expect(storage.puts, 0);
      expect(
        (await db.collection('users/ana/travel_entries').get()).docs,
        isEmpty,
      );
      final values = <double>[];
      await attempt.save(onProgress: values.add);
      final data =
          (await db.doc('users/ana/travel_entries/${attempt.entryId}').get())
              .data()!;
      expect(
        data['location'],
        const GeoPoint(0, 0),
      ); // Válido somente porque foi informado.
      expect(data['createdAt'], isA<Timestamp>());
      expect(data['imagePath'], attempt.imagePath);
      expect(storage.events.last, 'firestore');
      expect(
        storage.events.indexOf('url'),
        lessThan(storage.events.indexOf('firestore')),
      );
      expect(values.last, 1);
    },
  );

  test(
    'mesma tentativa compartilha envio e aguarda confirmação do Firestore',
    () async {
      service.writeGate = Completer<void>();
      final attempt = await prepare();
      final first = attempt.save(onProgress: (_) {});
      final second = attempt.save(onProgress: (_) {});
      expect(identical(first, second), isTrue);
      await service.enteredWrite.future;
      expect(storage.puts, 1);
      expect(service.writes, 1);
      expect(attempt.canCancel, isFalse);
      expect(await attempt.cancel(), isFalse);
      service.writeGate!.complete();
      await first;
      await attempt.save(onProgress: (_) {});
      expect(storage.puts, 1);
      expect(service.writes, 1);
      expect(service.written!.location, isNull);
    },
  );

  test(
    'falha de escrita remove somente a imagem da tentativa e permite retomar o mesmo ID',
    () async {
      final original = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      service.writeError = original;
      storage.files['users/ana/travel_entries/antiga/foto.jpg'] =
          (await validPhoto()).bytes;
      final attempt = await prepare();
      await expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(
          isA<TravelUploadException>().having(
            (e) => e.original,
            'original',
            same(original),
          ),
        ),
      );
      expect(storage.deleted, [attempt.imagePath]);
      expect(storage.files.keys, ['users/ana/travel_entries/antiga/foto.jpg']);
      service.writeError = null;
      await attempt.save(onProgress: (_) {});
      expect(
        (await db.collection('users/ana/travel_entries').get()).docs.single.id,
        attempt.entryId,
      );
    },
  );

  test(
    'falha na limpeza não oculta erro original e reutiliza objeto existente',
    () async {
      final original = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      service.writeError = original;
      storage.deleteError = FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthorized',
      );
      final attempt = await prepare();
      await expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(
          isA<TravelUploadException>()
              .having((e) => e.original, 'original', same(original))
              .having((e) => e.cleanupError, 'limpeza', isNotNull),
        ),
      );
      service.writeError = null;
      storage.deleteError = null;
      await attempt.save(onProgress: (_) {});
      expect(storage.puts, 1);
    },
  );

  test(
    'confirmação perdida é reconciliada sem duplicar documento ou remover foto confirmada',
    () async {
      service.afterWriteError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
      );
      final attempt = await prepare();
      await expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(isA<TravelUploadException>()),
      );
      expect(attempt.needsReconciliation, isTrue);
      expect(attempt.canEdit, isFalse);
      await attempt.save(onProgress: (_) {});
      expect(service.writes, 1);
      expect(storage.puts, 1);
      expect(storage.files.containsKey(attempt.imagePath), isTrue);
      expect(
        (await db.collection('users/ana/travel_entries').get()).docs,
        hasLength(1),
      );
    },
  );

  test(
    'resposta perdida do upload reutiliza a imagem se a limpeza também falhar',
    () async {
      storage.uploadResponseError = FirebaseException(
        plugin: 'firebase_storage',
        code: 'retry-limit-exceeded',
      );
      storage.deleteError = FirebaseException(
        plugin: 'firebase_storage',
        code: 'unavailable',
      );
      final attempt = await prepare();
      await expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(isA<TravelUploadException>()),
      );
      expect(storage.files.containsKey(attempt.imagePath), isTrue);
      expect(service.writes, 0);
      storage.uploadResponseError = null;
      storage.deleteError = null;
      await attempt.save(onProgress: (_) {});
      expect(storage.puts, 1);
      expect(service.writes, 1);
      expect(
        (await db.collection('users/ana/travel_entries').get()).docs.single.id,
        attempt.entryId,
      );
    },
  );

  test('imagem truncada não reserva ID nem inicia upload', () async {
    await expectLater(
      service.prepareUpload(
        uid: 'ana',
        placeName: 'Praia',
        description: 'Uma memória',
        photo: TravelPhoto(
          bytes: Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
          contentType: 'image/jpeg',
          extension: 'jpg',
        ),
      ),
      throwsFormatException,
    );
    expect(service.reservations, 0);
    expect(storage.puts, 0);
    expect(service.writes, 0);
  });

  test('falha ao obter URL limpa a foto e não grava documento', () async {
    final failure = FirebaseException(
      plugin: 'firebase_storage',
      code: 'retry-limit-exceeded',
    );
    storage.downloadUrlError = failure;
    final attempt = await prepare();
    await expectLater(
      attempt.save(onProgress: (_) {}),
      throwsA(
        isA<TravelUploadException>().having(
          (error) => error.original,
          'original',
          same(failure),
        ),
      ),
    );
    expect(service.writes, 0);
    expect(storage.deleted, [attempt.imagePath]);
    expect(storage.files, isEmpty);
    expect(attempt.needsReconciliation, isFalse);
    storage.downloadUrlError = null;
    await attempt.save(onProgress: (_) {});
    expect(service.reservations, 1);
    expect(service.writes, 1);
  });

  test(
    'escrita incerta preserva foto para confirmação tardia sem duplicar',
    () async {
      service.writeError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
      );
      final attempt = await prepare();
      await expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(isA<TravelUploadException>()),
      );
      expect(attempt.needsReconciliation, isTrue);
      expect(attempt.canEdit, isFalse);
      expect(storage.deleted, isEmpty);
      expect(storage.files.containsKey(attempt.imagePath), isTrue);
      // Simula uma confirmação que chega depois do erro de transporte.
      await db
          .doc('users/ana/travel_entries/${attempt.entryId}')
          .set(service.written!.toFirestore());
      service.writeError = null;
      await attempt.save(onProgress: (_) {});
      expect(service.writes, 1);
      expect(storage.puts, 1);
      expect(
        (await db.collection('users/ana/travel_entries').get()).docs,
        hasLength(1),
      );
    },
  );

  test(
    'escrita incerta sem documento retoma com mesmo ID e mesma foto',
    () async {
      service.writeError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      );
      final attempt = await prepare();
      await expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(isA<TravelUploadException>()),
      );
      expect(storage.deleted, isEmpty);
      service.writeError = null;
      await attempt.save(onProgress: (_) {});
      expect(service.reservations, 1);
      expect(storage.puts, 1);
      expect(service.writes, 2);
      expect(
        (await db.collection('users/ana/travel_entries').get()).docs.single.id,
        attempt.entryId,
      );
    },
  );

  test(
    'callback de progresso não transforma gravação confirmada em falha',
    () async {
      final attempt = await prepare();
      await attempt.save(
        onProgress: (_) => throw StateError('Observador indisponível'),
      );
      expect(service.writes, 1);
      expect(storage.deleted, isEmpty);
    },
  );

  test(
    'sessão encerrada após escrita não apaga foto confirmada nem retorna sucesso',
    () async {
      service.afterWriteGate = Completer<void>();
      final attempt = await prepare();
      final result = expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(isA<TravelUploadException>()),
      );
      await service.documentWritten.future;
      await auth.signOut();
      service.afterWriteGate!.complete();
      await result;
      expect(storage.deleted, isEmpty);
      expect(storage.files.containsKey(attempt.imagePath), isTrue);
      expect(
        (await db.collection('users/ana/travel_entries').get()).docs,
        hasLength(1),
      );
    },
  );

  test(
    'cancelamento e encerramento de sessão interrompem upload antes da escrita',
    () async {
      storage.autoComplete = false;
      final attempt = await prepare();
      final result = expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(isA<TravelUploadException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await attempt.cancel(), isTrue);
      await result;
      expect(service.writes, 0);

      final second = await prepare();
      final ended = expectLater(
        second.save(onProgress: (_) {}),
        throwsA(isA<TravelUploadException>()),
      );
      await Future<void>.delayed(Duration.zero);
      auth.signOut();
      await ended;
      expect(service.writes, 0);
    },
  );
}
