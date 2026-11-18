import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:freef1_cockpit/xtream_service.dart';

void main() {
  test(
    'requests and returns only streams from the exact F1 category',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        final action = request.url.queryParameters['action'];

        if (action == null) {
          return _jsonResponse({
            'user_info': {'auth': 1, 'status': 'Active'},
          });
        }
        if (action == 'get_live_categories') {
          return _jsonResponse([
            {'category_id': '42', 'category_name': 'LIVE | FORMULA 1 F1'},
            {'category_id': '43', 'category_name': 'LIVE | FORMULA 1 F1 HD'},
          ]);
        }
        if (action == 'get_live_streams') {
          return _jsonResponse([
            {
              'stream_id': '101',
              'category_id': '42',
              'name': 'F1 Main Feed',
              'container_extension': 'm3u8',
            },
            {
              'stream_id': '202',
              'category_id': '43',
              'name': 'Other category',
              'container_extension': 'ts',
            },
            {
              'stream_id': '303',
              'category_id': '42',
              'name': 'Unsafe extension',
              'container_extension': '../ts',
            },
          ]);
        }
        return http.Response('{}', 404);
      });
      final service = XtreamService(
        client: client,
        username: 'test-user',
        password: 'test-password',
      );
      addTearDown(service.dispose);

      await service.connect();
      final feeds = await service.loadFormulaOneFeeds();

      expect(feeds.map((feed) => feed.id), ['101', '303']);
      expect(feeds.map((feed) => feed.categoryId), everyElement('42'));
      expect(feeds.first.extension, 'm3u8');
      expect(feeds.last.extension, 'ts');
      expect(requests, hasLength(3));
      expect(requests[2].queryParameters['category_id'], '42');
      expect(requests[0].queryParameters['username'], 'test-user');
      expect(requests[0].queryParameters['password'], 'test-password');
      expect(
        service.streamUrl(feeds.first),
        'http://lordstreams.live:80/live/test-user/test-password/101.m3u8',
      );
    },
  );

  test('rejects a portal login explicitly marked as unauthenticated', () async {
    final client = MockClient((request) async {
      return _jsonResponse({
        'user_info': {'auth': 0, 'status': 'Disabled'},
      });
    });
    final service = XtreamService(
      client: client,
      username: 'test-user',
      password: 'test-password',
    );
    addTearDown(service.dispose);

    await expectLater(service.connect(), throwsA(isA<PortalException>()));
    expect(service.isConnected, isFalse);
  });

  test('normalizes spacing around the category separator', () {
    expect(
      XtreamService.normalizeCategoryName('  live  |  formula 1 f1  '),
      'LIVE | FORMULA 1 F1',
    );
  });
}

http.Response _jsonResponse(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json'},
);
