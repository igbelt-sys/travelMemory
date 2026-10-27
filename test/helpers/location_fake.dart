import 'dart:async';

import 'package:geolocator/geolocator.dart';

Position samplePosition({
  double latitude = -23.55,
  double longitude = -46.63,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026, 10, 27),
  accuracy: 30,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class LocationBackend extends GeolocatorPlatform {
  final calls = <String>[];
  bool enabled = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission requested = LocationPermission.whileInUse;
  Object? positionError;
  Position position = samplePosition();
  Completer<Position>? positionGate;
  Completer<bool>? serviceGate;
  LocationSettings? settings;

  @override
  Future<bool> isLocationServiceEnabled() async {
    calls.add('service');
    return serviceGate == null ? enabled : serviceGate!.future;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    calls.add('check');
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    calls.add('request');
    permission = requested;
    return permission;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    calls.add('position');
    settings = locationSettings;
    if (positionError != null) throw positionError!;
    return positionGate == null ? position : positionGate!.future;
  }
}
