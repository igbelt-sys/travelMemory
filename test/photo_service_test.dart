import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wanderlog/services/photo_service.dart';

import 'helpers/upload_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('recusa foto corrompida mesmo quando a assinatura diz PNG', () async {
    final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
    await expectLater(
      TravelPhoto.fromFile(XFile.fromData(bytes, name: 'foto.png')),
      throwsFormatException,
    );
  });
  test(
    'não permite burlar validação construindo TravelPhoto manualmente',
    () async {
      final bytes = (await validPhoto()).bytes;
      expect(
        () => TravelPhoto(
          bytes: bytes,
          contentType: 'image/jpeg',
          extension: 'jpg',
        ).validate(),
        throwsFormatException,
      );
      expect(
        () => TravelPhoto(
          bytes: bytes,
          contentType: 'image/png',
          extension: 'png',
        ).validate(),
        returnsNormally,
      );
    },
  );
  test('identifica PNG pelos bytes, mesmo com nome incorreto', () async {
    final bytes = (await validPhoto()).bytes;
    final photo = await TravelPhoto.fromFile(
      XFile.fromData(bytes, name: 'foto.jpg'),
    );
    expect(photo.contentType, 'image/png');
    expect(photo.extension, 'png');
  });
  test('rejeita arquivo com extensão de imagem e conteúdo inválido', () async {
    await expectLater(
      TravelPhoto.fromFile(
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'foto.png'),
      ),
      throwsFormatException,
    );
  });
  test('rejeita foto acima de 10 MB', () async {
    await expectLater(
      TravelPhoto.fromFile(
        XFile.fromData(Uint8List(TravelPhoto.maxBytes + 1), name: 'foto.jpg'),
      ),
      throwsFormatException,
    );
  });
}
