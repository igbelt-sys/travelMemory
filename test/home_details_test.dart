import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlog/models/travel_entry.dart';
import 'package:wanderlog/screens/auth_gate.dart';
import 'package:wanderlog/screens/auth_screen.dart';
import 'package:wanderlog/screens/entry_details_screen.dart';
import 'package:wanderlog/screens/home_screen.dart';
import 'package:wanderlog/screens/new_entry_screen.dart';
import 'package:wanderlog/services/auth_service.dart';
import 'package:wanderlog/services/photo_service.dart';
import 'package:wanderlog/services/travel_entry_service.dart';
import 'package:wanderlog/widgets/entry_photo.dart';
import 'package:wanderlog/widgets/travel_entry_card.dart';

import 'app_test.dart' show shell;
import 'helpers/upload_fakes.dart';

class NoGallery extends PhotoService {
  @override
  Future<TravelPhoto?> recoverLostPhoto() async => null;
  @override
  Future<TravelPhoto?> pick() async => null;
}

class CountingEntries extends UploadService {
  CountingEntries(super.db, super.auth, super.memory);
  int active = 0;
  int cancelled = 0;
  final requestedUids = <String>[];
  Completer<void>? deletionGate;
  Object? deletionError;
  Future<TravelDeletionResult>? deletion;
  int deleteCalls = 0;

  @override
  Future<TravelDeletionResult> deleteEntry({
    required String uid,
    required TravelEntry entry,
  }) {
    deleteCalls++;
    return deletion = _delete(uid, entry);
  }

  Future<TravelDeletionResult> _delete(String uid, TravelEntry entry) async {
    if (deletionGate != null) await deletionGate!.future;
    if (deletionError != null) throw deletionError!;
    return super.deleteEntry(uid: uid, entry: entry);
  }

  @override
  Stream<List<TravelEntry>> watchEntries([String? uid]) {
    requestedUids.add(uid ?? auth.currentUser!.uid);
    final source = super.watchEntries(uid);
    return Stream.multi((controller) {
      active++;
      final subscription = source.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () async {
        active--;
        cancelled++;
        await subscription.cancel();
      };
    });
  }
}

class ControlledEntries extends TravelEntryService {
  final events = StreamController<List<TravelEntry>>.broadcast();
  final uids = <String>[];
  @override
  bool hasSession(String uid) => uid == 'ana';
  @override
  Stream<List<TravelEntry>> watchEntries([String? uid]) {
    uids.add(uid!);
    return events.stream;
  }
}

TravelEntry memory({
  String id = 'memoria',
  String uid = 'ana',
  String name = 'Praia do Rosa',
  String description = 'Uma viagem inesquecível.',
  bool located = false,
  bool pending = false,
}) => TravelEntry(
  id: id,
  placeName: name,
  description: description,
  imageUrl: 'https://example.com/foto.png',
  imagePath: 'users/$uid/travel_entries/$id/foto.png',
  location: located ? const GeoPoint(-23.55, -46.63) : null,
  createdAt: pending ? null : DateTime(2026, 10, 27),
);

