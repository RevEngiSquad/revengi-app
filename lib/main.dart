import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:revengi/screens/ollama_screen.dart';
import 'package:revengi/screens/profile_screen.dart';
import 'package:revengi/screens/uninstall_screen.dart';
import 'package:revengi/screens/splash.dart';
import 'package:revengi/utils/dio.dart';
import 'package:revengi/utils/platform.dart';
import 'package:revengi/utils/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDio();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final QuickActions quickActions;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    quickActions = const QuickActions();
    if (!isWeb() && (isAndroid() || isIOS())) {
      _setupQuickActions();
    }
  }

  void _setupQuickActions() {
    quickActions.setShortcutItems(<ShortcutItem>[
      const ShortcutItem(
        type: 'action_uninstall',
        localizedTitle: "You'll regret that decision",
        icon: 'emoji_uninstall',
      ),
      const ShortcutItem(
        type: 'action_profile',
        localizedTitle: 'Profile',
        icon: 'icon_profile',
      ),
      const ShortcutItem(type: 'action_aichat', localizedTitle: 'AI Chat'),
    ]);
    quickActions.initialize((String shortcutType) {
      if (shortcutType == 'action_profile') {
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
      } else if (shortcutType == 'action_uninstall') {
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const UninstallScreen()),
        );
      } else if (shortcutType == 'action_aichat') {
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const OllamaChatScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'RevEngi App',
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: context.watch<ThemeProvider>().themeMode,
      home: const SplashScreen(),
    );
  }
}
