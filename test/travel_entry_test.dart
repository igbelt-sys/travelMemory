import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlog/models/travel_entry.dart';
import 'package:wanderlog/services/entry_validation.dart';

void main() {
  test(
    'par de coordenadas distingue localização desconhecida de zero informado',
    () {
      expect(parseLocation('', '  '), isNull);
      expect(parseLocation('0', '0'), const GeoPoint(0, 0));
      expect(parseLocation('-23,55', '-46.63'), const GeoPoint(-23.55, -46.63));
      expect(parseLocation('-90', '180'), const GeoPoint(-90, 180));
      for (final pair in [
        ('', '0'),
        ('0', ''),
        ('91', '0'),
        ('0', '-181'),
        ('NaN', '0'),
      ]) {
        expect(() => parseLocation(pair.$1, pair.$2), throwsFormatException);
      }
    },
  );
  Map<String, dynamic> validData() => {
    'placeName': 'Serra',
    'description': 'Frio e café',
    'imageUrl': 'https://example.com/foto.jpg',
    'imagePath': 'users/ana/travel_entries/id/foto.jpg',
    'location': null,
    'createdAt': null,
  };

  test(
    'opcionais ausentes e timestamp pendente são nulos, sem inventar data',
    () {
      final data = validData()
        ..remove('createdAt')
        ..remove('location');
      final entry = TravelEntry.fromMap('id', data, hasPendingWrites: true);
      expect(entry.createdAt, isNull);
      expect(entry.location, isNull);
      expect(entry.hasPendingWrites, isTrue);
      expect(entry.toFirestore(), isNot(contains('hasPendingWrites')));
      expect(entry.toFirestore()['location'], isNull);
    },
  );

  test(
    'tipos inválidos e campos obrigatórios ausentes geram FormatException',
    () {
      for (final field in [
        'placeName',
        'description',
        'imageUrl',
        'imagePath',
      ]) {
        expect(
          () => TravelEntry.fromMap('id', validData()..remove(field)),
          throwsFormatException,
        );
        expect(
          () => TravelEntry.fromMap('id', validData()..[field] = 42),
          throwsFormatException,
        );
      }
      for (final change in [
        {'location': '1,2'},
        {'createdAt': 'hoje'},
        {'createdAt': DateTime.now()},
      ]) {
        expect(
          () => TravelEntry.fromMap('id', {...validData(), ...change}),
          throwsFormatException,
        );
      }
    },
  );

  test('sem foto usa par null e mantém validação de pares e ID', () {
    final entry = TravelEntry.fromMap('id', {
      ...validData(),
      'imageUrl': null,
      'imagePath': null,
    });
    expect(entry.hasPhoto, isFalse);
    expect(entry.toFirestore()['imageUrl'], isNull);
    expect(entry.toFirestore()['imagePath'], isNull);
    expect(
      () => TravelEntry.fromMap('', {
        ...validData(),
        'imageUrl': null,
        'imagePath': null,
      }),
      throwsFormatException,
    );
    expect(
      () => TravelEntry.fromMap('id', {...validData(), 'imageUrl': null}),
      throwsFormatException,
    );
  });

  test('limites 120 e 2000 são validados também fora do formulário', () {
    expect(TravelEntry.validatePlaceName('x' * 120), isNull);
    expect(TravelEntry.validateDescription('x' * 2000), isNull);
    expect(TravelEntry.validatePlaceName('é' * 120), isNull);
    expect(TravelEntry.validatePlaceName('🌍' * 60), isNull);
    expect(TravelEntry.validatePlaceName('🌍' * 61), isNotNull);
    expect(TravelEntry.validateDescription('🌍' * 1000), isNull);
    expect(TravelEntry.validateDescription('🌍' * 1001), isNotNull);
    for (final change in [
      {'placeName': 'x' * 121},
      {'placeName': ' \n '},
      {'description': 'x' * 2001},
      {'description': ''},
    ]) {
      expect(
        () => TravelEntry.fromMap('id', {...validData(), ...change}),
        throwsFormatException,
      );
    }
  });

  test('caminho exige mesmo dono, mesmo registro e arquivo suportado', () {
    for (final path in [
      'users/bia/travel_entries/id/foto.jpg',
      'users/ana/travel_entries/outro/foto.jpg',
      'users/ana/travel_entries/id/pasta/foto.jpg',
      'users/ana/travel_entries/id/foto.svg',
    ]) {
      expect(
        () => TravelEntry.fromMap(
          'id',
          validData()..['imagePath'] = path,
          uid: 'ana',
        ),
        throwsFormatException,
      );
    }
    expect(
      () => TravelEntry.fromMap('id', validData(), uid: 'ana'),
      returnsNormally,
    );
  });

  test('URL vazia, insegura ou malformada é recusada', () {
    for (final url in [
      '',
      'http://example.com/foto.jpg',
      'https://',
      'https://example.com/foto com espaço.jpg',
    ]) {
      expect(
        () => TravelEntry.fromMap('id', validData()..['imageUrl'] = url),
        throwsFormatException,
      );
    }
  });

  test('serializa o contrato com GeoPoint e timestamp do servidor', () {
    const entry = TravelEntry(
      id: 'viagem',
      placeName: 'Praia do Rosa',
      description: 'Um dia de sol',
      imageUrl: 'https://example.com/photo.jpg',
      imagePath: 'users/ana/travel_entries/viagem/memoria.jpg',
      location: GeoPoint(-28.12, -48.64),
    );
    final data = entry.toFirestore();
    expect(
      data.keys,
      unorderedEquals([
        'placeName',
        'description',
        'imageUrl',
        'imagePath',
        'location',
        'createdAt',
      ]),
    );
    expect(data['location'], const GeoPoint(-28.12, -48.64));
    expect(data['createdAt'], isA<FieldValue>());
  });

  test('lê registros sem coordenadas e com timestamp pendente', () {
    final data = <String, dynamic>{
      'placeName': 'Serra',
      'description': 'Frio e café',
      'imageUrl': 'https://example.com/photo.jpg',
      'imagePath': 'users/ana/travel_entries/id/memoria.jpg',
      'location': null,
      'createdAt': null,
    };
    final entry = TravelEntry.fromMap('id', data);
    expect(entry.location, isNull);
    expect(entry.createdAt, isNull);
    final date = DateTime.utc(2026, 10, 27);
    data['createdAt'] = Timestamp.fromDate(date);
    expect(TravelEntry.fromMap('id', data).createdAt, date.toLocal());
  });

  test(
    'valida par opcional, vírgula decimal, limites e valores não finitos',
    () {
      expect(parseCoordinate(' -23,55 '), -23.55);
      expect(validateCoordinate('', latitude: true, otherValue: ''), isNull);
      expect(
        validateCoordinate('', latitude: true, otherValue: '10'),
        isNotNull,
      );
      expect(
        validateCoordinate('-90', latitude: true, otherValue: '180'),
        isNull,
      );
      expect(
        validateCoordinate('180', latitude: false, otherValue: '-90'),
        isNull,
      );
      for (final invalid in ['90.01', '-91', 'NaN', 'Infinity', 'texto']) {
        expect(
          validateCoordinate(invalid, latitude: true, otherValue: '0'),
          isNotNull,
        );
      }
      expect(
        validateCoordinate('-180.1', latitude: false, otherValue: '0'),
        isNotNull,
      );
    },
  );
}
