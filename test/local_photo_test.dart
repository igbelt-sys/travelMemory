import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wanderlog/models/travel_entry.dart';
import 'package:wanderlog/services/local_photo_service.dart';
import 'package:wanderlog/services/travel_entry_service.dart';
import 'package:wanderlog/widgets/local_entry_photo.dart';

import 'helpers/upload_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late UploadAuth auth;
  late LocalPhotoService photos;
  const imagePath = 'users/ana/travel_entries/id/memoria.png';
  Future<void> confirm(TravelUploadAttempt attempt) async {
    try {
      await attempt.save(onProgress: (_) {});
    } on TravelUploadException catch (error, stack) {
      Error.throwWithStackTrace(error.original, stack);
    }
  }

  setUp(() async {
    FakeFirebaseFirestore(); // Instala o FieldValueFactory de teste antes do modelo.
    root = await Directory.systemTemp.createTemp('wanderlog-local-');
    auth = UploadAuth();
    photos = LocalPhotoService(auth: auth, rootPath: () async => root.path);
  });
  tearDown(() async {
    await auth.changes.close();
    final target = await root.resolveSymbolicLinks();
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    if (!p.isWithin(temp, target) ||
        !p.basename(target).startsWith('wanderlog-local-')) {
      throw StateError('Pasta temporária fora do escopo do teste.');
    }
    await root.delete(recursive: true);
  });

  test(
    'cópia permanece após recriar serviço e sair/entrar na mesma conta',
    () async {
      final photo = await validPhoto();
      await photos.write(
        uid: 'ana',
        entryId: 'id',
        relativePath: imagePath,
        photo: photo,
      );
      // A origem da galeria não é necessária para ler a cópia permanente.
      final again = LocalPhotoService(
        auth: auth,
        rootPath: () async => root.path,
      );
      await auth.signOut();
      await expectLater(
        again.read(uid: 'ana', entryId: 'id', relativePath: imagePath),
        throwsA(isA<FirebaseException>()),
      );
      auth.user = UploadUser('ana');
      expect(
        await again.read(uid: 'ana', entryId: 'id', relativePath: imagePath),
        photo.bytes,
      );
      await again.write(
        uid: 'ana',
        entryId: 'id',
        relativePath: imagePath,
        photo: photo,
      );
      expect(
        await again.read(uid: 'ana', entryId: 'id', relativePath: imagePath),
        photo.bytes,
      );
    },
  );

  test('outra conta não lê a foto nem atravessa diretórios', () async {
    await photos.write(
      uid: 'ana',
      entryId: 'id',
      relativePath: imagePath,
      photo: await validPhoto(),
    );
    auth.user = UploadUser('bia');
    await expectLater(
      photos.read(uid: 'ana', entryId: 'id', relativePath: imagePath),
      throwsA(isA<FirebaseException>()),
    );
    await expectLater(
      photos.read(uid: 'bia', entryId: 'id', relativePath: imagePath),
      throwsFormatException,
    );
    auth.user = UploadUser('ana');
    for (final path in [
      '/etc/foto.png',
      'users/ana/travel_entries/id/../../foto.png',
      'users/ana/travel_entries/outro/foto.png',
      r'users\ana\travel_entries\id\foto.png',
    ]) {
      await expectLater(
        photos.read(uid: 'ana', entryId: 'id', relativePath: path),
        throwsFormatException,
      );
    }
  });

  test('excluir memória remove somente seu arquivo permanente', () async {
    final db = FakeFirebaseFirestore();
    final service = TravelEntryService(
      firestore: db,
      auth: auth,
      localPhotos: photos,
    );
    final photo = await validPhoto();
    await photos.write(
      uid: 'ana',
      entryId: 'id',
      relativePath: imagePath,
      photo: photo,
    );
    const otherPath = 'users/ana/travel_entries/outra/memoria.png';
    await photos.write(
      uid: 'ana',
      entryId: 'outra',
      relativePath: otherPath,
      photo: photo,
    );
    const entry = TravelEntry(
      id: 'id',
      placeName: 'Lugar',
      description: 'Memória',
      isLocalPhoto: true,
      imagePath: imagePath,
    );
    await service.createEntry(entry);
    expect(
      (await service.deleteEntry(uid: 'ana', entry: entry)).cleanupError,
      isNull,
    );
    expect(
      await photos.read(uid: 'ana', entryId: 'id', relativePath: imagePath),
      isNull,
    );
    expect(
      await photos.read(uid: 'ana', entryId: 'outra', relativePath: otherPath),
      photo.bytes,
    );
  });

  test(
    'arquivo ausente em outro dispositivo retorna ausência sem criar foto',
    () async {
      expect(
        await photos.read(uid: 'ana', entryId: 'id', relativePath: imagePath),
        isNull,
      );
      expect(await root.list().length, 0);
    },
  );

  test('modelo distingue foto local, foto Storage e memória sem foto', () {
    const entry = TravelEntry(
      id: 'id',
      placeName: 'Praia',
      description: 'Memória',
      imagePath: imagePath,
      isLocalPhoto: true,
      location: GeoPoint(-22.7, -47.2),
    );
    final map = entry.toFirestore();
    expect(map['imageUrl'], isNull);
    expect(map['imageSource'], 'local');
    final decoded = TravelEntry.fromMap('id', {
      ...map,
      'createdAt': null,
    }, uid: 'ana');
    expect(decoded.hasPhoto, isTrue);
    expect(decoded.isLocalPhoto, isTrue);
    expect(
      () => TravelEntry.fromMap('id', {...map, 'createdAt': null}, uid: 'bia'),
      throwsFormatException,
    );
    expect(
      () => TravelEntry.fromMap('id', {
        ...map,
        'imageUrl': 'https://example.com/foto.png',
        'createdAt': null,
      }),
      throwsFormatException,
    );
    expect(
      () => TravelEntry.fromMap('id', {
        ...map,
        'imageSource': 'arquivo',
        'createdAt': null,
      }),
      throwsFormatException,
    );
  });

  test(
    'salva foto permanente e GeoPoint sem nenhuma referência ao Storage',
    () async {
      final db = FakeFirebaseFirestore();
      final storage = MemoryStorage(db);
      final entries = UploadService(db, auth, storage, localPhotos: photos);
      final photo = await validPhoto();
      final attempt = await entries.prepareUpload(
        uid: 'ana',
        placeName: 'Praia',
        description: 'Memória',
        photo: photo,
        savePhotoLocally: true,
        location: const GeoPoint(-22.7, -47.2),
      );
      await confirm(attempt);
      await confirm(attempt);
      final data =
          (await db.doc('users/ana/travel_entries/${attempt.entryId}').get())
              .data()!;
      expect(data['imageSource'], 'local');
      expect(data['imageUrl'], isNull);
      expect(data['imagePath'], attempt.imagePath);
      expect(data['location'], const GeoPoint(-22.7, -47.2));
      expect(data['createdAt'], isA<Timestamp>());
      expect(storage.references, 0);
      expect(entries.writes, 1);
      expect(
        await photos.read(
          uid: 'ana',
          entryId: attempt.entryId,
          relativePath: attempt.imagePath!,
        ),
        photo.bytes,
      );
    },
  );

  test(
    'escrita rejeitada limpa só a cópia da tentativa e retoma o mesmo ID',
    () async {
      final db = FakeFirebaseFirestore();
      final storage = MemoryStorage(db);
      final entries = UploadService(db, auth, storage, localPhotos: photos)
        ..writeError = FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      final attempt = await entries.prepareUpload(
        uid: 'ana',
        placeName: 'Praia',
        description: 'Memória',
        photo: await validPhoto(),
        savePhotoLocally: true,
      );
      await expectLater(
        attempt.save(onProgress: (_) {}),
        throwsA(isA<TravelUploadException>()),
      );
      expect(
        await photos.read(
          uid: 'ana',
          entryId: attempt.entryId,
          relativePath: attempt.imagePath!,
        ),
        isNull,
      );
      entries.writeError = null;
      await confirm(attempt);
      expect(entries.reservations, 1);
      expect(storage.references, 0);
    },
  );

  test('confirmação perdida mantém foto e reconcilia sem duplicar', () async {
    final db = FakeFirebaseFirestore();
    final storage = MemoryStorage(db);
    final entries = UploadService(db, auth, storage, localPhotos: photos)
      ..afterWriteError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
      );
    final photo = await validPhoto();
    final attempt = await entries.prepareUpload(
      uid: 'ana',
      placeName: 'Praia',
      description: 'Memória',
      photo: photo,
      savePhotoLocally: true,
    );
    await expectLater(
      attempt.save(onProgress: (_) {}),
      throwsA(isA<TravelUploadException>()),
    );
    expect(attempt.needsReconciliation, isTrue);
    expect(
      await photos.read(
        uid: 'ana',
        entryId: attempt.entryId,
        relativePath: attempt.imagePath!,
      ),
      photo.bytes,
    );
    await confirm(attempt);
    expect(entries.writes, 1);
    expect(storage.references, 0);
  });

  testWidgets('foto local ausente mostra explicação sem tentar URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalEntryPhoto(
            uid: 'ana',
            entryId: 'id',
            imagePath: imagePath,
            placeName: 'Praia',
            photos: photos,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Foto não disponível neste dispositivo.'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
