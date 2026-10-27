import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'location_support_stub.dart'
    if (dart.library.js_interop) 'location_support_web.dart'
    as support;

enum CurrentLocationFailure {
  denied,
  deniedForever,
  disabled,
  timeout,
  unavailable,
  unsupported,
  cancelled,
}

class CurrentLocationException implements Exception {
  const CurrentLocationException(this.failure);
  final CurrentLocationFailure failure;

  String get message => switch (failure) {
    CurrentLocationFailure.denied =>
      'Permissão de localização negada. Você pode tentar novamente, preencher as coordenadas ou continuar sem localização.',
    CurrentLocationFailure.deniedForever =>
      'A permissão de localização está bloqueada. Se desejar, habilite-a nas configurações do aparelho ou do site no navegador. Você também pode preencher manualmente ou continuar sem localização.',
    CurrentLocationFailure.disabled =>
      'O serviço de localização está desligado. Ative-o no aparelho ou informe as coordenadas manualmente. A localização é opcional.',
    CurrentLocationFailure.timeout =>
      'Não foi possível obter a posição no tempo limite. Tente novamente, preencha manualmente ou continue sem localização.',
    CurrentLocationFailure.unavailable =>
      'Não foi possível obter sua localização. Tente novamente, preencha manualmente ou continue sem localização.',
    CurrentLocationFailure.unsupported =>
      'A captura de localização não está disponível nesta plataforma ou navegador. Você pode preencher manualmente ou continuar sem localização.',
    CurrentLocationFailure.cancelled =>
      'Captura interrompida. Você pode tentar novamente ou informar as coordenadas manualmente.',
  };
}

/// Não acessa sensores nem permissões até [capture] ser chamado pelo botão.
class CurrentLocationService {
  CurrentLocationService({
    GeolocatorPlatform? platform,
    bool? web,
    TargetPlatform? target,
    this.positionTimeout = const Duration(seconds: 15),
  }) : _providedPlatform = platform,
       _web = web ?? kIsWeb,
       _target = target ?? defaultTargetPlatform;

  final GeolocatorPlatform? _providedPlatform;
  final bool _web;
  final TargetPlatform _target;
  final Duration positionTimeout;
  GeolocatorPlatform get _platform =>
      _providedPlatform ?? GeolocatorPlatform.instance;
  Future<GeoPoint>? _pending;
  int _generation = 0;

  Future<GeoPoint> capture() =>
      _pending ??= _capture(_generation).whenComplete(() => _pending = null);

  void cancel() => _generation++;

  void _checkActive(int generation) {
    if (generation != _generation) {
      throw const CurrentLocationException(CurrentLocationFailure.cancelled);
    }
  }

  LocationSettings get _settings {
    if (_web) {
      return WebSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: positionTimeout,
        maximumAge: Duration.zero,
      );
    }
    if (_target == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: positionTimeout,
        allowBackgroundLocationUpdates: false,
        showBackgroundLocationIndicator: false,
        pauseLocationUpdatesAutomatically: true,
      );
    }
    return AndroidSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: positionTimeout,
      forceLocationManager: true,
    );
  }

  Future<GeoPoint> _capture(int generation) async {
    try {
      if (!_web &&
          _target != TargetPlatform.android &&
          _target != TargetPlatform.iOS) {
        throw const CurrentLocationException(
          CurrentLocationFailure.unsupported,
        );
      }
      if (_web && !support.browserLocationSupported()) {
        throw const CurrentLocationException(
          CurrentLocationFailure.unsupported,
        );
      }
      final enabled = await _platform.isLocationServiceEnabled().timeout(
        const Duration(seconds: 5),
      );
      _checkActive(generation);
      if (!enabled) {
        throw const CurrentLocationException(CurrentLocationFailure.disabled);
      }
      var permission = await _platform.checkPermission().timeout(
        const Duration(seconds: 5),
      );
      _checkActive(generation);
      if (permission == LocationPermission.deniedForever) {
        throw const CurrentLocationException(
          CurrentLocationFailure.deniedForever,
        );
      }
      // Na Web getCurrentPosition já solicita a permissão. requestPermission
      // faria outra captura sem timeLimit na implementação do plugin.
      if (!_web && permission == LocationPermission.denied) {
        permission = await _platform.requestPermission();
        _checkActive(generation);
      }
      if (permission == LocationPermission.deniedForever) {
        throw const CurrentLocationException(
          CurrentLocationFailure.deniedForever,
        );
      }
      if (!_web &&
          permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        throw const CurrentLocationException(CurrentLocationFailure.denied);
      }
      final position = await _platform
          .getCurrentPosition(locationSettings: _settings)
          .timeout(positionTimeout);
      _checkActive(generation);
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude < -90 ||
          position.latitude > 90 ||
          position.longitude < -180 ||
          position.longitude > 180) {
        throw const CurrentLocationException(
          CurrentLocationFailure.unavailable,
        );
      }
      return GeoPoint(position.latitude, position.longitude);
    } on CurrentLocationException {
      rethrow;
    } on TimeoutException {
      throw const CurrentLocationException(CurrentLocationFailure.timeout);
    } on LocationServiceDisabledException {
      throw const CurrentLocationException(CurrentLocationFailure.disabled);
    } on PermissionDeniedException {
      var failure = CurrentLocationFailure.denied;
      try {
        if (await _platform.checkPermission().timeout(
              const Duration(seconds: 5),
            ) ==
            LocationPermission.deniedForever) {
          failure = CurrentLocationFailure.deniedForever;
        }
      } catch (_) {
        /* Preservar a recusa original. */
      }
      throw CurrentLocationException(failure);
    } on UnsupportedError {
      throw const CurrentLocationException(CurrentLocationFailure.unsupported);
    } on MissingPluginException {
      throw const CurrentLocationException(CurrentLocationFailure.unsupported);
    } catch (_) {
      throw const CurrentLocationException(CurrentLocationFailure.unavailable);
    }
  }
}
