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

  // Android 13+ media notification permission (best-effort).
  // Without it the foreground MediaSession cannot show a notification, so
  // background playback and lock-screen controls silently do nothing. We
  // record the outcome so Settings can explain that instead of leaving the
  // user to wonder why the feature "does not work".
  try {
    var status = await Permission.notification.status;
    if (!status.isGranted) {
      status = await Permission.notification.request();
    }
    provider.notificationsAllowed = status.isGranted;
  } catch (_) {
    provider.notificationsAllowed = true; // non-Android / unknown: assume ok
  }

  // Wire up deep link handler (YouTube URLs from other apps)
  _setupDeepLinkHandler();

  runApp(VibeTubeApp(provider: provider));
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
  const VibeTubeApp({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(create: (_) => MiniPlayerController()),
      ],
      child: Consumer<AppProvider>(
        builder: (context, p, _) {
          AppTheme.applySystemUi(p.isDarkMode);
          return MaterialApp(
            navigatorKey: navigatorKey,
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
