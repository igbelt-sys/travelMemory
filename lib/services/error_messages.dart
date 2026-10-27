import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';

import 'travel_entry_service.dart';
import 'local_photo_service.dart';

String errorMessage(Object error) {
  if (error is TravelUploadException) return errorMessage(error.original);
  if (error is LocalPhotoException) return error.message;
  if (error is FirebaseException) {
    if (error.plugin == 'cloud_firestore' &&
        (error.code == 'permission-denied' || error.code == 'unauthorized')) {
      return 'Acesso não autorizado aos registros. Confira as permissões do banco de dados.';
    }
    if (error.plugin == 'firebase_storage') {
      final storageMessage = switch (error.code) {
        'permission-denied' || 'unauthorized' =>
          'O armazenamento não autorizou o acesso à foto. Confira as permissões do serviço de fotos.',
        'bucket-not-found' || 'no-default-bucket' || 'project-not-found' =>
          'O armazenamento de fotos não está configurado ou disponível para este aplicativo. O envio não foi concluído.',
        'object-not-found' =>
          'A foto não foi encontrada no armazenamento. Confira a disponibilidade do serviço e do arquivo.',
        'unknown' =>
          'Não foi possível concluir a operação com a foto. Confira a conexão e a configuração do armazenamento.',
        _ => null,
      };
      if (storageMessage != null) return storageMessage;
    }
    return switch (error.code) {
      'invalid-credential' || 'wrong-password' || 'user-not-found' =>
        'E-mail ou senha incorretos. Confira os dados e tente novamente.',
      'invalid-email' => 'Informe um e-mail válido.',
      'email-already-in-use' =>
        'Este e-mail já possui uma conta. Tente entrar.',
      'weak-password' => 'Escolha uma senha com pelo menos 6 caracteres.',
      'user-disabled' =>
        'Esta conta foi desativada. Entre em contato com a agência.',
      'too-many-requests' =>
        'Muitas tentativas. Aguarde um pouco e tente novamente.',
      'network-request-failed' ||
      'unavailable' ||
      'deadline-exceeded' ||
      'retry-limit-exceeded' =>
        'Não foi possível conectar. Verifique sua internet e tente novamente.',
      'permission-denied' || 'unauthorized' =>
        'Acesso não autorizado. Confira sua sessão e as regras do Firebase.',
      'unauthenticated' ||
      'user-token-expired' => 'Sua sessão expirou. Entre novamente.',
      'operation-not-allowed' =>
        'O acesso por e-mail e senha ainda não está habilitado.',
      'canceled' => 'O envio da foto foi cancelado. Tente novamente.',
      'quota-exceeded' =>
        'O armazenamento está indisponível no momento. Tente mais tarde.',
      _ => 'Não foi possível concluir. Tente novamente em instantes.',
    };
  }
  if (error is PlatformException) {
    return 'Não foi possível abrir a galeria. Confira a permissão de fotos nas configurações do aparelho.';
  }
  if (error is FormatException) return error.message;
  return 'Ocorreu um erro. Verifique sua conexão e tente novamente.';
}