void main() {
  late FakeFirebaseFirestore db;
  late UploadAuth auth;
  late CountingEntries entries;
  setUp(() {
    db = FakeFirebaseFirestore();
    auth = UploadAuth();
    entries = CountingEntries(db, auth, MemoryStorage(db));
  });
  tearDown(() async {
    await auth.changes.close();
  });

  Future<void> openDiary(WidgetTester tester, {double scale = 1}) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData.fromView(
          tester.view,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: shell(
          AuthGate(
            auth: AuthService(auth: auth),
            entries: entries,
            photos: NoGallery(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> revealCard(WidgetTester tester) => tester.scrollUntilVisible(
    find.byType(TravelEntryCard),
    250,
    scrollable: find.byType(Scrollable).first,
  );

  Future<void> openDeletion(WidgetTester tester) async {
    await entries.createEntry(
      const TravelEntry(
        id: 'apagar',
        placeName: 'Memória para excluir',
        description: 'Teste de exclusão',
      ),
    );
    await openDiary(tester);
    await revealCard(tester);
    await tester.tap(find.text('Memória para excluir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Excluir memória'));
    await tester.pumpAndSettle();
    expect(find.text('Excluir memória?'), findsOneWidget);
  }

  testWidgets(
    'exclusão exige confirmação, aguarda servidor e atualiza a lista',
    (tester) async {
      await openDeletion(tester);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(entries.deleteCalls, 0);
      expect(
        (await db.doc('users/ana/travel_entries/apagar').get()).exists,
        isTrue,
      );
      await tester.tap(find.byTooltip('Excluir memória'));
      await tester.pumpAndSettle();
      entries.deletionGate = Completer<void>();
      await tester.tap(find.text('Excluir'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Excluindo memória…'), findsOneWidget);
      expect(find.text('Memória excluída do seu diário.'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Excluir memória',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(EntryDetailsScreen), findsOneWidget);
      expect(entries.deleteCalls, 1);
      await tester.runAsync(() async {
        entries.deletionGate!.complete();
        await entries.deletion;
      });
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailsScreen), findsNothing);
      expect(find.text('Memória excluída do seu diário.'), findsOneWidget);
      expect(find.text('Seu diário está de malas prontas'), findsOneWidget);
      expect(
        (await db.doc('users/ana/travel_entries/apagar').get()).exists,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('erro de exclusão mantém detalhes e permite tentar novamente', (
    tester,
  ) async {
    await openDeletion(tester);
    entries.deletionError = FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
    );
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryDetailsScreen), findsOneWidget);
    expect(
      find.textContaining('Não foi possível excluir a memória.'),
      findsOneWidget,
    );
    expect(
      (await db.doc('users/ana/travel_entries/apagar').get()).exists,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Excluir memória',
            ),
          )
          .onPressed,
      isNotNull,
    );
    entries.deletionError = null;
    await tester.tap(find.byTooltip('Excluir memória'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.runAsync(() async => await entries.deletion);
    await tester.pumpAndSettle();
    expect(find.byType(EntryDetailsScreen), findsNothing);
    expect(entries.deleteCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'encerrar sessão durante exclusão não mostra sucesso nem usa widget descartado',
    (tester) async {
      await openDeletion(tester);
      entries.deletionGate = Completer<void>();
      await tester.tap(find.text('Excluir'));
      await tester.pump(const Duration(milliseconds: 350));
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailsScreen), findsNothing);
      expect(find.byType(AuthScreen), findsOneWidget);
      await tester.runAsync(() async {
        final failure = expectLater(
          entries.deletion,
          throwsA(isA<FirebaseException>()),
        );
        entries.deletionGate!.complete();
        await failure;
      });
      await tester.pumpAndSettle();
      expect(find.text('Memória excluída do seu diário.'), findsNothing);
      expect(
        (await db.doc('users/ana/travel_entries/apagar').get()).exists,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'registro sem foto aparece na lista e abre detalhes com GeoPoint',
    (tester) async {
      await tester.runAsync(() async {
        final attempt = await entries.prepareUpload(
          uid: 'ana',
          placeName: 'Sem foto',
          description: 'Memória apenas com localização',
          location: const GeoPoint(-22.70584, -47.27556),
        );
        await attempt.save(onProgress: (_) {});
      });
      await openDiary(tester);
      await revealCard(tester);
      expect(find.byType(EntryPhoto), findsNothing);
      await tester.tap(find.text('Sem foto'));
      await tester.pumpAndSettle();
      expect(find.text('Memória sem foto'), findsOneWidget);
      expect(find.textContaining('Latitude: -22,70584'), findsOneWidget);
      expect(find.textContaining('Longitude: -47,27556'), findsOneWidget);
      expect(entries.memory.references, 0);
    },
  );

  testWidgets(
    'upload confirmado aparece no stream, mostra trecho e abre memória completa',
    (tester) async {
      await openDiary(tester);
      expect(find.text('Seu diário está de malas prontas'), findsOneWidget);
      final description = List.filled(
        30,
        'Uma memória longa para revisitar com carinho.',
      ).join(' ');
      await tester.runAsync(() async {
        final attempt = await entries.prepareUpload(
          uid: 'ana',
          placeName: 'Praia do Rosa',
          description: description,
          photo: await validPhoto(),
          location: const GeoPoint(-23.55, -46.63),
        );
        await attempt.save(onProgress: (_) {});
      });
      await tester.pumpAndSettle();
      await revealCard(tester);
      expect(find.text('Seu diário está de malas prontas'), findsNothing);
      expect(find.text(description), findsNothing);
      expect(entries.requestedUids, ['ana']);
      await tester.ensureVisible(find.text('Praia do Rosa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Praia do Rosa'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailsScreen), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == description,
        ),
        findsOneWidget,
      );
      expect(find.textContaining('outubro'), findsOneWidget);
      expect(find.textContaining('Latitude: -23,55000'), findsOneWidget);
      expect(find.textContaining('Longitude: -46,63000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lista é atualizada, ordenada e não exibe documentos de outra conta',
    (tester) async {
      await db.doc('users/ana/travel_entries/antiga').set({
        ...memory(id: 'antiga', name: 'Viagem antiga').toFirestore(),
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      });
      await db
          .doc('users/bia/travel_entries/segredo')
          .set(
            memory(
              uid: 'bia',
              id: 'segredo',
              name: 'Segredo de Bia',
            ).toFirestore(),
          );
      await openDiary(tester);
      await revealCard(tester);
      expect(
        tester
            .widget<TravelEntryCard>(find.byType(TravelEntryCard).first)
            .entry
            .id,
        'antiga',
      );
      await entries.createEntry(memory(id: 'recente', name: 'Nova descoberta'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TravelEntryCard>(find.byType(TravelEntryCard).first)
            .entry
            .id,
        'recente',
      );
      expect(find.text('Segredo de Bia', skipOffstage: false), findsNothing);
      await db.doc('users/ana/travel_entries/recente').update({
        'placeName': 'Descoberta atualizada',
      });
      await tester.pumpAndSettle();
      expect(find.text('Descoberta atualizada'), findsOneWidget);
    },
  );

  testWidgets(
    'carregamento, erro, nova tentativa e vazio são estados distintos',
    (tester) async {
      final controlled = ControlledEntries();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await controlled.events.close();
      });
      await tester.pumpWidget(
        shell(
          HomeScreen(
            user: UploadUser('ana'),
            auth: AuthService(auth: auth),
            entries: controlled,
            photos: NoGallery(),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Carregando suas memórias'), findsOneWidget);
      controlled.events.add([memory()]);
      await tester.pumpAndSettle();
      expect(find.byType(TravelEntryCard), findsOneWidget);
      controlled.events.addError(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TravelEntryCard), findsNothing);
      expect(find.textContaining('Verifique sua internet'), findsOneWidget);
      await tester.tap(find.text('Tentar novamente'));
      await tester.pump();
      expect(find.bySemanticsLabel('Carregando suas memórias'), findsOneWidget);
      expect(find.byType(TravelEntryCard), findsNothing);
      controlled.events.add([]);
      await tester.pumpAndSettle();
      expect(find.text('Seu diário está de malas prontas'), findsOneWidget);
      expect(controlled.uids, ['ana', 'ana']);
    },
  );

  testWidgets(
    'trocar de conta fecha detalhes, limpa dados e cancela assinatura anterior',
    (tester) async {
      await entries.createEntry(memory(name: 'Memória privada de Ana'));
      await openDiary(tester);
      await revealCard(tester);
      await tester.ensureVisible(find.text('Memória privada de Ana'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Memória privada de Ana'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailsScreen), findsOneWidget);
      auth.user = UploadUser('bia');
      auth.changes.add(auth.user);
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailsScreen), findsNothing);
      expect(
        find.text('Memória privada de Ana', skipOffstage: false),
        findsNothing,
      );
      expect(entries.requestedUids, ['ana', 'bia']);
      expect(entries.cancelled, greaterThanOrEqualTo(1));
      expect(entries.active, 1);
      expect(find.text('Seu diário está de malas prontas'), findsOneWidget);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsNothing);
      expect(find.byType(AuthScreen), findsOneWidget);
      expect(entries.active, 0);
    },
  );

  testWidgets('botão destacado abre novo registro e logout encerra a sessão', (
    tester,
  ) async {
    await openDiary(tester);
    await tester.tap(find.text('Nova memória'));
    await tester.pumpAndSettle();
    expect(find.byType(NewEntryScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(NewEntryScreen), findsNothing);
    await tester.tap(find.byTooltip('Sair da conta'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(entries.active, 0);
  });

  testWidgets(
    'detalhes suportam texto longo, data pendente e localização ausente no celular',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final longName = List.filled(12, 'Lugar especial').join(' ');
      final longMemory = List.filled(100, 'Uma memória completa.').join(' ');
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: shell(
            EntryDetailsScreen(
              entry: memory(
                name: longName,
                description: longMemory,
                pending: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sincronizando data…'), findsOneWidget);
      expect(find.text('Localização não informada.'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SelectableText && widget.data == longMemory,
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Localização não informada.'),
        350,
        maxScrolls: 100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('foto exibe carregamento e falha com ação para recarregar', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        const Scaffold(
          body: EntryPhoto(
            imageUrl: 'https://example.com/indisponivel.png',
            placeName: 'Praia',
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Carregando foto'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar a foto.'), findsOneWidget);
    await tester.tap(find.text('Recarregar foto'));
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível carregar a foto.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cartões mantêm leitura e navegação em celular estreito com texto ampliado',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final name = List.filled(8, 'Lugar especial').join(' ');
      await entries.createEntry(
        memory(
          name: name,
          description: List.filled(60, 'Uma lembrança para guardar.').join(' '),
        ),
      );
      await openDiary(tester, scale: 1.5);
      await revealCard(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(name));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
      expect(find.byType(EntryDetailsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
