import 'dart:async';
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlog/screens/new_entry_screen.dart';
import 'package:wanderlog/services/photo_service.dart';
import 'package:wanderlog/services/local_photo_service.dart';
import 'package:wanderlog/services/current_location_service.dart';
import 'package:geolocator/geolocator.dart';

import 'app_test.dart' show shell;
import 'helpers/upload_fakes.dart';
import 'helpers/location_fake.dart';

class Gallery extends PhotoService {
  int calls = 0;
  @override
  Future<TravelPhoto?> pick() async {
    calls++;
    return null;
  }
}

class MemoryLocalPhotos extends LocalPhotoService {
  final files = <String, Uint8List>{};
  @override
  Future<void> write({
    required String uid,
    required String entryId,
    required String relativePath,
    required TravelPhoto photo,
  }) async {
    files[relativePath] = photo.bytes;
  }

  @override
  Future<Uint8List?> read({
    required String uid,
    required String entryId,
    required String relativePath,
  }) async => files[relativePath];
  @override
  Future<void> remove({
    required String uid,
    required String entryId,
    required String relativePath,
  }) async {
    files.remove(relativePath);
  }
}

Future<void> flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 60)),
  );
  await tester.pump();
}

void main() {
  Finder field(String name) => find.byKey(ValueKey(name));
  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    bool up = false,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      up ? -250 : 250,
      scrollable: find.byType(Scrollable).first,
    );
  }

  late UploadAuth auth;
  late MemoryStorage storage;
  late UploadService service;
  setUp(() {
    final db = FakeFirebaseFirestore();
    auth = UploadAuth();
    storage = MemoryStorage(db);
    service = UploadService(db, auth, storage);
  });
  tearDown(() async {
    await auth.changes.close();
    await storage.task?.progress.close();
  });

  Future<void> open(
    WidgetTester tester, {
    Gallery? gallery,
    CurrentLocationService? locationService,
    bool withoutPhoto = false,
    bool useLocalPhotos = false,
  }) async {
    final photo = (await tester.runAsync(validPhoto))!;
    await tester.pumpWidget(
      shell(
        Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => NewEntryScreen(
                      uid: 'ana',
                      entries: service,
                      initialPhoto: withoutPhoto ? null : photo,
                      photos: gallery,
                      locationService: locationService,
                      localPhotos: useLocalPhotos,
                    ),
                  ),
                );
                if (saved == true && context.mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Memória confirmada')),
                  );
                }
              },
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await reveal(tester, field('placeName'));
    await tester.enterText(field('placeName'), 'Praia');
    await reveal(tester, field('description'));
    await tester.enterText(field('description'), 'Um dia especial');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Salvar'));
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await flush(tester);
  }

  testWidgets('salva foto local pelo formulário sem acessar Storage', (
    tester,
  ) async {
    final photos = MemoryLocalPhotos();
    final db = FakeFirebaseFirestore();
    storage = MemoryStorage(db);
    service = UploadService(db, auth, storage, localPhotos: photos);
    await open(tester, useLocalPhotos: true);
    await save(tester);
    await tester.runAsync(
      () => service.documentWritten.future.timeout(const Duration(seconds: 3)),
    );
    await flush(tester);
    await tester.pumpAndSettle();
    expect(find.text('Memória confirmada'), findsOneWidget);
    expect(service.written!.isLocalPhoto, isTrue);
    expect(service.written!.imageUrl, isNull);
    expect(photos.files.containsKey(service.written!.imagePath), isTrue);
    expect(storage.references, 0);
  });

  testWidgets('salva memória sem foto com coordenadas manuais e sem Storage', (
    tester,
  ) async {
    await open(tester, withoutPhoto: true);
    expect(find.byType(Image), findsNothing);
    await reveal(tester, field('latitude'));
    await tester.enterText(field('latitude'), '-22,70584');
    await reveal(tester, field('longitude'));
    await tester.enterText(field('longitude'), '-47.27556');
    await save(tester);
    await flush(tester);
    await tester.pumpAndSettle();
    expect(find.text('Memória confirmada'), findsOneWidget);
    expect(service.written!.hasPhoto, isFalse);
    expect(service.written!.location!.latitude, -22.70584);
    expect(service.written!.location!.longitude, -47.27556);
    expect(storage.references, 0);
  });

  testWidgets('localização capturada salva sem foto e sem Storage', (
    tester,
  ) async {
    final backend = LocationBackend();
    await open(
      tester,
      withoutPhoto: true,
      locationService: CurrentLocationService(
        platform: backend,
        web: false,
        target: TargetPlatform.android,
      ),
    );
    await reveal(tester, find.byKey(const ValueKey('useCurrentLocation')));
    await tester.tap(find.byKey(const ValueKey('useCurrentLocation')));
    await tester.pumpAndSettle();
    await save(tester);
    await flush(tester);
    await tester.pumpAndSettle();
    expect(find.text('Memória confirmada'), findsOneWidget);
    expect(service.written!.location!.latitude, -23.55);
    expect(service.written!.location!.longitude, -46.63);
    expect(storage.references, 0);
  });

  testWidgets('cancelar a galeria preserva a foto e não exibe erro', (
    tester,
  ) async {
    final gallery = Gallery();
    await open(tester, gallery: gallery);
    await reveal(tester, find.text('Trocar foto'), up: true);
    await tester.tap(find.text('Trocar foto'));
    await tester.pumpAndSettle();
    expect(gallery.calls, 1);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('Não foi possível'), findsNothing);
    await reveal(tester, field('placeName'));
    expect(
      tester.widget<TextFormField>(field('placeName')).controller!.text,
      'Praia',
    );
  });

  testWidgets(
    'pede localização somente após o botão e salva o GeoPoint capturado',
    (tester) async {
      final backend = LocationBackend();
      await open(
        tester,
        locationService: CurrentLocationService(
          platform: backend,
          web: false,
          target: TargetPlatform.android,
        ),
      );
      expect(backend.calls, isEmpty);
      await reveal(tester, find.byKey(const ValueKey('useCurrentLocation')));
      await tester.tap(find.byKey(const ValueKey('useCurrentLocation')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('latitude')).controller!.text,
        '-23,55',
      );
      expect(
        tester.widget<TextFormField>(field('longitude')).controller!.text,
        '-46,63',
      );
      expect(backend.calls.where((call) => call == 'request'), hasLength(1));
      await save(tester);
      await flush(tester);
      await tester.pumpAndSettle();
      expect(service.written!.location!.latitude, -23.55);
      expect(service.written!.location!.longitude, -46.63);
    },
  );

  testWidgets(
    'recusa de localização mantém coordenadas manuais e permite salvar',
    (tester) async {
      final backend = LocationBackend()..requested = LocationPermission.denied;
      await open(
        tester,
        locationService: CurrentLocationService(
          platform: backend,
          web: false,
          target: TargetPlatform.android,
        ),
      );
      await reveal(tester, field('latitude'));
      await tester.enterText(field('latitude'), '-15,5');
      await tester.enterText(field('longitude'), '47,2');
      await reveal(
        tester,
        find.byKey(const ValueKey('useCurrentLocation')),
        up: true,
      );
      await tester.tap(find.byKey(const ValueKey('useCurrentLocation')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Permissão de localização negada'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextFormField>(field('latitude')).controller!.text,
        '-15,5',
      );
      expect(
        tester.widget<TextFormField>(field('longitude')).controller!.text,
        '47,2',
      );
      await save(tester);
      await flush(tester);
      await tester.pumpAndSettle();
      expect(service.written!.location!.latitude, -15.5);
      expect(service.written!.location!.longitude, 47.2);
    },
  );

  testWidgets('pode salvar sem localização depois de uma falha de captura', (
    tester,
  ) async {
    final backend = LocationBackend()..enabled = false;
    await open(
      tester,
      locationService: CurrentLocationService(
        platform: backend,
        web: false,
        target: TargetPlatform.android,
      ),
    );
    await reveal(tester, find.byKey(const ValueKey('useCurrentLocation')));
    await tester.tap(find.byKey(const ValueKey('useCurrentLocation')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('serviço de localização está desligado'),
      findsOneWidget,
    );
    await save(tester);
    await flush(tester);
    await tester.pumpAndSettle();
    expect(service.written!.location, isNull);
  });

  testWidgets(
    'captura pendente bloqueia repetição e ignora resultado após sair',
    (tester) async {
      final backend = LocationBackend()..positionGate = Completer<Position>();
      await open(
        tester,
        locationService: CurrentLocationService(
          platform: backend,
          web: false,
          target: TargetPlatform.android,
        ),
      );
      await reveal(tester, find.byKey(const ValueKey('useCurrentLocation')));
      await tester.tap(find.byKey(const ValueKey('useCurrentLocation')));
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('useCurrentLocation')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('saveEntry')))
            .onPressed,
        isNull,
      );
      expect(tester.widget<TextFormField>(field('latitude')).enabled, isFalse);
      await tester.pumpWidget(const SizedBox());
      backend.positionGate!.complete(samplePosition());
      await tester.pump();
      expect(service.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('timeout libera o preenchimento manual e ignora posição tardia', (
    tester,
  ) async {
    final backend = LocationBackend()..positionGate = Completer<Position>();
    await open(
      tester,
      locationService: CurrentLocationService(
        platform: backend,
        web: false,
        target: TargetPlatform.android,
        positionTimeout: const Duration(milliseconds: 10),
      ),
    );
    await reveal(tester, find.byKey(const ValueKey('useCurrentLocation')));
    await tester.tap(find.byKey(const ValueKey('useCurrentLocation')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 11));
    await tester.pumpAndSettle();
    expect(find.textContaining('tempo limite'), findsOneWidget);
    expect(tester.widget<TextFormField>(field('latitude')).enabled, isTrue);
    await tester.enterText(field('latitude'), '-10');
    await tester.enterText(field('longitude'), '20');
    expect(find.textContaining('tempo limite'), findsNothing);
    backend.positionGate!.complete(samplePosition());
    await tester.pump();
    expect(
      tester.widget<TextFormField>(field('latitude')).controller!.text,
      '-10',
    );
    await save(tester);
    await flush(tester);
    await tester.pumpAndSettle();
    expect(service.written!.location!.latitude, -10);
    expect(service.written!.location!.longitude, 20);
  });

  testWidgets(
    'exibe erro original enquanto aguarda limpeza e informa a falha separadamente',
    (tester) async {
      service.writeError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      storage.deleteError = FirebaseException(
        plugin: 'firebase_storage',
        code: 'unavailable',
      );
      final gate = storage.deleteGate = Completer<void>();
      await open(tester);
      try {
        await save(tester);
        expect(find.textContaining('Acesso não autorizado'), findsOneWidget);
        expect(find.text('Removendo a foto após a falha…'), findsOneWidget);
        expect(find.text('Cancelar envio'), findsNothing);
      } finally {
        gate.complete();
        await flush(tester);
      }
      expect(find.textContaining('Acesso não autorizado'), findsOneWidget);
      expect(
        find.textContaining('Também não foi possível remover'),
        findsOneWidget,
      );
      expect(find.text('Memória confirmada'), findsNothing);
    },
  );

  testWidgets(
    'bloqueia controles e confirma sucesso somente depois da gravação',
    (tester) async {
      service.writeGate = Completer<void>();
      await open(tester);
      await save(tester);
      expect(service.writes, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Memória confirmada'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('saveEntry')))
            .onPressed,
        isNull,
      );
      for (final field in tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      )) {
        expect(field.enabled, isFalse);
      }
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('Nova memória'), findsOneWidget);
      expect(storage.puts, 1);
      service.writeGate!.complete();
      await flush(tester);
      await tester.pumpAndSettle();
      expect(find.text('Nova memória'), findsNothing);
      expect(find.text('Memória confirmada'), findsOneWidget);
      expect(service.written!.location, isNull);
    },
  );

  testWidgets(
    'erro de gravação e limpeza preserva formulário, foto e causa original',
    (tester) async {
      service.writeError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      );
      storage.deleteError = FirebaseException(
        plugin: 'firebase_storage',
        code: 'unavailable',
      );
      await open(tester);
      await save(tester);
      await flush(tester);
      expect(find.textContaining('Acesso não autorizado'), findsOneWidget);
      expect(
        find.textContaining('Também não foi possível remover'),
        findsOneWidget,
      );
      expect(find.text('Memória confirmada'), findsNothing);
      await reveal(tester, field('placeName'), up: true);
      expect(
        tester.widget<TextFormField>(field('placeName')).controller!.text,
        'Praia',
      );
      await reveal(tester, find.text('Trocar foto'), up: true);
      expect(find.byType(Image), findsOneWidget);
      service.writeError = null;
      storage.deleteError = null;
      await save(tester);
      await flush(tester);
      await tester.pumpAndSettle();
      expect(storage.puts, 1);
      expect(find.text('Memória confirmada'), findsOneWidget);
    },
  );

  testWidgets('exige par de coordenadas e aceita zero somente quando informado', (
    tester,
  ) async {
    await open(tester);
    await reveal(tester, field('latitude'));
    await tester.enterText(field('latitude'), '0');
    await save(tester);
    expect(storage.puts, 0);
    expect(find.text('Informe as duas coordenadas.'), findsOneWidget);
    await reveal(tester, field('longitude'), up: true);
    await tester.enterText(field('longitude'), '0');
    await save(tester);
    // Decodificação e encerramento das assinaturas precisam de execução real
    // entre frames. Aguarde o resultado na interface, não só a escrita do fake.
    for (
      var i = 0;
      i < 50 && find.text('Memória confirmada').evaluate().isEmpty;
      i++
    ) {
      await flush(tester);
    }
    expect(service.documentWritten.isCompleted, isTrue);
    await tester.pumpAndSettle();
      expect(find.text('Memória confirmada'), findsOneWidget);
    expect(service.written!.location!.latitude, 0);
    expect(service.written!.location!.longitude, 0);
  });

  testWidgets(
    'descartar rota durante envio cancela sem atualizar widget removido',
    (tester) async {
      storage.autoComplete = false;
      await open(tester);
      await save(tester);
      expect(storage.task, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
      expect(storage.task!.done.isCompleted, isTrue);
      expect(service.writes, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
