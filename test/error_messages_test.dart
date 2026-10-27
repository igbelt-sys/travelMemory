import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlog/services/error_messages.dart';
import 'package:wanderlog/services/travel_entry_service.dart';

void main() {
  test('permissão do banco não é apresentada como sessão expirada', () {
    final message = errorMessage(
      FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
    );
    expect(message, contains('registros'));
    expect(message, contains('permissões do banco'));
    expect(message, isNot(contains('sessão')));
  });

  for (final code in [
    'bucket-not-found',
    'no-default-bucket',
    'project-not-found',
  ]) {
    test('Storage indisponível ($code) informa configuração pendente', () {
      final message = errorMessage(
        TravelUploadException(
          FirebaseException(plugin: 'firebase_storage', code: code),
        ),
      );
      expect(message, contains('armazenamento de fotos'));
      expect(message, contains('envio não foi concluído'));
    });
  }

  test('acesso negado e objeto ausente identificam o serviço de fotos', () {
    for (final code in ['unauthorized', 'object-not-found', 'unknown']) {
      final message = errorMessage(
        FirebaseException(plugin: 'firebase_storage', code: code),
      );
      expect(message, contains('foto'));
      expect(message, contains('armazenamento'));
      expect(message, isNot(contains('sessão')));
    }
  });

  test('sessão realmente expirada continua solicitando novo login', () {
    expect(
      errorMessage(FirebaseAuthException(code: 'user-token-expired')),
      contains('Entre novamente'),
    );
  });
}
