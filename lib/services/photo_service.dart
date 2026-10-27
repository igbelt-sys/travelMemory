import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

class TravelPhoto {
  const TravelPhoto({
    required this.bytes,
    required this.contentType,
    required this.extension,
  });
  static const maxBytes = 10 * 1024 * 1024;
  final Uint8List bytes;
  final String contentType;
  final String extension;

  void validate() {
    final expectedExtension = switch (lookupMimeType('', headerBytes: bytes)) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => null,
    };
    if (bytes.isEmpty ||
        bytes.length > maxBytes ||
        expectedExtension == null ||
        extension != expectedExtension ||
        contentType !=
            (extension == 'jpg' ? 'image/jpeg' : 'image/$extension')) {
      throw const FormatException(
        'Escolha uma foto JPG, PNG ou WebP de até 10 MB.',
      );
    }
  }

  Future<void> validateDecoded() async {
    validate();
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 1920,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } catch (_) {
      throw const FormatException(
        'Esta foto não pôde ser aberta. Escolha uma imagem JPG, PNG ou WebP válida.',
      );
    } finally {
      codec?.dispose();
    }
  }

  static Future<TravelPhoto> fromFile(XFile file) async {
    if (await file.length() > maxBytes) {
      throw const FormatException('Escolha uma foto de até 10 MB.');
    }
    final bytes = await file.readAsBytes();
    final type = lookupMimeType('', headerBytes: bytes);
    final extension = switch (type) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => null,
    };
    if (extension == null || bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException(
        'Escolha uma foto JPG, PNG ou WebP de até 10 MB.',
      );
    }
    final photo = TravelPhoto(
      bytes: bytes,
      contentType: type!,
      extension: extension,
    );
    await photo.validateDecoded();
    return photo;
  }
}

class PhotoService {
  final ImagePicker _picker = ImagePicker();

  Future<TravelPhoto?> pick() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return file == null ? null : TravelPhoto.fromFile(file);
  }

  Future<TravelPhoto?> recoverLostPhoto() async {
    final response = await _picker.retrieveLostData();
    if (response.exception != null) throw response.exception!;
    final files = response.files;
    return files == null || files.isEmpty
        ? null
        : TravelPhoto.fromFile(files.first);
  }
}
