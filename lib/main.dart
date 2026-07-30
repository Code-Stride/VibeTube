import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final provider = AppProvider();
  await provider.init();
  AppTheme.applySystemUi(provider.isDarkMode);

  runApp(VibeTubeApp(provider: provider));
}

class VibeTubeApp extends StatelessWidget {
  final AppProvider provider;
  const VibeTubeApp({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: provider,
      child: Consumer<AppProvider>(
        builder: (context, p, _) {
          AppTheme.applySystemUi(p.isDarkMode);
          return MaterialApp(
            title: 'VibeTube',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: p.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
