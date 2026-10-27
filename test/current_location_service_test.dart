import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wanderlog/services/current_location_service.dart';

import 'helpers/location_fake.dart';

void main() {
  late LocationBackend backend;
  late CurrentLocationService service;
  setUp(() {
    backend = LocationBackend();
    service = CurrentLocationService(
      platform: backend,
      web: false,
      target: TargetPlatform.android,
    );
  });

  Matcher failure(CurrentLocationFailure value) =>
      isA<CurrentLocationException>().having((e) => e.failure, 'falha', value);

  test(
    'não solicita acesso na construção; verifica serviço antes de pedir permissão',
    () async {
      expect(backend.calls, isEmpty);
      final first = service.capture();
      expect(identical(first, service.capture()), isTrue);
      expect(await first, const GeoPoint(-23.55, -46.63));
      expect(backend.calls, ['service', 'check', 'request', 'position']);
      expect(backend.settings!.timeLimit, const Duration(seconds: 15));
      expect(
        (backend.settings as AndroidSettings).forceLocationManager,
        isTrue,
      );
      expect(
        (backend.settings as AndroidSettings).foregroundNotificationConfig,
        isNull,
      );
    },
  );

  test('serviço desligado não pede permissão nem posição', () async {
    backend.enabled = false;
    await expectLater(
      service.capture(),
      throwsA(failure(CurrentLocationFailure.disabled)),
    );
    expect(backend.calls, ['service']);
  });

  test('permissão negada mantém captura opcional', () async {
    backend.requested = LocationPermission.denied;
    await expectLater(
      service.capture(),
      throwsA(failure(CurrentLocationFailure.denied)),
    );
    expect(backend.calls, isNot(contains('position')));
  });

  test('negação permanente não abre novamente o diálogo', () async {
    backend.permission = LocationPermission.deniedForever;
    await expectLater(
      service.capture(),
      throwsA(failure(CurrentLocationFailure.deniedForever)),
    );
    expect(backend.calls, ['service', 'check']);
    backend.permission = LocationPermission.denied;
    backend.requested = LocationPermission.deniedForever;
    await expectLater(
      service.capture(),
      throwsA(failure(CurrentLocationFailure.deniedForever)),
    );
  });

  test(
    'permissão existente no iOS não é solicitada de novo e não habilita segundo plano',
    () async {
      backend.permission = LocationPermission.whileInUse;
      service = CurrentLocationService(
        platform: backend,
        web: false,
        target: TargetPlatform.iOS,
      );
      await service.capture();
      expect(backend.calls, isNot(contains('request')));
      final settings = backend.settings as AppleSettings;
      expect(settings.allowBackgroundLocationUpdates, isFalse);
      expect(settings.showBackgroundLocationIndicator, isFalse);
      expect(settings.timeLimit, const Duration(seconds: 15));
    },
  );

  test(
    'tempo limite encerra a espera mesmo que a plataforma não responda',
    () async {
      backend.positionGate = Completer<Position>();
      service = CurrentLocationService(
        platform: backend,
        web: false,
        target: TargetPlatform.android,
        positionTimeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        service.capture(),
        throwsA(failure(CurrentLocationFailure.timeout)),
      );
      backend.positionGate!.complete(samplePosition());
    },
  );

  for (final error in [
    const PositionUpdateException('falha'),
    const PermissionDeniedException('negada'),
    UnsupportedError('indisponível'),
    MissingPluginException(),
  ]) {
    test(
      'classifica ${error.runtimeType} sem retornar coordenadas fictícias',
      () async {
        backend.permission = LocationPermission.whileInUse;
        backend.positionError = error;
        final expected =
            error is UnsupportedError || error is MissingPluginException
            ? CurrentLocationFailure.unsupported
            : error is PermissionDeniedException
            ? CurrentLocationFailure.denied
            : CurrentLocationFailure.unavailable;
        await expectLater(service.capture(), throwsA(failure(expected)));
      },
    );
  }

  test('plataforma não presente no projeto não acessa sensores', () async {
    service = CurrentLocationService(
      platform: backend,
      web: false,
      target: TargetPlatform.windows,
    );
    await expectLater(
      service.capture(),
      throwsA(failure(CurrentLocationFailure.unsupported)),
    );
    expect(backend.calls, isEmpty);
  });

  test(
    'Web solicita por getCurrentPosition com prazo e sem dupla captura',
    () async {
      service = CurrentLocationService(platform: backend, web: true);
      expect(await service.capture(), const GeoPoint(-23.55, -46.63));
      expect(backend.calls, ['service', 'check', 'position']);
      expect((backend.settings as WebSettings).maximumAge, Duration.zero);
      backend.permission = LocationPermission.unableToDetermine;
      expect(await service.capture(), const GeoPoint(-23.55, -46.63));
      expect(backend.calls.where((call) => call == 'request'), isEmpty);
    },
  );

  test(
    'coordenadas inválidas são recusadas e zero real é preservado',
    () async {
      backend.position = samplePosition(latitude: double.nan);
      await expectLater(
        service.capture(),
        throwsA(failure(CurrentLocationFailure.unavailable)),
      );
      backend.position = samplePosition(latitude: 91);
      await expectLater(
        service.capture(),
        throwsA(failure(CurrentLocationFailure.unavailable)),
      );
      backend.position = samplePosition(latitude: 0, longitude: 0);
      expect(await service.capture(), const GeoPoint(0, 0));
    },
  );

  test(
    'descartar a captura impede pedir permissão depois de sair da tela',
    () async {
      backend.serviceGate = Completer<bool>();
      final pending = service.capture();
      service.cancel();
      backend.serviceGate!.complete(true);
      await expectLater(
        pending,
        throwsA(failure(CurrentLocationFailure.cancelled)),
      );
      expect(backend.calls, ['service']);
    },
  );
}
