import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'app_config.dart';
import 'race_schedule.dart';
import 'xtream_service.dart';

const _ink = Color(0xFF08090A);
const _surfaceRaised = Color(0xFF202127);
const _text = Color(0xFFF5F6F7);
const _muted = Color(0xFF9B9DA5);
const _dim = Color(0xFF676B74);
const _f1Red = Color(0xFFE10600);
const _green = Color(0xFF00D57E);
const _line = Color(0x2EFFFFFF);
const _playerAgent = 'VLC/3.0.20 LibVLC/3.0.20';

const _teamColors = <_LiveryOption>[
  _LiveryOption('FreeF1 Red', Color(0xFFE10600)),
  _LiveryOption('McLaren', Color(0xFFFF8000)),
  _LiveryOption('Ferrari', Color(0xFFDC0000)),
  _LiveryOption('Red Bull', Color(0xFF1E41FF)),
  _LiveryOption('Mercedes', Color(0xFF00D2BE)),
  _LiveryOption('Williams', Color(0xFF005AFF)),
  _LiveryOption('Aston Martin', Color(0xFF006F62)),
  _LiveryOption('Alpine', Color(0xFFFF0080)),
  _LiveryOption('Haas', Color(0xFFB6BABD)),
  _LiveryOption('Audi', Color(0xFFE62213)),
  _LiveryOption('Cadillac', Color(0xFFB4A07A)),
  _LiveryOption('Racing Bulls', Color(0xFF6692FF)),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      final window = WindowManager.instance.getCurrent();
      if (window != null) {
        window.title = 'FreeF1 Cockpit';
        window.setSize(const Size(1500, 940).toNative(), false);
        window.minimumSize = const Size(980, 680).toNative();
        window.center();
      }
    } catch (_) {
      // Keep the in-app layout if native window setup is unavailable.
    }
  }

  runApp(const FreeF1CockpitApp());
}

class FreeF1CockpitApp extends StatelessWidget {
  const FreeF1CockpitApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FreeF1 Cockpit',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _f1Red,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: _ink,
      fontFamily: 'Segoe UI',
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Color(0xFF0E0F12),
        contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        hintStyle: TextStyle(color: _dim, fontSize: 12),
        prefixIconColor: _muted,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
          borderSide: BorderSide(color: Color(0x25FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
          borderSide: BorderSide(color: Color(0xFFE10600), width: 1.2),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(11)),
        ),
      ),
    ),
    home: const CockpitPage(),
  );
}

class CockpitPage extends StatefulWidget {
  const CockpitPage({super.key});

  @override
  State<CockpitPage> createState() => _CockpitPageState();
}

class _CockpitPageState extends State<CockpitPage> {
  final XtreamService _service = XtreamService();
  final TextEditingController _searchController = TextEditingController();

  late final Player _player;
  late final VideoController _videoController;
  StreamSubscription<bool>? _playingSubscription;

