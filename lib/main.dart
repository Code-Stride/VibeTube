import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/audio_helper.dart';
import 'providers/app_provider.dart';
import 'providers/mini_player_controller.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'utils/theme.dart';
import 'widgets/mini_player_bar.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final provider = AppProvider();
  await provider.init();
  AppTheme.applySystemUi(provider.isDarkMode);

  // Background / headset / lock-screen audio routing
  await AudioHelper.configure();

  // Android 13+ media notification permission (best-effort)
  try {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  } catch (_) {}

  // Wire up deep link handler (YouTube URLs from other apps)
  _setupDeepLinkHandler();

  runApp(VibeTubeApp(provider: provider));
}

/// Marks routes we pushed for a deep link, so a second link replaces the first
/// instead of stacking another player on top of it.
const String _deepLinkRouteName = 'player/deeplink';
const RouteSettings _playerRouteSettings =
    RouteSettings(name: _deepLinkRouteName);

/// Tracks whether a deep-linked player is currently the top route.
///
/// Without this, tapping three YouTube links in a row pushes three
/// PlayerScreens — each owning its own VideoPlayerController.
class _DeepLinkRouteObserver extends NavigatorObserver {
  bool topIsDeepLinkPlayer = false;

  void _update(Route<dynamic>? top) {
    topIsDeepLinkPlayer = top?.settings.name == _deepLinkRouteName;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _update(newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _update(previousRoute);
}

final _DeepLinkRouteObserver deepLinkRouteObserver = _DeepLinkRouteObserver();

void _setupDeepLinkHandler() {
  // Dedicated channel so we don't clash with the native player command channel.
  // Native buffers any link that arrives before this handler exists and
  // replays it when we announce 'ready' below.
  const deepChannel = MethodChannel('com.blazenxt.vibetube/deeplink');
  deepChannel.setMethodCallHandler((call) async {
    if (call.method == 'onDeepLink' && call.arguments is String) {
      final videoId = (call.arguments as String).trim();
      if (videoId.isEmpty) return;
      // Use the navigator state directly — currentContext can belong to a
      // widget that is not below the Navigator once routes are pushed.
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      // Replace an existing player rather than stacking a second one: each
      // PlayerScreen owns a VideoPlayerController, so stacking them means
      // several decoders (and audio tracks) alive at once.
      if (deepLinkRouteObserver.topIsDeepLinkPlayer) {
        nav.pushReplacement(
          MaterialPageRoute(
            settings: _playerRouteSettings,
            builder: (_) => PlayerScreen(videoId: videoId),
          ),
        );
      } else {
        nav.push(
          MaterialPageRoute(
            settings: _playerRouteSettings,
            builder: (_) => PlayerScreen(videoId: videoId),
          ),
        );
      }
    }
  });
  // Tell native we're listening; it flushes any cold-start link now.
  deepChannel.invokeMethod('ready').catchError((_) => null);
}

class VibeTubeApp extends StatelessWidget {
  final AppProvider provider;
  const VibeTubeApp({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // create (not .value) so the provider owns it and AppProvider.dispose()
        // — which closes the HTTP clients — is actually reached at teardown.
        ChangeNotifierProvider<AppProvider>(create: (_) => provider),
        ChangeNotifierProvider(create: (_) => MiniPlayerController()),
      ],
      child: Builder(
        builder: (context) {
          // select(), not watch(): AppProvider notifies on feed loads and on
          // every throttled download-progress tick. Rebuilding MaterialApp (and
          // issuing a SystemChrome platform call) for those was pure waste.
          // applySystemUi now runs in AppProvider.toggleDarkMode, where the
          // value actually changes.
          final isDark = context.select<AppProvider, bool>((p) => p.isDarkMode);
          return MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [deepLinkRouteObserver],
            title: 'VibeTube',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            // Global mini player for routes outside main shell (e.g. standalone search)
            builder: (context, child) {
              return Builder(
                builder: (context) {
                  final showOverlay = context.select<MiniPlayerController, bool>(
                      (m) => m.showMiniBar && m.useGlobalOverlay);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      child ?? const SizedBox.shrink(),
                      // Only when mini is showing AND we're not inside main shell's own bar
                      // Main shell draws its own bar above bottom nav via HomeScreen.
                      // For other routes (standalone search), show floating mini at bottom.
                      if (showOverlay)
                        const Align(
                          alignment: Alignment.bottomCenter,
                          child: MiniPlayerBar(),
                        ),
                    ],
                  );
                },
              );
            },
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
