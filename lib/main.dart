import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'xtream_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const VysePortalApp());
}

class VysePortalApp extends StatelessWidget {
  const VysePortalApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF58D6AF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Vyse Portal Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colors,
        scaffoldBackgroundColor: const Color(0xFF0B1018),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF0D1520),
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          labelStyle: TextStyle(color: Color(0xFF91A2B4), fontSize: 12),
          hintStyle: TextStyle(color: Color(0xFF607286), fontSize: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0x222A3A4C)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: Color(0xAA58D6AF), width: 1.2),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      ),
      home: const PortalHomePage(),
    );
  }
}

class PortalHomePage extends StatefulWidget {
  const PortalHomePage({super.key});

  @override
  State<PortalHomePage> createState() => _PortalHomePageState();
}

class _PortalHomePageState extends State<PortalHomePage> {
  static const _allCategories = '__all_live_channels__';

  final _service = XtreamService();
  final _serverController = TextEditingController(text: 'http://lordstreams.live:80');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();

  late final Player _player;
  late final VideoController _videoController;

  List<PortalCategory> _categories = const [];
  List<LiveChannel> _channels = const [];
  String _selectedCategoryId = _allCategories;
  LiveChannel? _activeChannel;
  PortalAccount? _account;
  bool _connected = false;
  bool _busy = false;
  bool _statusIsError = false;
  String _status = 'Enter your portal details to load live channels.';

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
  }

  @override
  void dispose() {
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    _service.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;

    var server = _serverController.text.trim();
    var username = _usernameController.text.trim();
    var password = _passwordController.text;
    if (username.isEmpty && password.isEmpty) {
      final combo = ParsedPortalCombo.tryParse(server);
      if (combo != null) {
        server = combo.server;
        username = combo.username;
        password = combo.password;
        _serverController.text = server;
        _usernameController.text = username;
        _passwordController.text = password;
      }
    }
    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _statusIsError = true;
        _status = 'Enter the portal username and password.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _statusIsError = false;
      _status = 'Checking portal login…';
    });

    try {
      final account = await _service.connect(
        server: server,
        username: username,
        password: password,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Login accepted. Loading categories and channels…';
      });

      final categories = await _service.loadLiveCategories();
      final channels = await _service.loadLiveChannels();
      if (!mounted) return;
      setState(() {
        _account = account;
        _categories = categories;
        _channels = channels;
        _selectedCategoryId = _allCategories;
        _activeChannel = null;
        _connected = true;
        _statusIsError = false;
        _status = 'Loaded ${categories.length} categories and ${channels.length} live channels.';
      });
    } catch (error) {
      _service.disconnect();
      if (!mounted) return;
      setState(() {
        _connected = false;
        _account = null;
        _categories = const [];
        _channels = const [];
        _activeChannel = null;
        _statusIsError = true;
        _status = _cleanError(error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    try {
      await _player.stop();
    } catch (_) {}
    _service.disconnect();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _account = null;
      _categories = const [];
      _channels = const [];
      _selectedCategoryId = _allCategories;
      _activeChannel = null;
      _usernameController.clear();
      _passwordController.clear();
      _searchController.clear();
      _statusIsError = false;
      _status = 'Disconnected. Portal credentials cleared from memory.';
    });
  }

  Future<void> _play(LiveChannel channel) async {
    setState(() {
      _activeChannel = channel;
      _statusIsError = false;
      _status = 'Opening ${channel.name}…';
    });
    try {
      final url = _service.streamUrl(channel);
      await _player.open(
        Media(
          url,
          httpHeaders: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'},
        ),
        play: true,
      );
      if (mounted) {
        setState(() {
          _statusIsError = false;
          _status = 'Player opened ${channel.name}.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusIsError = true;
          _status = _cleanError(error);
        });
      }
    }
  }

  String _cleanError(Object error) {
    return error.toString().replaceFirst(RegExp(r'^(Exception|StateError):\s*'), '');
  }

  List<LiveChannel> get _visibleChannels {
    final query = _searchController.text.trim().toLowerCase();
    return _channels.where((channel) {
      final categoryMatches = _selectedCategoryId == _allCategories ||
          channel.categoryId == _selectedCategoryId;
      final searchMatches = query.isEmpty || channel.name.toLowerCase().contains(query);
      return categoryMatches && searchMatches;
    }).toList(growable: false);
  }

  int _countInCategory(String id) =>
      _channels.where((channel) => channel.categoryId == id).length;

  String _categoryName(String id) {
    for (final category in _categories) {
      if (category.id == id) return category.name;
    }
    return 'Live channel';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 12),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildConnectionCard(),
              const SizedBox(height: 14),
              Expanded(child: _buildWorkspace()),
              const SizedBox(height: 10),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [Color(0xFF81E6C8), Color(0xFF39B995)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Text('V', style: TextStyle(color: Color(0xFF07130F), fontSize: 19, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('VYSE  PORTAL PLAYER', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              SizedBox(height: 3),
              Text('Live TV · Xtream-compatible portals', style: TextStyle(color: Color(0xFF8898A9), fontSize: 11)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF111A26),
            border: Border.all(color: const Color(0x222A3A4C)),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 8, color: _connected ? const Color(0xFF58D6AF) : const Color(0xFF647588)),
              const SizedBox(width: 7),
              Text(_connected ? (_account?.username ?? 'Connected') : 'Not connected', style: const TextStyle(color: Color(0xFFB1C0CE), fontSize: 10)),
            ],
          ),
        ),
        if (_connected) ...[
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _disconnect,
            icon: const Icon(Icons.logout, size: 15),
            label: const Text('Disconnect'),
          ),
        ],
      ],
    );
  }

  Widget _buildConnectionCard() {
    final serverField = TextField(
      controller: _serverController,
      keyboardType: TextInputType.url,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(
        labelText: 'Server address',
        hintText: 'http://provider.example:8080',
        prefixIcon: Icon(Icons.dns_outlined),
      ),
      onSubmitted: (_) => _connect(),
    );
    final usernameField = TextField(
      controller: _usernameController,
      autocorrect: false,
      enableSuggestions: false,
      decoration: const InputDecoration(
        labelText: 'Username',
        hintText: 'Portal username',
        prefixIcon: Icon(Icons.person_outline),
      ),
      onSubmitted: (_) => _connect(),
    );
    final passwordField = TextField(
      controller: _passwordController,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      decoration: const InputDecoration(
        labelText: 'Password',
        hintText: 'Portal password',
        prefixIcon: Icon(Icons.lock_outline),
      ),
      onSubmitted: (_) => _connect(),
    );
    final connectButton = SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _busy ? null : _connect,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.login, size: 17),
        label: Text(_busy ? 'Connecting' : 'Connect'),
      ),
    );

    return _panel(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Eyebrow('PORTAL LOGIN'),
                    SizedBox(height: 4),
                    Text('Connect to your live TV portal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0x163CC49B),
                  border: Border.all(color: const Color(0x2258D6AF)),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text('Credentials stay in memory', style: TextStyle(color: Color(0xFF9DDBC7), fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 880) {
                return Column(
                  children: [
                    serverField,
                    const SizedBox(height: 10),
                    Row(children: [Expanded(child: usernameField), const SizedBox(width: 10), Expanded(child: passwordField)]),
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: SizedBox(width: 150, child: connectButton)),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 5, child: serverField),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: usernameField),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: passwordField),
                  const SizedBox(width: 10),
                  SizedBox(width: 142, child: connectButton),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_statusIsError ? Icons.error_outline : Icons.info_outline, size: 15, color: _statusIsError ? const Color(0xFFFF9296) : const Color(0xFF8A9BAC)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _status,
                  style: TextStyle(fontSize: 10, color: _statusIsError ? const Color(0xFFFF9296) : const Color(0xFF9AABBC)),
                ),
              ),
              const SizedBox(width: 12),
              if (_account?.expiry.isNotEmpty == true)
                Text('Expiry ${_account!.expiry}', style: const TextStyle(color: Color(0xFF7F91A4), fontSize: 9)),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 15, color: Color(0xFFF4C275)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'HTTP does not encrypt credentials or streams. Use only an authorized portal; do not reuse this password.',
                  style: TextStyle(color: Color(0xFFC5A66F), fontSize: 9),
                ),
              ),
              SizedBox(width: 10),
              Text('Combo accepted: http://host:port:user:pass', style: TextStyle(color: Color(0xFF75879A), fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspace() {
    return Row(
      children: [
        Expanded(flex: 2, child: _buildCategoriesPanel()),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: _buildChannelsPanel()),
        const SizedBox(width: 12),
        Expanded(flex: 4, child: _buildPlayerPanel()),
      ],
    );
  }

  Widget _buildCategoriesPanel() {
    final categoryItems = <PortalCategory?>[null, ..._categories];
    return _panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _panelHeader(
            eyebrow: 'BROWSE',
            title: 'Categories',
            trailing: _countBadge(_categories.length),
          ),
          const Divider(height: 1, color: Color(0x221F2B39)),
          Expanded(
            child: !_connected
                ? _emptyPanel(Icons.view_list_outlined, 'Categories appear here after connecting.')
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                    itemCount: categoryItems.length,
                    itemBuilder: (context, index) {
                      final category = categoryItems[index];
                      final isAll = category == null;
                      final id = isAll ? _allCategories : category.id;
                      final name = isAll ? 'All channels' : category.name;
                      final count = isAll ? _channels.length : _countInCategory(category.id);
                      final selected = _selectedCategoryId == id;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Material(
                          color: selected ? const Color(0x1B58D6AF) : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(9),
                            onTap: () => setState(() => _selectedCategoryId = id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(isAll ? Icons.grid_view_rounded : Icons.folder_outlined, size: 15, color: selected ? const Color(0xFF58D6AF) : const Color(0xFF8295A8)),
                                  const SizedBox(width: 9),
                                  Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: selected ? const Color(0xFFD6FFF1) : const Color(0xFFB0BECC)))),
                                  const SizedBox(width: 6),
                                  Text('$count', style: const TextStyle(fontSize: 9, color: Color(0xFF718398))),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: Color(0x221F2B39)),
          const Padding(
            padding: EdgeInsets.all(11),
            child: Row(
              children: [
                Icon(Icons.circle, size: 6, color: Color(0xFF58D6AF)),
                SizedBox(width: 7),
                Expanded(child: Text('Channels are supplied by your portal', style: TextStyle(color: Color(0xFF738597), fontSize: 9))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelsPanel() {
    final visible = _visibleChannels;
    return _panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _panelHeader(
            eyebrow: 'LIVE LIBRARY',
            title: _selectedCategoryId == _allCategories ? 'All channels' : _categoryName(_selectedCategoryId),
            trailing: _countBadge(visible.length, wide: true, suffix: visible.length == 1 ? 'channel' : 'channels'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 11),
            child: TextField(
              controller: _searchController,
              enabled: _connected,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search channels…',
                prefixIcon: Icon(Icons.search, size: 18),
                isDense: true,
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0x221F2B39)),
          Expanded(
            child: !_connected
                ? _emptyPanel(Icons.live_tv_outlined, 'Connect to browse the portal’s live channels.')
                : visible.isEmpty
                    ? _emptyPanel(Icons.search_off, _searchController.text.isEmpty ? 'No channels in this category.' : 'No matching channels.')
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 5),
                        itemBuilder: (context, index) => _channelTile(visible[index]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _channelTile(LiveChannel channel) {
    final selected = _activeChannel?.id == channel.id;
    final initial = channel.name.trim().isEmpty ? 'L' : channel.name.trim()[0].toUpperCase();
    return Material(
      color: selected ? const Color(0x1B58D6AF) : const Color(0x08FFFFFF),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _play(channel),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? const Color(0x6658D6AF) : const Color(0x101F2B39)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0xFF1A2937), borderRadius: BorderRadius.circular(8)),
                child: Text(initial, style: const TextStyle(color: Color(0xFFB5C8D7), fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(_categoryName(channel.categoryId), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF718398), fontSize: 8)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(selected ? Icons.graphic_eq : Icons.play_arrow_rounded, color: selected ? const Color(0xFF58D6AF) : const Color(0xFF71879A), size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerPanel() {
    final active = _activeChannel;
    return _panel(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Eyebrow('NOW PLAYING'),
                    const SizedBox(height: 4),
                    Text(active?.name ?? 'Choose a channel', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(color: const Color(0x143DC59B), borderRadius: BorderRadius.circular(30), border: Border.all(color: const Color(0x2258D6AF))),
                child: const Row(children: [Icon(Icons.circle, size: 6, color: Color(0xFF58D6AF)), SizedBox(width: 5), Text('LIVE', style: TextStyle(color: Color(0xFF9BE4CB), fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: .7))]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  Video(controller: _videoController),
                  if (active == null)
                    IgnorePointer(
                      child: Container(
                        color: const Color(0xB20B1018),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.play_circle_outline, size: 52, color: Color(0xFF7BE0BF)),
                            SizedBox(height: 12),
                            Text('Your stream, in focus.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            SizedBox(height: 5),
                            Text('Select a channel to start playback.', style: TextStyle(color: Color(0xFF8798AA), fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.circle, size: 7, color: _statusIsError ? const Color(0xFFFF7F85) : const Color(0xFF58D6AF)),
              const SizedBox(width: 7),
              Expanded(child: Text(active == null ? 'Ready when you are' : 'Selected: ${active.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF96A8BA), fontSize: 9))),
              const Text('PORTAL STREAM', style: TextStyle(color: Color(0xFF667A8E), fontSize: 8, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 10),
          const Text('The portal controls channel availability and stream quality.', style: TextStyle(color: Color(0xFF718398), fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return const Row(
      children: [
        Text('VYSE PORTAL PLAYER', style: TextStyle(color: Color(0xFF738597), fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        Spacer(),
        Text('Use only with authorized IPTV access · Credentials are not saved', style: TextStyle(color: Color(0xFF576A7E), fontSize: 8)),
      ],
    );
  }

  Widget _panelHeader({required String eyebrow, required String title, required Widget trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 15, 13, 12),
      child: Row(
        children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_Eyebrow(eyebrow), const SizedBox(height: 4), Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))])),
          trailing,
        ],
      ),
    );
  }

  Widget _countBadge(int count, {bool wide = false, String suffix = ''}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: wide ? 9 : 7, vertical: 5),
      decoration: BoxDecoration(color: const Color(0x142A3D4F), borderRadius: BorderRadius.circular(8)),
      child: Text(wide ? '$count $suffix' : '$count', style: const TextStyle(color: Color(0xFF9DB1C2), fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }

  Widget _emptyPanel(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF6E8296), size: 34),
            const SizedBox(height: 11),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF8293A5), fontSize: 10, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xE6111A26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x221F2B39)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(color: Color(0xFF738699), fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.6),
      );
}
