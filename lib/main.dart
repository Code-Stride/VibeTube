import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'providers/app_provider.dart';
import 'providers/mini_player_controller.dart';
import 'screens/home_screen.dart';
import 'utils/theme.dart';
import 'widgets/mini_player_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final provider = AppProvider();
  await provider.init();
  AppTheme.applySystemUi(provider.isDarkMode);

  // Android 13+ media notification permission (best-effort)
  try {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  } catch (_) {}

  runApp(VibeTubeApp(provider: provider));
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
