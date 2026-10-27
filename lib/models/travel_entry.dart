import 'package:cloud_firestore/cloud_firestore.dart';

class TravelEntry {
  const TravelEntry({
    required this.id,
    required this.placeName,
    required this.description,
    this.imageUrl,
    this.imagePath,
    this.isLocalPhoto = false,
    this.location,
    this.createdAt,
    this.hasPendingWrites = false,
  });

  static const maxPlaceNameLength = 120;
  static const maxDescriptionLength = 2000;

  final String id;
  final String placeName;
  final String description;
  final String? imageUrl;
  final String? imagePath;
  final bool isLocalPhoto;
  bool get hasPhoto => isLocalPhoto || imageUrl != null;
  final GeoPoint? location;
  final DateTime? createdAt;
  final bool hasPendingWrites;

  factory TravelEntry.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data();
    if (data == null) throw const FormatException('Registro não encontrado.');
    return TravelEntry.fromMap(
      snapshot.id,
      data,
      uid: snapshot.reference.parent.parent?.id,
      hasPendingWrites: snapshot.metadata.hasPendingWrites,
    );
  }

  factory TravelEntry.fromMap(
    String id,
    Map<String, dynamic> data, {
    String? uid,
    bool hasPendingWrites = false,
  }) {
    String readString(String field) {
      final value = data[field];
      if (value is! String) {
        throw FormatException('Campo inválido no registro: $field.');
      }
      return value;
    }

    final location = data['location'];
    final timestamp = data['createdAt'];
    final source = data['imageSource'];
    if (source != null && source != 'local' && source != 'storage') {
      throw const FormatException('Origem da foto inválida.');
    }
    if (source == 'storage' && data['imageUrl'] == null) {
      throw const FormatException('Foto do armazenamento sem URL.');
    }
    if (location != null && location is! GeoPoint) {
      throw const FormatException('Coordenadas inválidas no registro.');
    }
    if (timestamp != null && timestamp is! Timestamp) {
      throw const FormatException('Data inválida no registro.');
    }
    final entry = TravelEntry(
      id: id,
      placeName: readString('placeName'),
      description: readString('description'),
      imageUrl: data['imageUrl'] == null ? null : readString('imageUrl'),
      imagePath: data['imagePath'] == null ? null : readString('imagePath'),
      isLocalPhoto: source == 'local',
      location: location as GeoPoint?,
      createdAt: (timestamp as Timestamp?)?.toDate(),
      hasPendingWrites: hasPendingWrites,
    );
    entry.validate(uid: uid);
    return entry;
  }

  static String? validatePlaceName(String value) =>
      _validateText(value, 'Nome do local', maxPlaceNameLength);
  static String? validateDescription(String value) =>
      _validateText(value, 'Descrição', maxDescriptionLength);

  static String? _validateText(String value, String label, int limit) {
    if (value.trim().isEmpty) return '$label é obrigatório.';
    // A mesma contagem UTF-16 usada por String.size() nas regras do Firestore.
    if (value.length > limit) {
      return '$label deve ter até $limit caracteres.';
    }
    return null;
  }

  static void validateContent({
    required String placeName,
    required String description,
  }) {
    final error =
        validatePlaceName(placeName) ?? validateDescription(description);
    if (error != null) throw FormatException(error);
  }

  /// Compartilhado com as regras: um nome simples e extensão suportada.
  static bool isSupportedFileName(String value) =>
      value.length <= 200 &&
      RegExp(
        r'^[a-zA-Z0-9][a-zA-Z0-9._-]*\.(jpg|jpeg|png|webp)$',
      ).hasMatch(value);

  void validate({String? uid}) {
    validateContent(placeName: placeName, description: description);
    if (id.isEmpty || id.contains('/')) {
      throw const FormatException('Identificador do registro inválido.');
    }
    if (isLocalPhoto && (imageUrl != null || imagePath == null)) {
      throw const FormatException(
        'Foto local precisa de caminho e não possui URL de download.',
      );
    }
    if (!isLocalPhoto && (imageUrl == null) != (imagePath == null)) {
      throw const FormatException(
        'A URL e o caminho da foto devem ser informados juntos.',
      );
    }
    validateLocation(location);
    if (!hasPhoto) return;
    final url = imageUrl == null ? null : Uri.tryParse(imageUrl!);
    if (!isLocalPhoto &&
        (url == null ||
            url.scheme != 'https' ||
            url.host.isEmpty ||
            RegExp(r'\s').hasMatch(imageUrl!))) {
      throw const FormatException(
        'A URL da foto deve ser uma URL HTTPS válida.',
      );
    }
    final parts = imagePath!.split('/');
    if (parts.length != 5 ||
        parts[0] != 'users' ||
        parts[1].isEmpty ||
        (uid != null && parts[1] != uid) ||
        parts[2] != 'travel_entries' ||
        parts[3] != id ||
        !isSupportedFileName(parts[4])) {
      throw const FormatException(
        'O caminho da foto deve pertencer ao usuário e ao registro.',
      );
    }
  }

  static void validateLocation(GeoPoint? point) {
    if (point != null &&
        (!point.latitude.isFinite ||
            !point.longitude.isFinite ||
            point.latitude < -90 ||
            point.latitude > 90 ||
            point.longitude < -180 ||
            point.longitude > 180)) {
      throw const FormatException('Informe coordenadas válidas.');
    }
  }

  Map<String, dynamic> toFirestore() {
    validate();
    return {
      'placeName': placeName,
      'description': description,
      'imageUrl': imageUrl,
      'imagePath': imagePath,
      if (isLocalPhoto) 'imageSource': 'local',
      'location': location,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
