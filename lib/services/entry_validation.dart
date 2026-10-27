import 'package:cloud_firestore/cloud_firestore.dart';

double? parseCoordinate(String value) =>
    double.tryParse(value.trim().replaceAll(',', '.'));

String? validateCoordinate(
  String value, {
  required bool latitude,
  required String otherValue,
}) {
  if (value.trim().isEmpty) {
    return otherValue.trim().isEmpty ? null : 'Informe as duas coordenadas.';
  }
  final number = parseCoordinate(value);
  final limit = latitude ? 90 : 180;
  if (number == null || !number.isFinite || number < -limit || number > limit) {
    return 'Use um número entre -$limit e $limit.';
  }
  return null;
}

/// Valida também fora do ciclo de vida dos campos do formulário.
GeoPoint? parseLocation(String latitude, String longitude) {
  final error =
      validateCoordinate(latitude, latitude: true, otherValue: longitude) ??
      validateCoordinate(longitude, latitude: false, otherValue: latitude);
  if (error != null) throw FormatException(error);
  if (latitude.trim().isEmpty && longitude.trim().isEmpty) return null;
  return GeoPoint(parseCoordinate(latitude)!, parseCoordinate(longitude)!);
}
