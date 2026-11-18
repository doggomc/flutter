import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class PortalCategory {
  const PortalCategory({required this.id, required this.name});

  final String id;
  final String name;
}

class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.icon,
    required this.extension,
  });

  final String id;
  final String name;
  final String categoryId;
  final String icon;
  final String extension;
}

class PortalAccount {
  const PortalAccount({
    required this.username,
    required this.status,
    required this.expiry,
  });

  final String username;
  final String status;
  final String expiry;
}

class ParsedPortalCombo {
  const ParsedPortalCombo({
    required this.server,
    required this.username,
    required this.password,
  });

  final String server;
  final String username;
  final String password;

  static ParsedPortalCombo? tryParse(String raw) {
    final match = RegExp(
      r'^(https?)://([^/:?#]+)(?::(\d{1,5}))?:([^:/?#]+):([^?#]+)$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final scheme = match.group(1)!.toLowerCase();
    final host = match.group(2)!;
    final port = match.group(3);
    return ParsedPortalCombo(
      server: '$scheme://$host${port == null ? '' : ':$port'}',
      username: match.group(4)!.trim(),
      password: match.group(5)!.trim(),
    );
  }
}

class XtreamService {
  XtreamService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  _PortalCredentials? _credentials;

  bool get isConnected => _credentials != null;

  Future<PortalAccount> connect({
    required String server,
    required String username,
    required String password,
  }) async {
    final credentials = _PortalCredentials(
      baseUrl: _normalizeBase(server),
      username: username.trim(),
      password: password.trim(),
    );
    if (credentials.username.isEmpty || credentials.password.isEmpty) {
      throw Exception('Enter the portal username and password.');
    }

    // Keep credentials in memory only. Do not persist them in preferences or files.
    _credentials = credentials;
    try {
      final root = await _request();
      if (root is! Map) throw Exception('Portal returned an unexpected login response.');
      final rootMap = Map<String, dynamic>.from(root);
      final rawInfo = rootMap['user_info'];
      final info = rawInfo is Map
          ? Map<String, dynamic>.from(rawInfo)
          : rootMap;
      final auth = info['auth']?.toString() ?? '';
      final status = (info['status']?.toString() ?? '').toLowerCase();
      final accepted = auth == '1' || status == 'active' || rootMap.containsKey('user_info');
      if (!accepted) throw Exception('The portal did not accept this login.');

      return PortalAccount(
        username: info['username']?.toString().isNotEmpty == true
            ? info['username'].toString()
            : credentials.username,
        status: info['status']?.toString() ?? 'connected',
        expiry: _formatExpiry(info['exp_date']?.toString()),
      );
    } catch (_) {
      _credentials = null;
      rethrow;
    }
  }

  Future<List<PortalCategory>> loadLiveCategories() async {
    final result = await _request(action: 'get_live_categories');
    if (result is! List) throw Exception('The portal did not return a live-category list.');
    return result.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      return PortalCategory(
        id: item['category_id']?.toString() ?? '',
        name: item['category_name']?.toString() ?? 'Unnamed category',
      );
    }).toList(growable: false);
  }

  Future<List<LiveChannel>> loadLiveChannels() async {
    final result = await _request(action: 'get_live_streams');
    if (result is! List) throw Exception('The portal did not return a live-channel list.');
    return result.whereType<Map>().map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final extension = (item['container_extension']?.toString() ?? 'ts')
          .replaceFirst(RegExp(r'^\.'), '');
      return LiveChannel(
        id: item['stream_id']?.toString() ?? item['id']?.toString() ?? '',
        name: item['name']?.toString() ?? item['title']?.toString() ?? 'Unnamed channel',
        categoryId: item['category_id']?.toString() ?? '',
        icon: item['stream_icon']?.toString() ?? '',
        extension: RegExp(r'^[A-Za-z0-9]+$').hasMatch(extension) ? extension : 'ts',
      );
    }).where((channel) => channel.id.isNotEmpty).toList(growable: false);
  }

  String streamUrl(LiveChannel channel) {
    final credentials = _credentials;
    if (credentials == null) throw StateError('Connect to a portal first.');
    final user = Uri.encodeComponent(credentials.username);
    final pass = Uri.encodeComponent(credentials.password);
    final streamId = Uri.encodeComponent(channel.id);
    return '${credentials.baseUrl}/live/$user/$pass/$streamId.${channel.extension}';
  }

  void disconnect() {
    _credentials = null;
  }

  void dispose() {
    _credentials = null;
    _client.close();
  }

  Future<dynamic> _request({String? action}) async {
    final credentials = _credentials;
    if (credentials == null) throw StateError('Connect to a portal first.');

    final endpoint = Uri.parse('${credentials.baseUrl}/player_api.php');
    final query = <String, String>{
      'username': credentials.username,
      'password': credentials.password,
      if (action != null) 'action': action,
    };
    final uri = endpoint.replace(queryParameters: query);

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {
            'Accept': 'application/json,*/*',
            'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
          })
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw Exception('Portal request timed out.');
    } on http.ClientException {
      throw Exception('Could not reach the portal. Check the address and network connection.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Portal returned HTTP ${response.statusCode}.');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw Exception('The portal returned a response that was not valid JSON.');
    }
  }

  String _normalizeBase(String raw) {
    var value = raw.trim();
    if (value.isEmpty) throw Exception('Enter the portal server address.');
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null || !uri.isAbsolute || uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw Exception('Enter a valid HTTP or HTTPS server address.');
    }
    if (uri.userInfo.isNotEmpty) {
      throw Exception('Put the username and password in their own fields.');
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw Exception('Use the portal base address, without query parameters.');
    }
    return uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }

  String _formatExpiry(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'null' || raw == '0') return 'Unlimited';
    final seconds = int.tryParse(raw);
    if (seconds == null) return raw;
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }
}

class _PortalCredentials {
  const _PortalCredentials({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  final String baseUrl;
  final String username;
  final String password;
}
