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

  // Background / headset / lock-screen audio routing
  await AudioHelper.configure();

  // Wire up deep link handler (YouTube URLs from other apps)
  _setupDeepLinkHandler();

  runApp(VibeTubeApp(
    provider: provider,
    mini: mini,
    routeObserver: MiniPlayerRouteObserver(mini),
  ));
}

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
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route) && _depth > 0) {
      _depth--;
      _sync();
    }
    super.didPop(route, previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route) && _depth > 0) {
      _depth--;
      _sync();
    }
    super.didRemove(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    // Depth is unchanged by a replacement, but resync in case the kinds differ.
    _sync();
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

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
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(videoId: videoId),
        ),
      );
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
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider.value(value: mini),
      ],
      child: Consumer<AppProvider>(
        builder: (context, p, _) {
          AppTheme.applySystemUi(p.isDarkMode);
          return MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [routeObserver],
            title: 'VibeTube',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: p.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            // Global mini player for routes outside main shell (e.g. standalone search)
            builder: (context, child) {
              return Consumer<MiniPlayerController>(
                builder: (context, mini, _) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      child ?? const SizedBox.shrink(),
                      // Only when mini is showing AND we're not inside main shell's own bar
                      // Main shell draws its own bar above bottom nav via HomeScreen.
                      // For other routes (standalone search), show floating mini at bottom.
                      if (mini.showMiniBar && mini.useGlobalOverlay)
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
