import 'package:flutter_test/flutter_test.dart';
import 'package:naarea/domain/osm_ids.dart';

void main() {
  test(
    'id do local a partir do Photon (N/W/R) e do OSM (node/way/relation)',
    () {
      expect(osmPlaceId('N', 123), 'osm-n123');
      expect(osmPlaceId('W', 45), 'osm-w45');
      expect(osmPlaceId('R', 7), 'osm-r7');
      expect(osmPlaceId('node', '123'), 'osm-n123');
      expect(osmPlaceId('relation', '9'), 'osm-r9');
    },
  );

  test('tipo ou id inválido: null', () {
    expect(osmPlaceId('X', 1), isNull);
    expect(osmPlaceId(null, 1), isNull);
    expect(osmPlaceId('N', 0), isNull);
    expect(osmPlaceId('N', -3), isNull);
    expect(osmPlaceId('N', '12a'), isNull);
    expect(osmPlaceId('N', 1.5), isNull);
    // Zero à esquerda: outro texto para o mesmo id (duplicata) — rejeitado.
    expect(osmPlaceId('N', '0123'), isNull);
    expect(osmPlaceId('node', '00'), isNull);
  });

  test('padrão aceito pelas Rules e conversões', () {
    expect(isOsmPlaceId('osm-n123'), isTrue);
    expect(isOsmPlaceId('osm-x123'), isFalse);
    expect(isOsmPlaceId('osm-n'), isFalse);
    expect(isOsmPlaceId('osm-n0123'), isFalse);
    expect(isOsmPlaceId('osm-n0'), isFalse);
    expect(osmIdOfPlaceId('osm-n0123'), isNull);
    expect(isOsmPlaceId('mangai-natal'), isFalse);
    expect(osmIdOfPlaceId('osm-w45'), 'way/45');
    expect(osmIdOfPlaceId('mangai'), isNull);
    expect(placeIdOfOsmId('relation/7'), 'osm-r7');
    expect(placeIdOfOsmId('way'), isNull);
    expect(placeIdOfOsmId(null), isNull);
  });
}