  List<LiveFeed> _feeds = const [];
  LiveFeed? _activeFeed;
  String? _loadError;
  String? _playbackError;
  String _playerNote = 'Choose a feed to start playback.';
  String _searchText = '';
  bool _loadingFeeds = false;
  bool _loadingPlayback = false;
  bool _isPlaying = false;
  bool _theaterMode = false;
  bool _showTheaterSources = true;
  bool _multiView = false;
  Color _livery = _f1Red;
  int _playToken = 0;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() {
        _isPlaying = playing;
        if (playing) {
          _loadingPlayback = false;
          _playbackError = null;
          _playerNote = 'On air · ${_activeFeed?.name ?? 'Live feed'}';
        }
      });
    });
    unawaited(_loadFeeds());
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _searchController.dispose();
    _service.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  List<LiveFeed> get _visibleFeeds {
    final query = _searchText.trim().toLowerCase();
    if (query.isEmpty) return _feeds;
    return _feeds
        .where((feed) => feed.name.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Future<void> _loadFeeds() async {
    if (_loadingFeeds) return;
    setState(() {
      _loadingFeeds = true;
      _loadError = null;
    });

    try {
      await _service.connect();
      final feeds = await _service.loadFormulaOneFeeds();
      final keepActive =
          _activeFeed != null && feeds.any((feed) => feed.id == _activeFeed!.id)
          ? _activeFeed
          : null;
      if (_activeFeed != null && keepActive == null) {
        await _player.stop();
      }
      if (!mounted) return;
      setState(() {
        _feeds = feeds;
        _activeFeed = keepActive;
        _loadingFeeds = false;
        _isPlaying = false;
        _playerNote = feeds.isEmpty
            ? 'The Formula 1 category is available but has no streams.'
            : '${feeds.length} feeds ready · ${AppConfig.categoryName}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _feeds = const [];
        _loadingFeeds = false;
        _loadError = _friendlyError(error);
        _playerNote = 'Portal connection unavailable.';
      });
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString().replaceFirst(
      RegExp(r'^(Exception|StateError):\s*'),
      '',
    );
    return message.isEmpty ? 'Something went wrong. Try again.' : message;
  }

  Future<void> _selectFeed(LiveFeed feed) async {
    if (_multiView) {
      setState(() => _multiView = false);
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }

    final token = ++_playToken;
    setState(() {
      _activeFeed = feed;
      _loadingPlayback = true;
      _playbackError = null;
      _isPlaying = false;
      _playerNote = 'Establishing feed…';
    });

    try {
      await _player.open(
        Media(
          _service.streamUrl(feed),
          httpHeaders: const {'User-Agent': _playerAgent},
        ),
        play: true,
      );
      if (!mounted || token != _playToken) return;
      setState(() {
        _loadingPlayback = false;
        _playerNote = 'Feed opened · waiting for video';
      });
    } catch (error) {
      if (!mounted || token != _playToken) return;
      setState(() {
        _loadingPlayback = false;
        _playbackError = _friendlyError(error);
        _playerNote = 'Could not start this feed.';
      });
    }
  }

  Future<void> _stopPlayback() async {
    ++_playToken;
    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _activeFeed = null;
      _loadingPlayback = false;
      _playbackError = null;
      _isPlaying = false;
      _playerNote = 'Choose a feed to start playback.';
    });
  }

  Future<void> _retryFeed() async {
    final feed = _activeFeed;
    if (feed != null) await _selectFeed(feed);
  }

  Future<void> _nextFeed() async {
    final visible = _visibleFeeds;
    if (visible.isEmpty) return;
    final current = visible.indexWhere((feed) => feed.id == _activeFeed?.id);
    await _selectFeed(visible[(current + 1) % visible.length]);
  }

  void _toggleTheater() {
    final next = !_theaterMode;
    setState(() => _theaterMode = next);
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        final window = WindowManager.instance.getCurrent();
        if (window != null) window.isFullScreen = next;
      } catch (_) {
        // Keep the expanded in-app theater layout even if OS fullscreen fails.
      }
    }
  }

  Future<void> _toggleMultiView() async {
    if (_multiView) {
      final resume = _activeFeed;
      setState(() => _multiView = false);
      if (resume != null) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
        await _selectFeed(resume);
      }
      return;
    }

    try {
      await _player.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _multiView = true;
      _loadingPlayback = false;
      _isPlaying = false;
      _playerNote =
          'Multiview · each tile can use an additional portal connection.';
    });
  }

  Future<void> _openWebsite(String path) async {
    final uri = Uri.parse('${AppConfig.website}$path');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _showMessage('Could not open the website.');
    } catch (_) {
      if (mounted) _showMessage('Could not open the website.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _showRaceTimes() async {
    await showDialog<void>(
      context: context,
      builder: (context) => const RaceTimesDialog(year: AppConfig.season),
    );
  }

  Future<void> _chooseLivery() async {
    final selected = await showDialog<_LiveryOption>(
      context: context,
      builder: (context) => _LiveryDialog(current: _livery),
    );
    if (selected == null || !mounted) return;
    setState(() => _livery = selected.color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _livery,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: _ink,
      fontFamily: 'Segoe UI',
      inputDecorationTheme: Theme.of(context).inputDecorationTheme,
    );

    return Theme(
      data: theme,
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.escape): _ExitTheaterIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _ExitTheaterIntent: CallbackAction<_ExitTheaterIntent>(
              onInvoke: (_) {
                if (_theaterMode) _toggleTheater();
                return null;
              },
            ),
          },
          child: _theaterMode
              ? _buildTheaterScaffold()
              : _buildNormalScaffold(),
        ),
      ),
    );
  }

  Widget _buildNormalScaffold() => Scaffold(
    backgroundColor: _ink,
    body: Stack(
      children: [
        const Positioned.fill(child: _CockpitBackdrop()),
        SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 1180;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1600),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildPageHeading(),
                              const SizedBox(height: 20),
                              if (wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _buildMainColumn()),
                                    const SizedBox(width: 26),
                                    SizedBox(
                                      width: 310,
                                      child: _buildSideRail(),
                                    ),
                                  ],
                                )
                              else ...[
                                _buildMainColumn(),
                                const SizedBox(height: 16),
                                _buildSideRail(),
                              ],
                              const SizedBox(height: 22),
                              _buildFooter(),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildTheaterScaffold() => Scaffold(
    backgroundColor: _ink,
    body: Stack(
      children: [
        const Positioned.fill(child: _CockpitBackdrop()),
        SafeArea(
          child: Column(
            children: [
              _buildTopBar(theater: true),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(child: _buildPlayerCard(theater: true)),
                            const SizedBox(height: 12),
                            _buildActionBar(theater: true),
                          ],
                        ),
                      ),
                      if (_showTheaterSources &&
                          MediaQuery.sizeOf(context).width >= 980) ...[
                        const SizedBox(width: 14),
                        SizedBox(width: 330, child: _buildTheaterRail()),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildTopBar({bool theater = false}) {
    final connected = _service.isConnected && _loadError == null;
    final status = _loadingFeeds
        ? 'CONNECTING'
        : connected
        ? 'CONNECTED'
        : 'OFFLINE';
    final statusColor = _loadingFeeds
        ? const Color(0xFFFFB020)
        : connected
        ? _green
        : const Color(0xFFF87168);

    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xE90A0A0C),
        border: Border(bottom: BorderSide(color: Color(0x19FFFFFF))),
      ),
      child: Row(
        children: [
          _FreeF1Mark(color: _livery, size: 32),
          const SizedBox(width: 10),
          const Text(
            'FreeF1',
            style: TextStyle(
              color: _text,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(width: 13),
          Container(width: 1, height: 26, color: _line),
          const SizedBox(width: 13),
          Text(
            theater ? 'THEATER' : 'COCKPIT',
            style: TextStyle(
              color: _livery,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.0,
            ),
          ),
          const Spacer(),
          _StatusPill(label: status, color: statusColor),
          const SizedBox(width: 9),
          IconButton(
            tooltip: 'Refresh Formula 1 streams',
            onPressed: _loadingFeeds ? null : _loadFeeds,
            icon: const Icon(Icons.refresh_rounded, size: 19),
          ),
          if (theater) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: _showTheaterSources
                  ? 'Hide source rail'
                  : 'Show source rail',
              onPressed: () =>
                  setState(() => _showTheaterSources = !_showTheaterSources),
              icon: Icon(
                _showTheaterSources
                    ? Icons.view_sidebar_rounded
                    : Icons.view_sidebar_outlined,
                size: 19,
              ),
            ),
            const SizedBox(width: 4),
            OutlinedButton.icon(
              onPressed: _toggleTheater,
              icon: const Icon(Icons.fullscreen_exit_rounded, size: 17),
              label: const Text('Exit theater'),
            ),
          ] else ...[
            const SizedBox(width: 9),
            IconButton(
              tooltip: 'Open FreeF1 website',
              onPressed: () => _openWebsite(''),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPageHeading() => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _livery,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _livery.withAlpha(110),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 9),
                const _Eyebrow('BROADCAST CONTROL'),
              ],
            ),
            const SizedBox(height: 10),
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  color: _text,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -2.2,
                  height: 1,
                ),
                children: [
                  const TextSpan(text: 'THE '),
                  TextSpan(
                    text: 'COCKPIT',
                    style: TextStyle(color: _livery),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'A focused F1 live-feed console.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      ),
      if (MediaQuery.sizeOf(context).width >= 600)
        Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF16171B),
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.live_tv_rounded, size: 15, color: _livery),
              const SizedBox(width: 8),
              Text(
                '${_feeds.length} FEED${_feeds.length == 1 ? '' : 'S'}',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _buildMainColumn() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _buildPlayerCard(),
      const SizedBox(height: 14),
      _buildActionBar(),
      const SizedBox(height: 16),
      _buildSourcesPanel(),
    ],
  );

  Widget _buildPlayerCard({bool theater = false}) {
    final active = _activeFeed;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x35FFFFFF)),
        boxShadow: [
          const BoxShadow(
            color: Color(0x90000000),
            blurRadius: 38,
            offset: Offset(0, 18),
          ),
          BoxShadow(
            color: _livery.withAlpha(25),
            blurRadius: 38,
            spreadRadius: 1,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 39,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1E1B20),
                  Color(0xFF15161C),
                  Color(0xFF111217),
                ],
              ),
              border: Border(bottom: BorderSide(color: Color(0x18FFFFFF))),
            ),
            child: Row(
              children: [
                _PulseDot(color: _livery),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    active == null
                        ? 'FREEF1://LIVE/FORMULA-1'
                        : 'FREEF1://LIVE/FORMULA-1/${active.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF85868D),
                      fontSize: 10,
                      fontFamily: 'Consolas',
                      letterSpacing: 0.45,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _LiveBadge(
                  label: _multiView
                      ? 'MULTIVIEW'
                      : active == null
                      ? 'STANDBY'
                      : 'LIVE',
                  active: active != null || _multiView,
                  accent: _livery,
                ),
                if (active != null && !_multiView) ...[
                  const SizedBox(width: 7),
                  IconButton(
                    tooltip: 'Stop playback',
                    visualDensity: VisualDensity.compact,
                    onPressed: _stopPlayback,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: _muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (theater)
            Expanded(child: _buildPlayerStage())
          else
            AspectRatio(aspectRatio: 16 / 9, child: _buildPlayerStage()),
        ],
      ),
    );
  }

  Widget _buildPlayerStage() => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (_multiView)
          MultiViewPanel(
            feeds: _feeds,
            service: _service,
            accent: _livery,
            initialFeed: _activeFeed,
          )
        else
          Video(controller: _videoController),
        if (!_multiView && _activeFeed == null) _buildStandbyOverlay(),
        if (!_multiView && _loadingPlayback && _activeFeed != null)
          _buildLoadingOverlay(),
        if (!_multiView && _playbackError != null) _buildPlaybackErrorOverlay(),
      ],
    ),
  );

  Widget _buildStandbyOverlay() => Positioned.fill(
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.1,
            colors: [Color(0xFF17181D), Color(0xFF050506)],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _livery.withAlpha(27),
                border: Border.all(color: _livery.withAlpha(100)),
                boxShadow: [
                  BoxShadow(color: _livery.withAlpha(30), blurRadius: 24),
                ],
              ),
              child: Icon(Icons.play_arrow_rounded, size: 34, color: _livery),
            ),
            const SizedBox(height: 15),
            const Text(
              'Not on air yet',
              style: TextStyle(
                color: _text,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _loadingFeeds
                  ? 'Finding the Formula 1 feeds…'
                  : 'Select a source below to open the live player.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildLoadingOverlay() => Positioned.fill(
    child: ColoredBox(
      color: const Color(0x90000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.3,
                color: _livery,
              ),
            ),
            const SizedBox(height: 13),
            const Text(
              'Establishing feed…',
              style: TextStyle(color: _text, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildPlaybackErrorOverlay() => Positioned.fill(
    child: ColoredBox(
      color: const Color(0xE6000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.signal_wifi_connected_no_internet_4_rounded,
                color: Color(0xFFF87168),
                size: 30,
              ),
              const SizedBox(height: 11),
              const Text(
                'Feed unavailable',
                style: TextStyle(color: _text, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _playbackError ?? 'The stream could not be opened.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _retryFeed,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _nextFeed,
                    icon: const Icon(Icons.skip_next_rounded, size: 17),
                    label: const Text('Next feed'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildActionBar({bool theater = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF202127), Color(0xFF14151A)],
      ),
      border: Border.all(color: const Color(0x24FFFFFF)),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x44000000),
          blurRadius: 22,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final info = _buildNowPlayingInfo();
        final actions = Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _ActionButton(
              icon: Icons.grid_view_rounded,
              label: 'Multiview',
              accent: _livery,
              selected: _multiView,
              onPressed: _toggleMultiView,
            ),
            _ActionButton(
              icon: theater
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              label: theater ? 'Exit theater' : 'Theater',
              accent: _livery,
              onPressed: _toggleTheater,
            ),
            _ActionButton(
              icon: Icons.schedule_rounded,
              label: 'Race Times',
              accent: _livery,
              onPressed: _showRaceTimes,
            ),
            _ActionButton(
              icon: Icons.palette_outlined,
              label: 'Team Livery',
              accent: _livery,
              onPressed: _chooseLivery,
            ),
          ],
        );

        if (constraints.maxWidth < 850) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [info, const SizedBox(height: 12), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: info),
            const SizedBox(width: 14),
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: actions),
            ),
          ],
        );
      },
    ),
  );

  Widget _buildNowPlayingInfo() => Row(
    children: [
      _PulseDot(color: _activeFeed == null ? _dim : _livery, size: 8),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  _multiView
                      ? 'MULTIVIEW ACTIVE'
                      : _activeFeed == null
                      ? 'UP NEXT'
                      : _isPlaying
                      ? 'LIVE NOW'
                      : 'TUNING IN',
                  style: const TextStyle(
                    color: _text,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(width: 7),
                const Text('·', style: TextStyle(color: _dim)),
                const SizedBox(width: 7),
                Text(
                  _multiView ? '4 feed slots' : '${_feeds.length} sources',
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _multiView
                  ? 'Formula 1 multi-feed view'
                  : _activeFeed?.name ?? 'Select a live Formula 1 feed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _playerNote,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildSourcesPanel() => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF202127), Color(0xFF14151A)],
      ),
      border: Border.all(color: const Color(0x24FFFFFF)),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x44000000),
          blurRadius: 26,
          offset: Offset(0, 9),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Eyebrow('LIVE LIBRARY'),
                  SizedBox(height: 5),
                  Text(
                    'Stream sources',
                    style: TextStyle(
                      color: _text,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            _CountPill('${_feeds.length} FEEDS', accent: _livery),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildSearchField()),
            const SizedBox(width: 10),
            if (_searchText.isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchText = '');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _CategoryPill(accent: _livery),
            Text(
              _loadError == null
                  ? 'Showing only this category'
                  : 'Feed list unavailable',
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_loadingFeeds && _feeds.isEmpty)
          _buildLoadingSources()
        else if (_loadError != null)
          _buildSourcesError()
        else if (_visibleFeeds.isEmpty)
          _buildEmptySources()
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = math
                  .max(1, (constraints.maxWidth / 255).floor())
                  .toInt();
              return GridView.builder(
                shrinkWrap: true,
                primary: false,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _visibleFeeds.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 9,
                  mainAxisSpacing: 9,
                  mainAxisExtent: 72,
                ),
                itemBuilder: (context, index) =>
                    _buildFeedTile(_visibleFeeds[index]),
              );
            },
          ),
        if (_loadError == null && !_loadingFeeds && _feeds.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x1EFFFFFF)),
          const SizedBox(height: 10),
          const Text(
            'The portal supplies channel availability and stream quality.',
            style: TextStyle(color: _dim, fontSize: 10),
          ),
        ],
      ],
    ),
  );

  Widget _buildSearchField({bool compact = false}) => TextField(
    controller: _searchController,
    onChanged: (value) => setState(() => _searchText = value),
    style: const TextStyle(color: _text, fontSize: 12),
    decoration: InputDecoration(
      isDense: true,
      hintText: 'Search Formula 1 streams…',
      prefixIcon: const Icon(Icons.search_rounded, size: 18),
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 13,
        vertical: compact ? 9 : 12,
      ),
    ),
  );

  Widget _buildLoadingSources() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 34),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 11),
        Text(
          'Finding Formula 1 feeds…',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _buildSourcesError() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: _EmptyState(
      icon: Icons.signal_wifi_connected_no_internet_4_rounded,
      title: 'Could not load the feed list',
      message: _loadError ?? 'Try again in a moment.',
      actionLabel: 'Retry',
      onAction: _loadingFeeds ? null : _loadFeeds,
      accent: _livery,
    ),
  );

  Widget _buildEmptySources() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: _EmptyState(
      icon: Icons.live_tv_outlined,
      title: _searchText.isEmpty ? 'No streams found' : 'No matching feeds',
      message: _searchText.isEmpty
          ? 'The configured Formula 1 category has no streams right now.'
          : 'Try a different search.',
      actionLabel: _searchText.isEmpty ? 'Refresh' : 'Clear search',
      onAction: _searchText.isEmpty
          ? (_loadingFeeds ? null : _loadFeeds)
          : () {
              _searchController.clear();
              setState(() => _searchText = '');
            },
      accent: _livery,
    ),
  );

  Widget _buildFeedTile(LiveFeed feed, {bool compact = false}) {
    final selected = !_multiView && _activeFeed?.id == feed.id;
    final icon = feed.iconUrl.trim();
    return Material(
      color: selected ? _livery.withAlpha(34) : const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _selectFeed(feed),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 9 : 11,
            vertical: compact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? _livery.withAlpha(190)
                  : const Color(0x20FFFFFF),
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: _livery.withAlpha(24), blurRadius: 17)]
                : null,
          ),
          child: Row(
            children: [
              _FeedArtwork(
                url: icon,
                name: feed.name,
                accent: _livery,
                compact: compact,
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      feed.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _text,
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        _TinyDot(color: selected ? _livery : _green),
                        const SizedBox(width: 5),
                        Text(
                          selected ? 'NOW PLAYING' : 'LIVE FEED',
                          style: TextStyle(
                            color: selected ? _livery : _muted,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.75,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              Icon(
                selected ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                color: selected ? _livery : _dim,
                size: compact ? 17 : 19,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideRail() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SideCard(
        eyebrow: 'NOW PLAYING',
        title: _multiView
            ? 'Multiview'
            : (_activeFeed?.name ?? 'No feed selected'),
        subtitle: _multiView
            ? 'Choose up to four independent feeds.'
            : _activeFeed == null
            ? 'Select a live source from the feed library.'
            : _isPlaying
            ? 'Playback is active.'
            : 'Connecting to the selected source.',
        icon: Icons.sensors_rounded,
        accent: _livery,
      ),
      const SizedBox(height: 13),
      _SideCard(
        eyebrow: 'FEED LIBRARY',
        title: AppConfig.categoryName,
        subtitle: _loadingFeeds
            ? 'Loading the single configured category…'
            : '${_feeds.length} channel${_feeds.length == 1 ? '' : 's'} available.',
        icon: Icons.live_tv_rounded,
        accent: _livery,
      ),
      const SizedBox(height: 13),
      _SideLinkCard(
        title: 'Live timing',
        subtitle: 'Tower, sectors, race control & radio',
        icon: Icons.speed_rounded,
        onTap: () => _openWebsite('/live-timing'),
      ),
      const SizedBox(height: 10),
      _SideLinkCard(
        title: 'Championship',
        subtitle: 'Standings and points',
        icon: Icons.emoji_events_outlined,
        onTap: () => _openWebsite('/standings'),
      ),
      const SizedBox(height: 10),
      _SideLinkCard(
        title: 'FreeF1 website',
        subtitle: 'Open the full race-weekend companion',
        icon: Icons.open_in_new_rounded,
        onTap: () => _openWebsite(''),
      ),
      const SizedBox(height: 13),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x99101216),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x18FFFFFF)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: _dim),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'This independent app is not affiliated with Formula One or the FIA. Streams are supplied by the configured portal.',
                style: TextStyle(color: _muted, fontSize: 10, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildTheaterRail() => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF202127), Color(0xFF131419)],
      ),
      border: Border.all(color: const Color(0x24FFFFFF)),
      borderRadius: BorderRadius.circular(17),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 10),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Eyebrow('FORMULA 1'),
                    SizedBox(height: 4),
                    Text(
                      'Stream sources',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _CountPill('${_feeds.length}', accent: _livery),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: _buildSearchField(compact: true),
        ),
        const Divider(height: 1, color: Color(0x1FFFFFFF)),
        Expanded(
          child: _loadingFeeds && _feeds.isEmpty
              ? _buildLoadingSources()
              : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: _EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: 'Feed list unavailable',
                      message: _loadError!,
                      actionLabel: 'Retry',
                      onAction: _loadFeeds,
                      accent: _livery,
                    ),
                  ),
                )
              : _visibleFeeds.isEmpty
              ? const Center(
                  child: Text(
                    'No feeds match.',
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: _visibleFeeds.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 7),
                  itemBuilder: (context, index) =>
                      _buildFeedTile(_visibleFeeds[index], compact: true),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 7, 13, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _CategoryPill(accent: _livery, compact: true),
          ),
        ),
      ],
    ),
  );

  Widget _buildFooter() => Row(
    children: [
      const Text(
        'FREEF1 COCKPIT',
        style: TextStyle(
          color: _dim,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
      const Spacer(),
      Flexible(
        child: Text(
          '${_feeds.length} Formula 1 feeds · ${AppConfig.season} season',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: const TextStyle(color: _dim, fontSize: 9),
        ),
      ),
    ],
  );
}

class MultiViewPanel extends StatefulWidget {
  const MultiViewPanel({
    super.key,
    required this.feeds,
    required this.service,
    required this.accent,
    this.initialFeed,
  });

  final List<LiveFeed> feeds;
  final XtreamService service;
  final Color accent;
  final LiveFeed? initialFeed;

  @override
  State<MultiViewPanel> createState() => _MultiViewPanelState();
}

class _MultiViewPanelState extends State<MultiViewPanel> {
  final List<_PlayerSlot> _slots = List<_PlayerSlot>.generate(
    4,
    (_) => _PlayerSlot(),
  );

  @override
  void initState() {
    super.initState();
    if (widget.initialFeed != null && widget.feeds.isNotEmpty) {
      unawaited(_select(0, widget.initialFeed));
    }
  }

  @override
  void dispose() {
    for (final slot in _slots) {
      final player = slot.player;
      if (player != null) unawaited(player.dispose());
    }
    super.dispose();
  }

  Future<void> _select(int index, LiveFeed? feed) async {
    final slot = _slots[index];
    slot.feed = feed;
    slot.error = null;

    if (feed == null) {
      slot.loading = false;
      try {
        await slot.player?.stop();
      } catch (_) {}
      if (mounted) setState(() {});
      return;
    }

    slot.player ??= Player();
    slot.controller ??= VideoController(slot.player!);
    slot.loading = true;
    if (mounted) setState(() {});

    try {
      await slot.player!.open(
        Media(
          widget.service.streamUrl(feed),
          httpHeaders: const {'User-Agent': _playerAgent},
        ),
        play: true,
      );
    } catch (_) {
      slot.error = 'This feed could not be opened.';
    } finally {
      slot.loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(4),
    physics: const NeverScrollableScrollPhysics(),
    itemCount: _slots.length,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 4,
      mainAxisSpacing: 4,
      childAspectRatio: 16 / 9,
    ),
    itemBuilder: (context, index) => _buildTile(index, _slots[index]),
  );

  Widget _buildTile(int index, _PlayerSlot slot) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF070708),
      border: Border.all(color: widget.accent.withAlpha(90)),
      borderRadius: BorderRadius.circular(9),
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (slot.controller != null) Video(controller: slot.controller!),
        if (slot.feed == null)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_to_queue_rounded,
                  color: widget.accent,
                  size: 24,
                ),
                const SizedBox(height: 7),
                const Text(
                  'Choose a feed',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
        Positioned(
          left: 5,
          right: 5,
          top: 5,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: const Color(0xCC101114),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0x26FFFFFF)),
            ),
            child: Row(
              children: [
                Text(
                  '0${index + 1}',
                  style: TextStyle(
                    color: widget.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<LiveFeed?>(
                      isExpanded: true,
                      value: slot.feed,
                      dropdownColor: _surfaceRaised,
                      style: const TextStyle(color: _text, fontSize: 10),
                      hint: const Text(
                        'Select source',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                      items: [
                        const DropdownMenuItem<LiveFeed?>(
                          value: null,
                          child: Text('No feed'),
                        ),
                        ...widget.feeds.map(
                          (feed) => DropdownMenuItem<LiveFeed?>(
                            value: feed,
                            child: Text(
                              feed.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (feed) => unawaited(_select(index, feed)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (slot.loading)
          ColoredBox(
            color: const Color(0x88000000),
            child: Center(
              child: CircularProgressIndicator(
                color: widget.accent,
                strokeWidth: 2,
              ),
            ),
          ),
        if (slot.error != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Text(
              slot.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFF87168), fontSize: 9),
            ),
          ),
      ],
    ),
  );
}

class RaceTimesDialog extends StatefulWidget {
  const RaceTimesDialog({super.key, required this.year});

  final int year;

  @override
  State<RaceTimesDialog> createState() => _RaceTimesDialogState();
}

class _RaceTimesDialogState extends State<RaceTimesDialog> {
  late final RaceScheduleService _service;
  late final Future<List<RaceWeekend>> _future;

  @override
  void initState() {
    super.initState();
    _service = RaceScheduleService();
    _future = _service.loadSeason(widget.year);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  String _time(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day ${months[local.month - 1]} · $hour:$minute';
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: const Color(0xFF141519),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0x2EFFFFFF)),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Eyebrow('SEASON ${AppConfig.season}'),
                      SizedBox(height: 5),
                      Text(
                        'Race Times',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Times are shown in your local timezone.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
            const SizedBox(height: 13),
            Expanded(
              child: FutureBuilder<List<RaceWeekend>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const _EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Race times unavailable',
                      message: 'The schedule service could not be reached.',
                      accent: _f1Red,
                    );
                  }
                  final weekends = snapshot.data ?? const <RaceWeekend>[];
                  if (weekends.isEmpty) {
                    return const Center(
                      child: Text(
                        'No race schedule was returned.',
                        style: TextStyle(color: _muted),
                      ),
                    );
                  }
                  final now = DateTime.now().toUtc();
                  final upcoming = weekends.where(
                    (weekend) => weekend.sessions.last.start.isAfter(
                      now.subtract(const Duration(hours: 4)),
                    ),
                  );
                  final display = upcoming.isEmpty
                      ? weekends.reversed.take(3).toList()
                      : upcoming.toList();
                  return ListView.separated(
                    itemCount: display.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 9),
                    itemBuilder: (context, index) {
                      final weekend = display.elementAt(index);
                      return Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1C21),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x20FFFFFF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0x22E10600),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'R${weekend.round}',
                                    style: const TextStyle(
                                      color: _f1Red,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    weekend.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _text,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (weekend.locality.isNotEmpty ||
                                weekend.country.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${weekend.locality}${weekend.locality.isNotEmpty && weekend.country.isNotEmpty ? ', ' : ''}${weekend.country}',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                            const SizedBox(height: 9),
                            for (final session in weekend.sessions)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 3,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        session.name,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _time(session.start),
                                      style: const TextStyle(
                                        color: _text,
                                        fontSize: 10,
                                        fontFamily: 'Consolas',
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LiveryDialog extends StatelessWidget {
  const _LiveryDialog({required this.current});

  final Color current;

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF17181C),
    title: const Text('Choose your livery'),
    content: SizedBox(
      width: 420,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in _teamColors)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.of(context).pop(option),
              child: Container(
                width: 124,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF222329),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: current.toARGB32() == option.color.toARGB32()
                        ? option.color
                        : const Color(0x22FFFFFF),
                    width: current.toARGB32() == option.color.toARGB32()
                        ? 1.5
                        : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        color: option.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

class _PlayerSlot {
  Player? player;
  VideoController? controller;
  LiveFeed? feed;
  String? error;
  bool loading = false;
}

class _LiveryOption {
  const _LiveryOption(this.name, this.color);

  final String name;
  final Color color;
}

class _ExitTheaterIntent extends Intent {
  const _ExitTheaterIntent();
}

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF202127), Color(0xFF14151A)],
      ),
      border: Border.all(color: const Color(0x24FFFFFF)),
      borderRadius: BorderRadius.circular(17),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 22,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withAlpha(28),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withAlpha(75)),
          ),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Eyebrow(eyebrow),
              const SizedBox(height: 5),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _text,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SideLinkCard extends StatelessWidget {
  const _SideLinkCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF191A1F),
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x21FFFFFF)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(
                color: const Color(0x14FFFFFF),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0x20FFFFFF)),
              ),
              child: Icon(icon, color: _muted, size: 16),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      foregroundColor: selected ? accent : _text,
      backgroundColor: selected
          ? accent.withAlpha(32)
          : const Color(0x12FFFFFF),
      side: BorderSide(
        color: selected ? accent.withAlpha(175) : const Color(0x26FFFFFF),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      textStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withAlpha(24),
      border: Border.all(color: color.withAlpha(65)),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TinyDot(color: color),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ],
    ),
  );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({
    required this.label,
    required this.active,
    required this.accent,
  });

  final String label;
  final bool active;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: active ? accent.withAlpha(35) : const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: active ? accent.withAlpha(95) : const Color(0x20FFFFFF),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active) ...[_TinyDot(color: accent), const SizedBox(width: 5)],
        Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFFFFAAA5) : _muted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.65,
          ),
        ),
      ],
    ),
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill(this.label, {required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0x18FFFFFF),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: const Color(0x20FFFFFF)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: accent,
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _CategoryPill extends StatelessWidget {
  const _CategoryPill({required this.accent, this.compact = false});

  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 8 : 10,
      vertical: compact ? 5 : 6,
    ),
    decoration: BoxDecoration(
      color: accent.withAlpha(28),
      border: Border.all(color: accent.withAlpha(90)),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Text(
      AppConfig.categoryName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: accent,
        fontSize: compact ? 8 : 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.55,
      ),
    ),
  );
}

