import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, SystemNavigator;
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/screens/about.dart';
import 'package:revengi/screens/extract_apk.dart';
import 'package:revengi/screens/ollama.dart';
import 'package:revengi/utils/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:revengi/utils/dio.dart';
import 'package:revengi/utils/cards.dart';
import 'package:revengi/screens/mthook/mthook.dart';
import 'package:revengi/screens/blutter/blutter.dart';
import 'package:revengi/screens/dexrepair/dexrepair.dart';
import 'package:revengi/utils/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:revengi/screens/smalig.dart';
import 'package:revengi/screens/profile.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:revengi/screens/jni_analysis.dart';
import 'package:revengi/screens/flutter_analysis.dart';
import 'package:revengi/screens/splitsmerger/splitsmerger.dart';
import 'package:revengi/utils/language_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool checkUpdate = false;
  String currentVersion = "1.2.5-bugfix";
  bool isUpdateAvailable = false;
  DateTime? _lastPressedAt;
  bool isDrawerOpen = false;

  @override
  void initState() {
    super.initState();
    addLicenses();
    if (!isWeb() && isAndroid()) _initializePrefs();
    if (!isWeb() && isAndroid()) _requestPermissions();
  }

  Future<void> _initializePrefs() async {
    await _getUpdatePrefs();
    await checkForUpdate();
    if (isUpdateAvailable && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showUpdateDialog();
      });
    }
  }

  Future<void> checkForUpdate() async {
    if (!checkUpdate) return;
    try {
      final response = await dio.get(
        'https://api.github.com/repos/RevEngiSquad/revengi-app/releases/latest',
      );
      if (response.statusCode == 200) {
        final latestVersion = response.data['tag_name'].replaceAll('v', '');
        if (latestVersion != currentVersion) {
          setState(() {
            isUpdateAvailable = true;
          });
        }
      }
    } catch (_) {}
  }

  void _showUpdateDialog() {
    showAdaptiveDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog.adaptive(
          title: Text(AppLocalizations.of(context)!.updateAvailable),
          content: Text(AppLocalizations.of(context)!.updateAvailableMessage),
          actionsPadding: const EdgeInsets.all(8),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context)!.later),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(AppLocalizations.of(context)!.update),
              onPressed: () {
                launchUrl(Uri.parse('https://revengi.in/downloads'));
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveUpdatePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('checkUpdate', checkUpdate);
  }

  Future<void> _getUpdatePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      checkUpdate = prefs.getBool('checkUpdate') ?? false;
    });
  }

  void addLicenses() {
    final licenses = {
      'revengi': 'assets/licenses/revengi.txt',
      'sigtool': 'assets/licenses/sigtool.txt',
      'smalig': 'assets/licenses/smalig.txt',
      'blutter': 'assets/licenses/blutter.txt',
      'arsclib': 'assets/licenses/arsclib.txt',
    };

    for (var entry in licenses.entries) {
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks([
          entry.key,
        ], await rootBundle.loadString(entry.value));
      });
    }
  }

  Future<void> _requestPermissions() async {
    int sdkVersion = await DeviceInfo.getSdkVersion();
    if (sdkVersion < 29) {
      if (await Permission.storage.isGranted) {
        return;
      }

      if (await Permission.storage.isPermanentlyDenied) {
        openAppSettings();
        return;
      }

      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }
    } else {
      if (await Permission.ignoreBatteryOptimizations.isGranted) {
        return;
      }
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.batteryOptimization),
              content: Text(
                AppLocalizations.of(context)!.batteryOptimizationMessage,
              ),
              actionsPadding: const EdgeInsets.all(8),
              actions: <Widget>[
                TextButton(
                  child: Text(AppLocalizations.of(context)!.cancel),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: Text(AppLocalizations.of(context)!.ok),
                  onPressed: () async {
                    Navigator.of(context).pop();

                    await Permission.ignoreBatteryOptimizations.request();
                  },
                ),
              ],
            );
          },
        );
      }
    }
  }

  String _getLanguageName(String languageCode) {
    switch (languageCode) {
      case 'en':
        return 'English';
      case 'es':
        return 'Español';
      case 'ar':
        return 'العربية';
      case 'af':
        return 'Afrikaans';
      case 'ca':
        return 'Català';
      case 'cs':
        return 'Čeština';
      case 'da':
        return 'Dansk';
      case 'de':
        return 'Deutsch';
      case 'el':
        return 'Ελληνικά';
      case 'fi':
        return 'Suomi';
      case 'fr':
        return 'Français';
      case 'he':
        return 'עברית';
      case 'hi':
        return 'हिन्दी';
      case 'hu':
        return 'Magyar';
      case 'it':
        return 'Italiano';
      case 'ja':
        return '日本語';
      case 'ko':
        return '한국어';
      case 'nl':
        return 'Nederlands';
      case 'no':
        return 'Norsk';
      case 'pl':
        return 'Polski';
      case 'pt':
        return 'Português';
      case 'ro':
        return 'Română';
      case 'ru':
        return 'Русский';
      case 'sr':
        return 'Српски';
      case 'sv':
        return 'Svenska';
      case 'tr':
        return 'Türkçe';
      case 'uk':
        return 'Українська';
      case 'vi':
        return 'Tiếng Việt';
      case 'zh':
        return '中文';
      default:
        return languageCode.toUpperCase();
    }
  }

  void _onPopInvokedWithResult(bool didPop, dynamic result) {
    if (didPop) return;
    if (isDrawerOpen) {
      Navigator.of(context).pop();
      return;
    }
    final now = DateTime.now();
    if (_lastPressedAt == null ||
        now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
      _lastPressedAt = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pressBackAgainToExit),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final languageCode =
        context.watch<LanguageProvider>().locale.languageCode.toUpperCase();
    final theme = Theme.of(context);

    final analysisTools = [
      ModernFeatureCard(
        title: localizations.jniAnalysis,
        subtitle: localizations.jniAnalysisDesc,
        icon: Icons.android,
        color: const Color(0xFF10B981),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const JniAnalysisScreen(),
              ),
            ),
      ),
      ModernFeatureCard(
        title: localizations.flutterAnalysis,
        subtitle: localizations.flutterAnalysisDesc,
        icon: Icons.flutter_dash,
        color: const Color(0xFF3B82F6),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const FlutterAnalysisScreen(),
              ),
            ),
      ),
      ModernFeatureCard(
        title: localizations.blutter,
        subtitle: localizations.blutterDesc,
        icon: Icons.build,
        color: const Color(0xFFF59E0B),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BlutterAnalysisScreen(),
              ),
            ),
      ),
      ModernFeatureCard(
        title: localizations.mtHook,
        subtitle: localizations.mtHookDesc,
        icon: Icons.book,
        color: const Color(0xFF8B5CF6),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MTHookAnalysisScreen(),
              ),
            ),
      ),
    ];

    final utilityTools = [
      ModernToolTile(
        title: localizations.dexRepair,
        icon: Icons.auto_fix_high,
        color: const Color(0xFFEC4899),
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const DexRepairScreen()),
            ),
      ),
      if (isWeb() || !isIOS())
        ModernToolTile(
          title: localizations.apksToApk,
          icon: Icons.merge_type,
          color: const Color(0xFF6366F1),
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SplitApksMergerScreen(),
                ),
              ),
        ),
      if (!isWeb() && isAndroid())
        ModernToolTile(
          title: localizations.extractApk,
          icon: Icons.layers,
          color: const Color(0xFF14B8A6),
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ExtractApkScreen(),
                ),
              ),
        ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Scaffold(
        onDrawerChanged: (isOpened) => setState(() => isDrawerOpen = isOpened),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primaryContainer,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Image.asset(
                        'assets/${theme.brightness == Brightness.dark ? "dark" : "light"}_splash.png',
                        height: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      localizations.appTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              ExpansionTile(
                leading: const Icon(Icons.settings),
                title: Text(localizations.preferences),
                children: [
                  ListTile(
                    leading: Icon(
                      context.watch<ThemeProvider>().themeMode ==
                              ThemeMode.system
                          ? Icons.brightness_auto
                          : context.watch<ThemeProvider>().themeMode ==
                              ThemeMode.light
                          ? Icons.light_mode
                          : Icons.dark_mode,
                    ),
                    title: Text(
                      '${localizations.theme}: ${context.watch<ThemeProvider>().themeMode == ThemeMode.system
                          ? 'System'
                          : context.watch<ThemeProvider>().themeMode == ThemeMode.light
                          ? 'Light'
                          : 'Dark'}',
                    ),
                    onTap: () => context.read<ThemeProvider>().toggleTheme(),
                  ),
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(localizations.language(languageCode)),
                    onTap: () {
                      showDialog(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: Text(localizations.selectLanguage),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children:
                                      AppLocalizations.supportedLocales.map((
                                        locale,
                                      ) {
                                        return ListTile(
                                          title: Text(
                                            _getLanguageName(
                                              locale.languageCode,
                                            ),
                                          ),
                                          onTap: () {
                                            context
                                                .read<LanguageProvider>()
                                                .setLocale(locale);
                                            Navigator.pop(context);
                                          },
                                        );
                                      }).toList(),
                                ),
                              ),
                            ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(localizations.ollama_api_url),
                    onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      if (!context.mounted) return;
                      showDialog(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: Text(localizations.ollama_api_url),
                              content: TextField(
                                controller: TextEditingController(
                                  text:
                                      prefs.getString('ollamaBaseUrl') ??
                                      'http://localhost:11434/api',
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Enter API URL',
                                ),
                                onSubmitted: (value) async {
                                  await prefs.setString('ollamaBaseUrl', value);
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(localizations.cancel),
                                ),
                                TextButton(
                                  onPressed: () {
                                    prefs.remove('ollamaBaseUrl');
                                    Navigator.pop(context);
                                  },
                                  child: Text(localizations.reset),
                                ),
                              ],
                            ),
                      );
                    },
                  ),
                  ...(!isWeb()
                      ? [
                        SwitchListTile.adaptive(
                          secondary: const Icon(Icons.update),
                          value: checkUpdate,
                          title: Text(localizations.checkForUpdate),
                          onChanged: (value) {
                            setState(() {
                              checkUpdate = value;
                            });
                            _saveUpdatePrefs();
                          },
                        ),
                      ]
                      : []),
                  ListTile(
                    leading: const Icon(Icons.bug_report),
                    title: FutureBuilder<bool>(
                      future: SharedPreferences.getInstance().then((prefs) {
                        return prefs.getBool('logEnabled') ?? false;
                      }),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return Text(
                            snapshot.data! ? 'Disable Logs' : 'Enable Logs',
                          );
                        } else {
                          return const Text('Enable Logs');
                        }
                      },
                    ),
                    onTap: () {
                      final prefs = SharedPreferences.getInstance();
                      prefs.then((prefs) {
                        final logEnabled = prefs.getBool('logEnabled') ?? false;
                        prefs.setBool('logEnabled', !logEnabled);
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Restart the app to apply changes'),
                          ),
                        );
                      });
                    },
                  ),
                ],
              ),

              ListTile(
                leading: const Icon(Icons.code),
                title: Text(localizations.smaliGrammar),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SmaliGrammarScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(localizations.profile),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info),
                title: Text(localizations.about),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) =>
                              AboutScreen(currentVersion: currentVersion),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const OllamaChatScreen()),
            );
          },
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('AI Chat'),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
        ),
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              stretch: true,
              backgroundColor: theme.scaffoldBackgroundColor,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  localizations.appTitle,
                  style: TextStyle(
                    color: theme.textTheme.titleLarge?.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: true,
                titlePadding: const EdgeInsets.only(bottom: 16),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary.withValues(alpha: 0.15),
                            theme.scaffoldBackgroundColor,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -20,
                      top: -20,
                      child: Opacity(
                        opacity: 0.1,
                        child: Icon(
                          Icons.build_circle_outlined,
                          size: 200,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Text(
                  'Analysis Tools',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.titleMedium?.color?.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.0,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => analysisTools[index],
                  childCount: analysisTools.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 12),
                child: Text(
                  'Utilities',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.textTheme.titleMedium?.color?.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => utilityTools[index],
                  childCount: utilityTools.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
