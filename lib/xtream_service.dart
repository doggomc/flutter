import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

class PortalException implements Exception {
  const PortalException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LiveFeed {
  const LiveFeed({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.iconUrl,
    required this.extension,
  });

  final String id;
  final String name;
  final String categoryId;
  final String iconUrl;
  final String extension;
}

/// Reads only the configured Formula 1 live category from the fixed portal.
/// Credentials are not persisted by the app at runtime.
class XtreamService {
  XtreamService({http.Client? client, String? username, String? password})
    : _client = client ?? http.Client(),
      _username = username ?? AppConfig.portalUsername,
      _password = password ?? AppConfig.portalPassword;

  final http.Client _client;
  final String _username;
  final String _password;
  bool _connected = false;

  bool get isConnected => _connected;

  String get _baseUrl =>
      AppConfig.portalServer.replaceFirst(RegExp(r'/+$'), '');

  Future<void> connect() async {
    if (_connected) return;
    if (_username.isEmpty || _password.isEmpty) {
      throw const PortalException(
        'Portal credentials were not included in this app build.',
      );
    }

    final root = await _request();
    if (root is! Map) {
      throw const PortalException(
        'The portal returned an unexpected login response.',
      );
    }

    final rootMap = Map<String, dynamic>.from(root);
    final rawInfo = rootMap['user_info'];
    final info = rawInfo is Map ? Map<String, dynamic>.from(rawInfo) : rootMap;
    final auth = info['auth']?.toString() ?? '';
    final status = (info['status']?.toString() ?? '').toLowerCase();

    if (auth == '0' ||
        const {'expired', 'disabled', 'banned', 'inactive'}.contains(status)) {
      throw const PortalException(
        'The portal rejected the configured account.',
      );
    }

    final accepted = auth == '1' || status == 'active' || rawInfo is Map;
    if (!accepted) {
      throw const PortalException(
        'The portal did not confirm the configured login.',
      );
    }

    _connected = true;
  }

  Future<List<LiveFeed>> loadFormulaOneFeeds() async {
    if (!_connected) await connect();

    final rawCategories = await _request(action: 'get_live_categories');
    if (rawCategories is! List) {
      throw const PortalException(
        'The portal did not return its live categories.',
      );
    }

    Map<String, dynamic>? targetCategory;
    final targetName = normalizeCategoryName(AppConfig.categoryName);
    for (final raw in rawCategories) {
      if (raw is! Map) continue;
      final category = Map<String, dynamic>.from(raw);
      final name = normalizeCategoryName(
        category['category_name']?.toString() ?? '',
      );
      if (name == targetName) {
        targetCategory = category;
        break;
      }
    }

    if (targetCategory == null) {
      throw const PortalException(
        'The configured Formula 1 category was not found on the portal.',
      );
    }

    final categoryId = targetCategory['category_id']?.toString() ?? '';
    if (categoryId.isEmpty) {
      throw const PortalException('The Formula 1 category has no valid ID.');
    }

    final rawStreams = await _request(
      action: 'get_live_streams',
      categoryId: categoryId,
    );
    if (rawStreams is! List) {
      throw const PortalException(
        'The portal did not return streams for this category.',
      );
    }

    final feeds = <LiveFeed>[];
    final seenIds = <String>{};
    for (final raw in rawStreams) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = item['stream_id']?.toString() ?? item['id']?.toString() ?? '';
      final itemCategory = item['category_id']?.toString() ?? categoryId;
      final name =
          item['name']?.toString() ??
          item['title']?.toString() ??
          'Untitled feed';
      if (id.isEmpty ||
          itemCategory != categoryId ||
          seenIds.contains(id) ||
          RegExp(r'#').allMatches(name).length >= 3) {
        continue;
      }
      seenIds.add(id);

      var extension = (item['container_extension']?.toString() ?? 'ts')
          .replaceFirst(RegExp(r'^\.'), '')
          .trim();
      if (!RegExp(r'^[A-Za-z0-9]{1,8}$').hasMatch(extension)) {
        extension = 'ts';
      }

      feeds.add(
        LiveFeed(
          id: id,
          name: name,
          categoryId: categoryId,
          iconUrl: item['stream_icon']?.toString() ?? '',
          extension: extension,
        ),
      );
    }

    return List.unmodifiable(feeds);
  }

  String streamUrl(LiveFeed feed) {
    if (!_connected) throw StateError('Connect to the portal first.');
    final user = Uri.encodeComponent(_username);
    final pass = Uri.encodeComponent(_password);
    final id = Uri.encodeComponent(feed.id);
    return '$_baseUrl/live/$user/$pass/$id.${feed.extension}';
  }

  static String normalizeCategoryName(String value) => value
      .replaceAll('\u00a0', ' ')
      .trim()
      .replaceAll(RegExp(r'\s*\|\s*'), ' | ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toUpperCase();

  Future<dynamic> _request({String? action, String? categoryId}) async {
    final query = <String, String>{
      'username': _username,
      'password': _password,
      if (action != null) 'action': action,
      if (categoryId != null) 'category_id': categoryId,
    };
    final uri = Uri.parse('$_baseUrl/player_api.php')
        .replace(queryParameters: query);

    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              'Accept': 'application/json,*/*',
              'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
            },
          )
          .timeout(const Duration(seconds: 18));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw PortalException(
          'The portal returned HTTP ${response.statusCode}.',
        );
      }

      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw const PortalException('The portal returned invalid JSON.');
      }
    } on TimeoutException {
      throw const PortalException('The portal request timed out. Try again.');
    } on PortalException {
      rethrow;
    } catch (_) {
      // Avoid echoing a request URL: Xtream URLs contain the configured login.
      throw const PortalException(
        'Could not reach the portal. Check the connection and retry.',
      );
    }
  }

  void dispose() => _client.close();
}
