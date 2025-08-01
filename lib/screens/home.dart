import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/screens/about.dart';
import 'package:revengi/screens/ollama_screen.dart';
import 'package:revengi/utils/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:revengi/utils/dio.dart';
import 'package:revengi/screens/user.dart';
import 'package:revengi/utils/cards.dart';
import 'package:revengi/screens/mthook/mthook.dart';
import 'package:revengi/screens/blutter/blutter.dart';
import 'package:revengi/screens/dexrepair/dexrepair.dart';
import 'package:revengi/utils/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:revengi/screens/smali_grammar.dart';
import 'package:revengi/screens/profile_screen.dart';
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
  // Nah, that's users choice, not ours
  bool checkUpdate = false;
  String currentVersion = "1.2.2";
  bool isUpdateAvailable = false;

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
  }

  void _showUpdateDialog() {
    showAdaptiveDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog.adaptive(
          title: Text(AppLocalizations.of(context)!.updateAvailable),
          content: Text(AppLocalizations.of(context)!.updateAvailableMessage),
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

  Future<void> _handleLogout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    await prefs.remove('apiKey');
    await prefs.setBool('isLoggedIn', false);
    dio.options.headers.remove('X-API-Key');

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  Future<void> _showSmaliGrammarDialog(BuildContext context) async {
    if (context.mounted) {
      await showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Row(
                children: [
                  Text(AppLocalizations.of(context)!.smaliGrammar),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                height: MediaQuery.of(context).size.height * 0.8,
                child: const SmaliInstructionDialog(),
              ),
            ),
      );
    }
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
                    // Navigate to the battery optimization settings
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

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final languageCode =
        context.watch<LanguageProvider>().locale.languageCode.toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color:
                    Brightness.dark == Theme.of(context).brightness
                        ? Colors.black
                        : Colors.white,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    Theme.of(context).brightness == Brightness.dark
                        ? 'assets/dark_splash.png'
                        : 'assets/light_splash.png',
                    height: 90,
                  ),
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final brightness = Theme.of(context).brightness;
                      return Text(
                        localizations.appTitle,
                        style: TextStyle(
                          color:
                              brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                          fontSize: 24,
                        ),
                      );
                    },
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
                    context.watch<ThemeProvider>().themeMode == ThemeMode.system
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
                  onTap: () {
                    context.read<ThemeProvider>().toggleTheme();
                  },
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
                                          _getLanguageName(locale.languageCode),
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
              ],
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.code),
              title: Text(localizations.smaliGrammar),
              onTap: () {
                Navigator.pop(context);
                _showSmaliGrammarDialog(context);
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
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OllamaChatScreen()),
          );
        },
        backgroundColor:
            Brightness.dark == Theme.of(context).brightness
                ? Colors.black
                : Colors.white,
        child: Icon(Icons.chat, color: Theme.of(context).colorScheme.primary),
      ),
      floatingActionButtonAnimator: FloatingActionButtonAnimator.scaling,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.2,
              mainAxisExtent: 170,
            ),
            itemCount: 6,
            itemBuilder: (context, index) {
              switch (index) {
                case 0:
                  return AnalysisCard(
                    title: localizations.jniAnalysis,
                    icon: Icons.android,
                    description: localizations.jniAnalysisDesc,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const JniAnalysisScreen(),
                          ),
                        ),
                  );
                case 1:
                  return AnalysisCard(
                    title: localizations.flutterAnalysis,
                    icon: Icons.flutter_dash,
                    description: localizations.flutterAnalysisDesc,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FlutterAnalysisScreen(),
                          ),
                        ),
                  );
                case 2:
                  return AnalysisCard(
                    title: localizations.blutter,
                    icon: Icons.build,
                    description: localizations.blutterDesc,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const BlutterAnalysisScreen(),
                          ),
                        ),
                  );
                case 3:
                  return AnalysisCard(
                    title: localizations.mtHook,
                    icon: Icons.book,
                    description: localizations.mtHookDesc,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MTHookAnalysisScreen(),
                          ),
                        ),
                  );
                case 4:
                  return AnalysisCard(
                    title: localizations.dexRepair,
                    icon: Icons.auto_fix_high,
                    description: localizations.dexRepairDesc,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DexRepairScreen(),
                          ),
                        ),
                  );
                case 5:
                  return AnalysisCard(
                    title: localizations.apksToApk,
                    icon: Icons.merge_type,
                    description: localizations.mergeSplitApks,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SplitApksMergerScreen(),
                          ),
                        ),
                  );
                default:
                  return const SizedBox.shrink();
              }
            },
          );
        },
      ),
    );
  }
}
