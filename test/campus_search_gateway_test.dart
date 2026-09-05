import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:navipet/data/campus_place.dart';
import 'package:navipet/data/campus_search_gateway.dart';
import 'package:navipet/data/navigation_models.dart';

Map<String, Object?> placeJson(int index) => {
  'id': '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  'type': 'building',
  'title': 'Building $index',
  'subtitle': 'B$index',
  'source': 'csulb',
  'navigation': {
    'outdoorDestination': {'latitude': 33.78, 'longitude': -118.11},
  },
};

void main() {
  test(
    'calls autocomplete with query, ten limit, and paired proximity',
    () async {
      late http.Request captured;
      final gateway = HttpCampusSearchGateway(
        baseUrl: 'https://campus.example/',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({'query': 'COB 140', 'results': []}),
            200,
          );
        }),
      );

      await gateway.autocomplete(
        'COB 140',
        limit: 50,
        proximity: const NavigationCoordinate(
          latitude: 33.7838,
          longitude: -118.1141,
        ),
      );

      expect(captured.url.path, '/autocomplete');
      expect(captured.url.queryParameters['q'], 'COB 140');
      expect(captured.url.queryParameters['limit'], '10');
      expect(captured.url.queryParameters['latitude'], '33.7838');
      expect(captured.url.queryParameters['longitude'], '-118.1141');
    },
  );

  test('defensively truncates autocomplete results to ten', () async {
    final gateway = HttpCampusSearchGateway(
      baseUrl: 'https://campus.example',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'query': 'building',
            'results': [
              for (var index = 0; index < 12; index++) placeJson(index),
            ],
          }),
          200,
        ),
      ),
    );

    expect(await gateway.autocomplete('building'), hasLength(10));
  });

  test('loads one local place by its stable ID', () async {
    late http.Request captured;
    final gateway = HttpCampusSearchGateway(
      baseUrl: 'https://campus.example',
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'place': placeJson(1)}), 200);
      }),
    );

    final place = await gateway.place('00000000-0000-4000-8000-000000000001');

    expect(captured.url.path, '/places/00000000-0000-4000-8000-000000000001');
    expect(place.id, '00000000-0000-4000-8000-000000000001');
  });

  test('parses standard API errors', () async {
    final gateway = HttpCampusSearchGateway(
      baseUrl: 'https://campus.example',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'UPSTREAM_ERROR', 'message': 'Search failed.'},
          }),
          502,
        ),
      ),
    );

    await expectLater(
      gateway.autocomplete('COB'),
      throwsA(
        isA<CampusSearchException>()
            .having(
              (error) => error.failure,
              'failure',
              CampusSearchFailure.api,
            )
            .having((error) => error.message, 'message', 'Search failed.'),
      ),
    );
  });

  test('classifies client failures as offline', () async {
    final gateway = HttpCampusSearchGateway(
      baseUrl: 'https://campus.example',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );

    await expectLater(
      gateway.autocomplete('COB'),
      throwsA(
        isA<CampusSearchException>().having(
          (error) => error.failure,
          'failure',
          CampusSearchFailure.offline,
        ),
      ),
    );
  });

  test('classifies malformed JSON as an API failure', () async {
    final gateway = HttpCampusSearchGateway(
      baseUrl: 'https://campus.example',
      client: MockClient((_) async => http.Response('not-json', 200)),
    );

    await expectLater(
      gateway.autocomplete('COB'),
      throwsA(isA<CampusSearchException>()),
    );
  });
}