class _FeedArtwork extends StatelessWidget {
  const _FeedArtwork({
    required this.url,
    required this.name,
    required this.accent,
    this.compact = false,
  });

  final String url;
  final String name;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 31.0 : 38.0;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF24252B),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        name.trim().isEmpty ? 'F1' : name.trim().substring(0, 1).toUpperCase(),
        style: TextStyle(
          color: accent,
          fontSize: compact ? 12 : 14,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent.withAlpha(180), size: 28),
          const SizedBox(height: 9),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _text,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 10, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    ),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      color: _muted,
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.55,
    ),
  );
}

class _PulseDot extends StatelessWidget {
  const _PulseDot({required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(color: color.withAlpha(115), blurRadius: 10, spreadRadius: 1),
      ],
    ),
  );
}

class _TinyDot extends StatelessWidget {
  const _TinyDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _FreeF1Mark extends StatelessWidget {
  const _FreeF1Mark({required this.color, this.size = 32});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _FreeF1MarkPainter(color)),
  );
}

class _FreeF1MarkPainter extends CustomPainter {
  const _FreeF1MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = color;
    final left = Path()
      ..moveTo(2, 17.5)
      ..lineTo(7.5, 6.5)
      ..lineTo(12.7, 6.5)
      ..lineTo(10.7, 10.5)
      ..lineTo(15.3, 10.5)
      ..lineTo(13.7, 13.7)
      ..lineTo(8.9, 13.7)
      ..lineTo(7.2, 17.5)
      ..close();
    final right = Path()
      ..moveTo(14.5, 6.5)
      ..lineTo(22, 6.5)
      ..lineTo(20.3, 9.9)
      ..lineTo(12.8, 9.9)
      ..close();
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint..color = color.withAlpha(190));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FreeF1MarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _CockpitBackdrop extends StatelessWidget {
  const _CockpitBackdrop();

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const ColoredBox(color: _ink),
      Positioned(
        top: -330,
        right: -220,
        child: Container(
          width: 770,
          height: 770,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [Color(0x1FE10600), Color(0x00E10600)],
            ),
          ),
        ),
      ),
      Positioned(
        top: 250,
        left: -400,
        child: Container(
          width: 760,
          height: 760,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [Color(0x0CFFFFFF), Color(0x00FFFFFF)],
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(child: CustomPaint(painter: _SpeedLinePainter())),
      ),
    ],
  );
}

class _SpeedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x06FFFFFF)
      ..strokeWidth = 1;
    for (var i = 0; i < 9; i++) {
      final y = size.height * (0.14 + i * 0.095);
      canvas.drawLine(
        Offset(size.width * 0.72, y),
        Offset(size.width, y - 12),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
