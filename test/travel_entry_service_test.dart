import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlog/models/travel_entry.dart';
import 'package:wanderlog/services/travel_entry_service.dart';

class TestUser implements User {
  TestUser(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAuth implements FirebaseAuth {
  TestAuth(String? uid) : currentUser = uid == null ? null : TestUser(uid);
  @override
  User? currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TravelEntry entry({
  String id = 'viagem',
  String uid = 'ana',
  String? description,
}) => TravelEntry(
  id: id,
  placeName: 'Praia',
  description: description ?? 'Um dia especial',
  imageUrl: 'https://example.com/foto.jpg',
  imagePath: 'users/$uid/travel_entries/$id/foto.jpg',
);

void main() {
  late FakeFirebaseFirestore db;
  late TestAuth auth;
  late TravelEntryService service;
  setUp(() {
    db = FakeFirebaseFirestore();
    auth = TestAuth('ana');
    service = TravelEntryService(firestore: db, auth: auth);
  });

  test(
    'cria documento tipado na pasta da sessão sem depender de Storage',
    () async {
      final id = await service.createEntry(entry());
      final document = await db.doc('users/ana/travel_entries/$id').get();
      expect(document.exists, isTrue);
      expect(document.data()!['createdAt'], isA<Timestamp>());
      expect(document.data()!['location'], isNull);
      expect(
        document.data()!['imagePath'],
        'users/ana/travel_entries/viagem/foto.jpg',
      );
      expect(
        (await db.collection('users/bia/travel_entries').get()).docs,
        isEmpty,
      );
      expect((await service.watchEntries().first).single.id, id);
    },
  );

  test('reserva ID sem gravar dados incompletos', () async {
    expect(service.createEntryId(), isNotEmpty);
    expect(
      (await db.collection('users/ana/travel_entries').get()).docs,
      isEmpty,
    );
  });

  test('nega sessão ausente antes de ler ou escrever', () async {
    auth.currentUser = null;
    expect(() => service.watchEntries(), throwsA(isA<FirebaseAuthException>()));
    expect(
      () => service.createEntryId(),
      throwsA(isA<FirebaseAuthException>()),
    );
    await expectLater(
      service.createEntry(entry()),
      throwsA(isA<FirebaseAuthException>()),
    );
  });

  test('nega UID informado de outra conta e caminho de outra pasta', () async {
    expect(
      () => service.watchEntries('bia'),
      throwsA(isA<FirebaseAuthException>()),
    );
    await expectLater(
      service.createEntry(entry(uid: 'bia')),
      throwsFormatException,
    );
    expect(
      (await db.collection('users/ana/travel_entries').get()).docs,
      isEmpty,
    );
  });

  test('valida os limites antes de gravar', () async {
    await expectLater(
      service.createEntry(entry(description: 'x' * 2001)),
      throwsFormatException,
    );
    await service.createEntry(entry(description: 'x' * 2000));
    expect(
      (await db.collection('users/ana/travel_entries').get()).docs,
      hasLength(1),
    );
  });

  test(
    'lista somente o usuário autenticado, do mais recente ao mais antigo',
    () async {
      for (final values in [
        ('antiga', 'ana', 1),
        ('recente', 'ana', 3),
        ('outra', 'bia', 4),
      ]) {
        await db.doc('users/${values.$2}/travel_entries/${values.$1}').set({
          ...entry(id: values.$1, uid: values.$2).toFirestore(),
          'createdAt': Timestamp.fromMillisecondsSinceEpoch(values.$3 * 1000),
        });
      }
      final entries = await service.watchEntries().first;
      expect(entries.map((entry) => entry.id), ['recente', 'antiga']);
    },
  );

  test(
    'não emite eventos de uma sessão anterior depois de trocar conta',
    () async {
      final iterator = StreamIterator(service.watchEntries());
      expect(await iterator.moveNext(), isTrue);
      auth.currentUser = TestUser('bia');
      await db
          .doc('users/ana/travel_entries/viagem')
          .set(entry().toFirestore());
      await expectLater(
        iterator.moveNext(),
        throwsA(isA<FirebaseAuthException>()),
      );
      await iterator.cancel();
    },
  );
}
