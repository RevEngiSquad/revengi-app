import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/sign_info.dart';
import 'package:intl/intl.dart';
import 'package:l/l.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ExtractApkScreen extends StatefulWidget {
  const ExtractApkScreen({super.key});

  @override
  State<ExtractApkScreen> createState() => _ExtractApkScreenState();
}

class _ExtractApkScreenState extends State<ExtractApkScreen>
    with WidgetsBindingObserver {
  List<AppInfo> _apps = [];
  List<AppInfo> _filteredApps = [];
  bool _excludeSystemApps = true;
  bool _isLoading = false;
  bool _isSearching = false;
  bool upperCase = true;
  bool addColon = false;
  final Set<int> _selectedApps = {};
  bool _isMultiSelect = false;
  final TextEditingController _searchController = TextEditingController();
  String? _uniPkgName;
  bool _autoRefresh = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPrefs();
    _loadApps();
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_autoRefresh) {
        _loadApps();
      } else if (_uniPkgName != null) {
        _checkUninstalledApp(_uniPkgName!);
        _uniPkgName = null;
      }
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoRefresh = prefs.getBool('autoRefresh') ?? false;
    });
  }

  Future<void> _savePrefs(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoRefresh', value);
    setState(() {
      _autoRefresh = value;
    });
  }

  Future<void> _checkUninstalledApp(String packageName) async {
    final appInfo = await InstalledApps.getAppInfo(packageName);
    if (appInfo == null) {
      setState(() {
        _apps.removeWhere((app) => app.packageName == packageName);
        _filteredApps.removeWhere((app) => app.packageName == packageName);
      });
    }
  }

  Future<(String?, String?)> _checkAppOnStore(String packageName) async {
    if (packageName.startsWith("com.termux")) {
      return ("F-Droid", 'https://f-droid.org/en/packages/$packageName');
    }
    final stores = {
      "Google Play":
          'https://play.google.com/store/apps/details?id=$packageName',
      "F-Droid": 'https://f-droid.org/en/packages/$packageName',
      "IzzyOnDroid": 'https://apt.izzysoft.de/fdroid/index/apk/$packageName',
      "RuStore":
          'https://backapi.rustore.ru/applicationData/overallInfo/$packageName',
    };

    final Dio dio = Dio();
    dio.options.validateStatus = (status) => status! < 500;

    for (var entry in stores.entries) {
      try {
        var res = await dio.head(entry.value);
        if (res.statusCode == 200) {
          return (entry.key, entry.value);
        }
      } catch (e) {
        l.e("Error checking app on store: ${entry.key} $e");
      }
    }

    return (null, null);
  }

  Future<void> _loadApps() async {
    setState(() => _isLoading = true);
    try {
      final apps = await InstalledApps.getInstalledApps(
        _excludeSystemApps,
        true,
        "",
      );
      apps.sort(
        (a, b) => b.lastUpdatedTimestamp.compareTo(a.lastUpdatedTimestamp),
      );
      setState(() {
        _apps = apps;
        _filteredApps = apps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading apps: $e')));
      }
    }
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredApps =
          _apps.where((app) {
            return app.name.toLowerCase().contains(query) ||
                app.packageName.toLowerCase().contains(query);
          }).toList();
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _filteredApps = _apps;
        FocusScope.of(context).unfocus();
      }
    });
  }

  void _toggleMultiSelect() {
    if (!mounted) return;
    setState(() {
      _isMultiSelect = !_isMultiSelect;
      if (!_isMultiSelect) {
        _selectedApps.clear();
      }
    });
  }

  void _onPopInvokedWithResult(bool didPop, dynamic result) {
    if (didPop) return;
    if (_isSearching) {
      _toggleSearch();
    } else if (_isMultiSelect) {
      _toggleMultiSelect();
    }
  }

  Future<void> _extractApk(List<AppInfo> appsToExtract) async {
    var isExtracting = true;
    var extracted = false;
    final localizations = AppLocalizations.of(context)!;
    File? outputFile;
    final dir = Directory(
      await getDownloadsDirectory().then((dir) => "$dir/apks"),
    );
    int extractedApps = 0;

    if (appsToExtract.length > 1) {
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(localizations.info),
              content: Text(
                localizations.extractMultiApkConfirm(appsToExtract.length),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(localizations.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(localizations.yes),
                ),
              ],
            ),
      );
      if (confirm != true) {
        isExtracting = false;
        return;
      } else {
        _toggleMultiSelect();
      }
    }

    try {
      if (isExtracting) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => PopScope(
                canPop: extracted,
                child: AlertDialog(
                  title: Text(localizations.extractingApk),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(),
                      SizedBox(height: 16),
                      Text(localizations.pleaseWait),
                    ],
                  ),
                ),
              ),
        );
      }

      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      for (final app in appsToExtract) {
        try {
          final isSplitApp = app.splitSourceDirs.isNotEmpty;
          final appName = app.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
          outputFile =
              isSplitApp
                  ? File('${dir.path}/${appName}_${app.versionName}.apks')
                  : File('${dir.path}/${appName}_${app.versionName}.apk');

          if (outputFile.existsSync()) {
            if (!mounted) return;
            final shouldOverwrite = await showDialog<bool>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: Text(localizations.fileExists),
                    content: Text(
                      localizations.fileExistsMsg(outputFile!.path),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(localizations.cancel),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(localizations.overwrite),
                      ),
                    ],
                  ),
            );
            if (shouldOverwrite != true) {
              continue;
            } else {
              outputFile.delete(recursive: true);
            }
          }

          if (isSplitApp) {
            final methodChannel = MethodChannel('flutter.native/helper');
            final apkPaths = [app.apkPath, ...app.splitSourceDirs];
            if (await methodChannel.invokeMethod<bool>('zipApks', {
                  'apkPaths': apkPaths,
                  'outputPath': outputFile.path,
                }) ??
                false) {
              extractedApps++;
            }
          } else {
            final apkFile = File(app.apkPath);
            await apkFile.copy(outputFile.path);
            if (outputFile.existsSync()) {
              extractedApps++;
            }
          }
        } catch (e) {
          if (e is PathAccessException) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    localizations.manualDeleteRequired(outputFile!.path),
                  ),
                  backgroundColor: Colors.yellow,
                  duration: const Duration(seconds: 5),
                ),
              );
              if (appsToExtract.length == 1) {
                return;
              } else {
                continue;
              }
            }
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localizations.apkExtractError(e.toString())),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          isExtracting = false;
          extracted = true;
        });
        Navigator.of(context).pop();
        if (outputFile != null) {
          if (extractedApps == 1) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localizations.apkExtractedMsg(outputFile.path)),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 5),
              ),
            );
          } else if (extractedApps > 1) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "$extractedApps ${localizations.apkExtractedMsg(dir.path)}",
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _extractSelectedApps() async {
    final selectedApps =
        _selectedApps.map((index) => _filteredApps[index]).toList();
    await _extractApk(selectedApps);
  }

  void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    InstalledApps.toast(AppLocalizations.of(context)!.copiedToClipboard, true);
  }

  Future<void> _rawData(List<int> rawData, String baseData) async {
    final localizations = AppLocalizations.of(context)!;

    String hexData = rawData
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');

    TextEditingController textEditingController = TextEditingController(
      text: hexData,
    );

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(localizations.rawData),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                TextField(
                  controller: textEditingController,
                  readOnly: true,
                  maxLines: null,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(localizations.copy),
              onPressed: () {
                copyToClipboard(textEditingController.text);
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(localizations.copyBase64),
              onPressed: () {
                copyToClipboard(baseData);
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(localizations.cancel),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSignInfo(SignInfo signInfo) async {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Padding(
                padding: const EdgeInsets.only(
                  right: 20.0,
                  left: 20.0,
                  top: 20.0,
                  bottom: 10.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      localizations.signInfo,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Table(
                          columnWidths: const {0: FixedColumnWidth(120)},
                          children: [
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  localizations.scheme,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        '${signInfo.verifiedSchemes}',
                                      ),
                                  child: Text(
                                    signInfo.verifiedSchemes.isNotEmpty
                                        ? signInfo.verifiedSchemes.join(" + ")
                                        : "Verified failed",
                                    style: TextStyle(
                                      color:
                                          signInfo.verifiedSchemes.isNotEmpty
                                              ? theme.colorScheme.onSurfaceVariant
                                              : theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  localizations.algorithm,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(signInfo.algorithm),
                                  child: Text(
                                    signInfo.algorithm,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  localizations.status,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        '${signInfo.verified}',
                                      ),
                                  child: Text(
                                    signInfo.verified
                                        ? "Verified${signInfo.warnings.isNotEmpty ? ' with ${signInfo.warnings.length} warnings' : ''}${signInfo.errors.isNotEmpty ? ' and ${signInfo.errors.length} errors' : ''}"
                                        : "Not Verified",
                                    style: TextStyle(
                                      color:
                                          signInfo.verified
                                              ? Colors.green
                                              : theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  localizations.createDate,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () =>
                                          copyToClipboard(signInfo.createDate),
                                  child: Text(
                                    signInfo.createDate,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  localizations.expireDate,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () =>
                                          copyToClipboard(signInfo.expireDate),
                                  child: Text(
                                    signInfo.expireDate,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  localizations.owner,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap: () => copyToClipboard(signInfo.issuer),
                                  child: Text(
                                    signInfo.issuer,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  "HASH",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        upperCase
                                            ? "0x${(int.parse(signInfo.digests.hash) & 0xFFFFFFFF).toRadixString(16).toUpperCase()} (${signInfo.digests.hash})"
                                            : "0x${(int.parse(signInfo.digests.hash) & 0xFFFFFFFF).toRadixString(16)} (${signInfo.digests.hash})",
                                      ),
                                  child: Text(
                                    upperCase
                                        ? "0x${(int.parse(signInfo.digests.hash) & 0xFFFFFFFF).toRadixString(16).toUpperCase()} (${signInfo.digests.hash})"
                                        : "0x${(int.parse(signInfo.digests.hash) & 0xFFFFFFFF).toRadixString(16)} (${signInfo.digests.hash})",
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  "CRC32",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        upperCase
                                            ? "0x${signInfo.digests.crc32.replaceFirst(RegExp('^0+'), '').toUpperCase()} (${int.parse((signInfo.digests.crc32), radix: 16)})"
                                            : "0x${signInfo.digests.crc32.replaceFirst(RegExp('^0+'), '')} (${int.parse((signInfo.digests.crc32), radix: 16)})",
                                      ),
                                  child: Text(
                                    upperCase
                                        ? "0x${signInfo.digests.crc32.replaceFirst(RegExp('^0+'), '').toUpperCase()} (${int.parse((signInfo.digests.crc32), radix: 16)})"
                                        : "0x${signInfo.digests.crc32.replaceFirst(RegExp('^0+'), '')} (${int.parse((signInfo.digests.crc32), radix: 16)})",
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  "MD5",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        upperCase
                                            ? addColon
                                                ? _formatWithColon(
                                                  signInfo.digests.md5
                                                      .toUpperCase(),
                                                )
                                                : signInfo.digests.md5
                                                    .toUpperCase()
                                            : addColon
                                            ? _formatWithColon(
                                              signInfo.digests.md5,
                                            )
                                            : signInfo.digests.md5,
                                      ),
                                  child: Text(
                                    upperCase
                                        ? addColon
                                            ? _formatWithColon(
                                              signInfo.digests.md5
                                                  .toUpperCase(),
                                            )
                                            : signInfo.digests.md5.toUpperCase()
                                        : addColon
                                        ? _formatWithColon(signInfo.digests.md5)
                                        : signInfo.digests.md5,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  "SHA1",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        upperCase
                                            ? addColon
                                                ? _formatWithColon(
                                                  signInfo.digests.sha1
                                                      .toUpperCase(),
                                                )
                                                : signInfo.digests.sha1
                                                    .toUpperCase()
                                            : addColon
                                            ? _formatWithColon(
                                              signInfo.digests.sha1,
                                            )
                                            : signInfo.digests.sha1,
                                      ),
                                  child: Text(
                                    upperCase
                                        ? addColon
                                            ? _formatWithColon(
                                              signInfo.digests.sha1
                                                  .toUpperCase(),
                                            )
                                            : signInfo.digests.sha1
                                                .toUpperCase()
                                        : addColon
                                        ? _formatWithColon(
                                          signInfo.digests.sha1,
                                        )
                                        : signInfo.digests.sha1,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  "SHA256",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        upperCase
                                            ? addColon
                                                ? _formatWithColon(
                                                  signInfo.digests.sha256
                                                      .toUpperCase(),
                                                )
                                                : signInfo.digests.sha256
                                                    .toUpperCase()
                                            : addColon
                                            ? _formatWithColon(
                                              signInfo.digests.sha256,
                                            )
                                            : signInfo.digests.sha256,
                                      ),
                                  child: Text(
                                    upperCase
                                        ? addColon
                                            ? _formatWithColon(
                                              signInfo.digests.sha256
                                                  .toUpperCase(),
                                            )
                                            : signInfo.digests.sha256
                                                .toUpperCase()
                                        : addColon
                                        ? _formatWithColon(
                                          signInfo.digests.sha256,
                                        )
                                        : signInfo.digests.sha256,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  "SHA384",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        upperCase
                                            ? addColon
                                                ? _formatWithColon(
                                                  signInfo.digests.sha384
                                                      .toUpperCase(),
                                                )
                                                : signInfo.digests.sha384
                                                    .toUpperCase()
                                            : addColon
                                            ? _formatWithColon(
                                              signInfo.digests.sha384,
                                            )
                                            : signInfo.digests.sha384,
                                      ),
                                  child: Text(
                                    upperCase
                                        ? addColon
                                            ? _formatWithColon(
                                              signInfo.digests.sha384
                                                  .toUpperCase(),
                                            )
                                            : signInfo.digests.sha384
                                                .toUpperCase()
                                        : addColon
                                        ? _formatWithColon(
                                          signInfo.digests.sha384,
                                        )
                                        : signInfo.digests.sha384,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  "SHA512",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        upperCase
                                            ? addColon
                                                ? _formatWithColon(
                                                  signInfo.digests.sha512
                                                      .toUpperCase(),
                                                )
                                                : signInfo.digests.sha512
                                                    .toUpperCase()
                                            : addColon
                                            ? _formatWithColon(
                                              signInfo.digests.sha512,
                                            )
                                            : signInfo.digests.sha512,
                                      ),
                                  child: Text(
                                    upperCase
                                        ? addColon
                                            ? _formatWithColon(
                                              signInfo.digests.sha512
                                                  .toUpperCase(),
                                            )
                                            : signInfo.digests.sha512
                                                .toUpperCase()
                                        : addColon
                                        ? _formatWithColon(
                                          signInfo.digests.sha512,
                                        )
                                        : signInfo.digests.sha512,
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            TableRow(
                              children: [
                                const SizedBox(height: 8),
                                const SizedBox(height: 8),
                              ],
                            ),
                            TableRow(
                              children: [
                                Text(
                                  localizations.format,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        Text(localizations.addColon),
                                        Switch.adaptive(
                                          value: addColon,
                                          onChanged: (value) {
                                            setState(() {
                                              addColon = value;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Text(localizations.upperCase),
                                        Switch.adaptive(
                                          value: upperCase,
                                          onChanged: (value) {
                                            setState(() {
                                              upperCase = value;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            _rawData(signInfo.rawData, signInfo.baseData);
                          },
                          child: Text(
                            localizations.viewData.toUpperCase(),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: Text(
                            localizations.cancel.toUpperCase(),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatWithColon(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i += 2) {
      buffer.write(input.substring(i, i + 2));
      if (i + 2 < input.length) {
        buffer.write(':');
      }
    }
    return buffer.toString();
  }

  void _invertSelect() {
    setState(() {
      final allIndices = List.generate(_filteredApps.length, (index) => index);
      final selectedIndices = _selectedApps.toList();
      _selectedApps.clear();
      for (final index in allIndices) {
        if (!selectedIndices.contains(index)) {
          _selectedApps.add(index);
        }
      }
    });
  }

  Future<void> _showAppDetails(AppInfo app) async {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context); // Capture theme
    final GlobalKey menuKey = GlobalKey();

    List<String>? signatureSchemes;
    SignInfo? signInfo;
    String appStore = "";
    String appStoreUrl = "";
    String installer = "";

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (signatureSchemes == null) {
              Future.microtask(() async {
                final result = await InstalledApps.extractSignatureInfo(
                  app.apkPath,
                );

                if (context.mounted) {
                  setState(() {
                    signatureSchemes = result.schemes;
                    signInfo = result;
                  });
                }
                final installerResult = await InstalledApps.getAppInfo(
                  app.installer,
                );
                if (context.mounted) {
                  setState(() {
                    if (installerResult != null) {
                      installer = installerResult.name;
                    } else {
                      installer = localizations.unknown;
                    }
                  });
                }
                var (appStor, appStoreUr) = await _checkAppOnStore(
                  app.packageName,
                );
                if (context.mounted) {
                  setState(() {
                    if (appStor != null && appStoreUr != null) {
                      appStore = appStor;
                      appStoreUrl = appStoreUr;
                    } else {
                      appStore = localizations.notFound;
                      appStoreUrl = "";
                    }
                  });
                }
              });
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Padding(
                padding: const EdgeInsets.only(
                  right: 20.0,
                  left: 20.0,
                  top: 20.0,
                  bottom: 10.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (app.icon != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Image.memory(
                              app.icon!,
                              width: 40,
                              height: 40,
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => copyToClipboard(app.name),
                                child: Text(
                                  app.name,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => copyToClipboard(app.versionName),
                                child: Padding(
                                  padding: EdgeInsets.only(top: 6, bottom: 4),
                                  child: Text(
                                    app.versionName,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Table(
                      columnWidths: const {0: FixedColumnWidth(120)},
                      children: [
                        TableRow(
                          children: [
                            Text(
                              localizations.packageName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap: () => copyToClipboard(app.packageName),
                              child: Text(
                                app.packageName,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.versionCode,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard('${app.versionCode}'),
                              child: Text(
                                '${app.versionCode}',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.fileSize,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(
                                    '${(app.packageSize / (1024 * 1024)).toStringAsFixed(2)}M',
                                  ),
                              child: Text(
                                '${(app.packageSize / (1024 * 1024)).toStringAsFixed(2)}M',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.signature,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap:
                                  () =>
                                      signatureSchemes != null
                                          ? _showSignInfo(signInfo!)
                                          : null,
                              child: Text(
                                signatureSchemes != null
                                    ? signatureSchemes!.isEmpty
                                        ? "Verified failed"
                                        : signatureSchemes!.join(" + ")
                                    : "...",
                                style: TextStyle(
                                  color:
                                      signatureSchemes != null &&
                                              signatureSchemes!.isEmpty
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.dataDirectory,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap: () => copyToClipboard(app.dataDir),
                              child: Text(
                                app.dataDir,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.dataDirectory2,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(
                                    '/storage/emulated/0/Android/data/${app.packageName}',
                                  ),
                              child: Text(
                                '/storage/emulated/0/Android/data/${app.packageName}',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.apkPath,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap: () => copyToClipboard(app.apkPath),
                              child: Text(
                                app.apkPath,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.firstInstall,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(
                                    DateFormat('yyyy-MM-dd HH:mm:ss').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        app.installedTimestamp,
                                      ),
                                    ),
                                  ),
                              child: Text(
                                DateFormat('yyyy-MM-dd HH:mm:ss').format(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    app.installedTimestamp,
                                  ),
                                ),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.lastUpdate,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(
                                    DateFormat('yyyy-MM-dd HH:mm:ss').format(
                                      DateTime.fromMillisecondsSinceEpoch(
                                        app.lastUpdatedTimestamp,
                                      ),
                                    ),
                                  ),
                              child: Text(
                                DateFormat('yyyy-MM-dd HH:mm:ss').format(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    app.lastUpdatedTimestamp,
                                  ),
                                ),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.availableIn,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap: () async {
                                final url = Uri.parse(
                                  appStoreUrl != "" ? appStoreUrl : "",
                                );
                                if (await canLaunchUrl(url)) {
                                  await launchUrl(url);
                                }
                              },
                              child: Text(
                                appStore != "" ? appStore : "...",
                                style: TextStyle(color: Colors.green[600]),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              localizations.installer,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(
                                    installer != "" ? installer : "...",
                                  ),
                              child: Text(
                                installer != "" ? installer : "...",
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TableRow(
                          children: [
                            const SizedBox(height: 8),
                            const SizedBox(height: 8),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text(
                              'UID',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(app.appUid.toString()),
                              child: Text(
                                "${app.appUid}",
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          key: menuKey,
                          onPressed: () async {
                            final RenderBox button =
                                menuKey.currentContext!.findRenderObject()
                                    as RenderBox;
                            final RenderBox overlay =
                                Overlay.of(context).context.findRenderObject()
                                    as RenderBox;
                            final Offset position = button.localToGlobal(
                              Offset.zero,
                              ancestor: overlay,
                            );
                            final RelativeRect rect = RelativeRect.fromLTRB(
                              position.dx,
                              position.dy + button.size.height,
                              position.dx + button.size.width,
                              position.dy,
                            );
                            await showMenu<String>(
                              context: context,
                              position: rect,
                              items: [
                                PopupMenuItem(
                                  onTap:
                                      () => InstalledApps.startApp(
                                        app.packageName,
                                      ),
                                  child: Text(
                                    localizations.launch,
                                    style: TextStyle(fontSize: 18),
                                  ),
                                ),
                                PopupMenuItem(
                                  onTap:
                                      () => InstalledApps.openSettings(
                                        app.packageName,
                                      ),
                                  child: Text(
                                    localizations.details,
                                    style: TextStyle(fontSize: 18),
                                  ),
                                ),
                                PopupMenuItem(
                                  onTap: () {
                                    _uniPkgName = app.packageName;
                                    InstalledApps.uninstallApp(app.packageName);
                                    Navigator.of(context).pop();
                                  },
                                  child: Text(
                                    localizations.uninstall,
                                    style: TextStyle(fontSize: 18),
                                  ),
                                ),
                              ],
                            );
                          },
                          child: Text(
                            localizations.more.toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _extractApk([app]);
                          },
                          child: Text(
                            localizations.extractApk.toUpperCase(),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;
    
    return PopScope(
      canPop: !_isSearching && !_isMultiSelect,
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 180,
              pinned: true,
              stretch: true,
              backgroundColor: theme.colorScheme.surface,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                   if (_isSearching) {
                    _toggleSearch();
                  } else if (_isMultiSelect) {
                    _toggleMultiSelect();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
              actions: [
                 IconButton(
                    icon: Icon(_isSearching ? Icons.close : Icons.search),
                    onPressed: _toggleSearch,
                  ),
                  PopupMenuButton<int>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 0) {
                        setState(() {
                          _excludeSystemApps = !_excludeSystemApps;
                          _isSearching = false;
                          _searchController.clear();
                        });
                        _loadApps();
                      } else if (value == 1) {
                        _savePrefs(!_autoRefresh);
                      }
                    },
                    itemBuilder:
                        (context) => [
                          CheckedPopupMenuItem(
                            value: 0,
                            checked: !_excludeSystemApps,
                            child: Text(localizations.includeSystemApps),
                          ),
                          CheckedPopupMenuItem(
                            value: 1,
                            checked: _autoRefresh,
                            child: Text(localizations.autoRefresh),
                          ),
                        ],
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                title: _isMultiSelect
                          ? Text(localizations.selected(_selectedApps.length.toString()),
                              style: TextStyle(color: theme.colorScheme.onSurface)
                            )
                          : _isSearching 
                             ? null
                             : Text(
                                localizations.extractApk,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                centerTitle: true,
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colorScheme.primary.withValues(alpha: 0.1),
                            theme.colorScheme.surface,
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
                          Icons.layers,
                          size: 150,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              bottom: _isSearching 
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(60),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                       color: theme.colorScheme.surface,
                       child: TextField(
                        controller: _searchController,
                        autofocus: true,
                         decoration: InputDecoration(
                          hintText: localizations.searchApps,
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                           fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                             borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                       ),
                    ),
                  )
                : null,
            ),
             if (_isLoading)
               const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
               )
             else if (_filteredApps.isEmpty)
               SliverFillRemaining(
                child: Center(child: Text(localizations.noAppsFound)),
               )
             else 
               SliverPadding(
                 padding: const EdgeInsets.all(16),
                 sliver: SliverList(
                   delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final app = _filteredApps[index];
                      bool isSplitApp = app.splitSourceDirs.isNotEmpty;
                      final isSelected = _isMultiSelect && _selectedApps.contains(index);

                      return Container(
                         margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? theme.colorScheme.primary.withValues(alpha: 0.1) 
                                : theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: isSelected 
                                    ? theme.colorScheme.primary 
                                    : theme.dividerColor,
                                width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            leading: Container(
                               padding: const EdgeInsets.all(8),
                               decoration: BoxDecoration(
                                 color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                 borderRadius: BorderRadius.circular(12),
                               ),
                               child: app.icon != null
                                  ? Image.memory(
                                    app.icon!,
                                    width: 32,
                                    height: 32,
                                  )
                                  : Icon(Icons.android, size: 32, color: theme.colorScheme.primary),
                            ),
                            title: Text(
                              app.name, 
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                     Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                           color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                                           borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          app.versionName,
                                           style: theme.textTheme.labelSmall?.copyWith(
                                             color: theme.colorScheme.secondary,
                                             fontWeight: FontWeight.bold,
                                           ),
                                        ),
                                     ),
                                     const SizedBox(width: 8),
                                     Text(
                                        formatSize(app.packageSize),
                                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                                     ),
                                  ],
                                ),
                                if (isSplitApp) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                       "SPLIT APK",
                                        style: theme.textTheme.labelSmall?.copyWith(
                                           color: theme.colorScheme.tertiary,
                                           fontWeight: FontWeight.bold,
                                        ),
                                    ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  app.packageName,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                     fontFamily: 'monospace',
                                     color: theme.colorScheme.outline,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            onTap: () {
                              if (_isMultiSelect) {
                                setState(() {
                                  if (_selectedApps.contains(index)) {
                                    _selectedApps.remove(index);
                                    if (_selectedApps.isEmpty) {
                                      _isMultiSelect = false;
                                    }
                                  } else {
                                    _selectedApps.add(index);
                                  }
                                });
                              } else {
                                _showAppDetails(app);
                              }
                            },
                            onLongPress: () {
                              if (!_isMultiSelect) {
                                _toggleMultiSelect();
                              }
                              setState(() {
                                if (_selectedApps.contains(index)) {
                                  _selectedApps.remove(index);
                                } else {
                                  _selectedApps.add(index);
                                }
                              });
                            },
                          ),
                      );
                    },
                    childCount: _filteredApps.length,
                   ),
                 ),
               ),
          ],
        ),
        floatingActionButton: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (Widget child, Animation<double> animation) {
            final offsetAnimation = Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            );
            return SlideTransition(position: offsetAnimation, child: child);
          },
          child:
              _isMultiSelect
                  ? Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16.0, right: 16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton(
                            onPressed: _invertSelect,
                            heroTag: 'invertFAB',
                            backgroundColor: theme.colorScheme.secondary,
                            foregroundColor: theme.colorScheme.onSecondary,
                            child: const Icon(Icons.flip_to_back),
                          ),
                          const SizedBox(height: 12),
                          FloatingActionButton(
                            onPressed: _extractSelectedApps,
                            heroTag: 'extractFAB',
                            backgroundColor: theme.colorScheme.primary,
                             foregroundColor: theme.colorScheme.onPrimary,
                            child: const Icon(Icons.eject_outlined),
                          ),
                        ],
                      ),
                    ),
                  )
                  : const SizedBox.shrink(),
        ),
      ),
    );
  }

  String formatSize(int bytes) {
    if (bytes < 1024) {
      return '${bytes}B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)}K';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}M';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)}G';
    }
  }
}
