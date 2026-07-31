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
const _deepLinkChannel = MethodChannel('com.blazenxt.vibetube/player');

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

void _setupDeepLinkHandler() {
  // The native side also registers a handler on this channel for player commands.
  // We use a separate method name 'onDeepLink' that native invokes when a YT URL is opened.
  // Since the native side sets its own handler in configureFlutterEngine, we need
  // to intercept 'onDeepLink' calls. We use a secondary channel to avoid conflicts.
  const deepChannel = MethodChannel('com.blazenxt.vibetube/deeplink');
  deepChannel.setMethodCallHandler((call) async {
    if (call.method == 'onDeepLink' && call.arguments is String) {
      final videoId = call.arguments as String;
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        Navigator.of(ctx).push(
          MaterialPageRoute(
            builder: (_) => PlayerScreen(videoId: videoId),
          ),
        );
      }
    }
  });
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
