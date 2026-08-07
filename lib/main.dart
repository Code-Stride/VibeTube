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

  // Install the Dart-side deep link handler before the first frame so nothing
  // can arrive unhandled, but do not tell native we are ready yet — see below.
  _setupDeepLinkHandler();

  runApp(VibeTubeApp(provider: provider));

  // Everything that must not block the first frame runs after it.
  //
  // The notification permission request in particular used to be awaited
  // *before* runApp: request() only completes once the user answers the system
  // dialog, so the app sat on the native splash until then — and stayed there
  // forever if the dialog was suppressed (OEM policy, restricted profile).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _announceDeepLinkReady();
    _requestNotificationPermission();
  });
}

/// Android 13+ media notification permission (best-effort, never blocking).
Future<void> _requestNotificationPermission() async {
  try {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  } catch (_) {}
}

/// Dedicated channel so we don't clash with the native player command channel.
/// Native buffers any link that arrives before we announce 'ready' and replays
/// it at that point.
const MethodChannel _deepLinkChannel = MethodChannel(
  'com.blazenxt.vibetube/deeplink',
);

String? _pendingDeepLinkId;
int _deepLinkRetries = 0;

void _setupDeepLinkHandler() {
  _deepLinkChannel.setMethodCallHandler((call) async {
    if (call.method == 'onDeepLink' && call.arguments is String) {
      final videoId = (call.arguments as String).trim();
      if (videoId.isEmpty) return;
      _openDeepLink(videoId);
    }
  });
}

/// Tell native we're listening; it flushes any cold-start link now.
///
/// Deliberately called after the first frame: native replays the buffered link
/// synchronously on receiving this, and before the first frame
/// `navigatorKey.currentState` is still null, so the link was silently dropped
/// by the `?.` below.
void _announceDeepLinkReady() {
  _deepLinkChannel.invokeMethod('ready').catchError((_) => null);
}

void _openDeepLink(String videoId) {
  // Use the navigator state directly — currentContext can belong to a widget
  // that is not below the Navigator once routes are pushed.
  final nav = navigatorKey.currentState;
  if (nav == null) {
    // Navigator not mounted yet. Buffer and retry on the next frame rather
    // than dropping the link. Capped so a genuinely broken navigator cannot
    // spin frame callbacks forever.
    if (_deepLinkRetries >= 10) return;
    _deepLinkRetries++;
    _pendingDeepLinkId = videoId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = _pendingDeepLinkId;
      _pendingDeepLinkId = null;
      if (pending != null) _openDeepLink(pending);
    });
    return;
  }
  _deepLinkRetries = 0;
  nav.push(MaterialPageRoute(builder: (_) => PlayerScreen(videoId: videoId)));
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
