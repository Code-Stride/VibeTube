import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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

  // Owned here (not created inside the widget tree) so the route observer
  // below can talk to the same instance.
  final mini = MiniPlayerController();
  // Held globally so the deep-link handler can ask what the top route is.
  final routeObserver = MiniPlayerRouteObserver(mini);
  miniPlayerRouteObserver = routeObserver;

  // Background / headset / lock-screen audio routing
  await AudioHelper.configure();

  // Wire up deep link handler (YouTube URLs from other apps)
  _setupDeepLinkHandler();

  runApp(VibeTubeApp(
    provider: provider,
    mini: mini,
    routeObserver: routeObserver,
  ));
}

/// The live route observer, set in [main].
///
/// The deep-link handler is a top-level function with no BuildContext, so it
/// needs a way to ask whether the current top route is already a deep-linked
/// player.
MiniPlayerRouteObserver? miniPlayerRouteObserver;

/// Keeps [MiniPlayerController.useGlobalOverlay] in sync with the navigation
/// stack.
///
/// The main shell (HomeScreen) draws its own mini bar above the bottom nav.
/// Any route pushed on top of it — standalone search, a settings sub-page —
/// covers that bar, so the floating overlay in [VibeTubeApp.build] has to take
/// over. Previously the flag was only ever set to `true` in
/// `HomeScreen.dispose()`, which never runs because HomeScreen *is*
/// `MaterialApp.home`, so the overlay was unreachable dead code.
class MiniPlayerRouteObserver extends NavigatorObserver {
  MiniPlayerRouteObserver(this.mini);

  final MiniPlayerController mini;
  int _depth = 0;

  /// Whether the route on top was pushed by a deep link.
  ///
  /// Without this, tapping three YouTube links in a row pushes three
  /// PlayerScreens — each owning its own VideoPlayerController.
  bool topIsDeepLinkPlayer = false;

  void _trackTop(Route<dynamic>? top) {
    topIsDeepLinkPlayer = top?.settings.name == deepLinkRouteName;
  }

  void _sync() {
    final wantOverlay = _depth > 0;
    if (mini.useGlobalOverlay == wantOverlay) return;
    // Observer callbacks can fire mid-frame; notifying listeners there would
    // trigger "setState() called during build".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      mini.setUseGlobalOverlay(wantOverlay);
    });
  }

  bool _counts(Route<dynamic>? route) => route is PageRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route) && previousRoute != null) {
      _depth++;
      _sync();
    }
    _trackTop(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route) && _depth > 0) {
      _depth--;
      _sync();
    }
    _trackTop(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route) && _depth > 0) {
      _depth--;
      _sync();
    }
    _trackTop(previousRoute);
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // Depth is unchanged by a replacement, but resync in case the kinds differ.
    _sync();
    _trackTop(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

/// Route name for players opened from a deep link, so a second link replaces
/// the first instead of stacking another player (and decoder) on top of it.
const String deepLinkRouteName = 'player/deeplink';

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
      final route = MaterialPageRoute<void>(
        settings: const RouteSettings(name: deepLinkRouteName),
        builder: (_) => PlayerScreen(videoId: videoId),
      );
      // Replace an existing deep-linked player rather than stacking a second
      // one: each PlayerScreen owns a VideoPlayerController.
      if (miniPlayerRouteObserver?.topIsDeepLinkPlayer == true) {
        nav.pushReplacement(route);
      } else {
        nav.push(route);
      }
    }
  });
  // Tell native we're listening; it flushes any cold-start link now.
  deepChannel.invokeMethod('ready').catchError((_) => null);
}

class VibeTubeApp extends StatelessWidget {
  final AppProvider provider;
  final MiniPlayerController mini;
  final MiniPlayerRouteObserver routeObserver;
  const VibeTubeApp({
    super.key,
    required this.provider,
    required this.mini,
    required this.routeObserver,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // create (not .value) so the providers are owned here and their
        // dispose() — which closes the HTTP clients and the video controller —
        // is actually reached at teardown.
        ChangeNotifierProvider<AppProvider>(create: (_) => provider),
        ChangeNotifierProvider<MiniPlayerController>(create: (_) => mini),
      ],
      child: Builder(
        builder: (context) {
          // select(), not watch(): AppProvider notifies on feed loads and on
          // every throttled download-progress tick. Rebuilding MaterialApp —
          // and issuing a SystemChrome platform call — for those was waste.
          // applySystemUi now runs in AppProvider.toggleDarkMode, where the
          // value actually changes.
          final isDark = context.select<AppProvider, bool>((p) => p.isDarkMode);
          return MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [routeObserver],
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
