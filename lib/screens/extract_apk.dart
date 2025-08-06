import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/sign_info.dart';
import 'package:intl/intl.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/platform.dart';
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
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _loadApps();
    }
  }

  Future<(String?, String?)> checkAppOnStore(String packageName) async {
    var url = 'https://play.google.com/store/apps/details?id=$packageName';
    final Dio dio = Dio();
    dio.options.validateStatus = (status) {
      return status! < 500;
    };
    var res = await dio.head(url);
    if (res.statusCode == 200) {
      return ("Google Play", url);
    } else {
      url = 'https://f-droid.org/en/packages/$packageName';
      res = await dio.get(url);
      if (res.statusCode == 200) {
        return ("F-Droid", url);
      } else {
        url = 'https://apt.izzysoft.de/fdroid/index/apk/$packageName';
        res = await dio.get(url);
        if (res.statusCode == 200) {
          return ("Izzydroid", url);
        }
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

  void _onPopInvokedWithResult(bool didPop, dynamic result) {
    if (didPop) return;
    if (_isSearching) {
      _toggleSearch();
    }
  }

  Future<void> _extractApk(
    String apkPath,
    List<dynamic> splitSourceDirs,
    String apkName,
    String apkVersion,
  ) async {
    var isExtracting = true;
    var extracted = false;
    final localizations = AppLocalizations.of(context)!;
    final isSplitApp = splitSourceDirs.isNotEmpty;
    File? outputFile;

    try {
      if (isExtracting) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => AlertDialog(
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
        );
      }

      final dir = Directory(
        await getDownloadsDirectory().then((dir) => "$dir/apks"),
      );
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      outputFile =
          isSplitApp
              ? File('${dir.path}/${apkName}_$apkVersion.apks')
              : File('${dir.path}/${apkName}_$apkVersion.apk');

      if (outputFile.existsSync()) {
        if (!mounted) return;
        final shouldOverwrite = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(localizations.fileExists),
                content: Text(localizations.fileExistsMsg),
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
          return;
        } else {
          outputFile.delete(recursive: true);
        }
      }

      if (isSplitApp) {
        final methodChannel = MethodChannel('flutter.native/helper');
        final apkPaths = [apkPath, ...splitSourceDirs];
        extracted =
            (await methodChannel.invokeMethod<bool>('zipApks', {
              'apkPaths': apkPaths,
              'outputPath': outputFile.path,
            }))!;
      } else {
        final apkFile = File(apkPath);
        await apkFile.copy(outputFile.path);
        if (!outputFile.existsSync()) {
          extracted = false;
        } else {
          extracted = true;
        }
      }
    } catch (e) {
      // Check if error is of PathAccessException type
      if (e is PathAccessException) {
        // It looks like that file/directory wasn't made by RevEngi
        // It needs manual deletion by the user because we're not requesting manageExternalStorage permission
        // This is a limitation of Android 11 and above
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
          return;
        }
      }
      setState(() {
        isExtracting = false;
        extracted = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localizations.apkExtractError(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isExtracting = false;
        });
        Navigator.of(context).pop();
        if (outputFile != null && extracted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations.apkExtractedMsg(outputFile.path)),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
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
          title: Text("Raw data"),
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
              child: Text("Copy"),
              onPressed: () {
                copyToClipboard(textEditingController.text);
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text("Copy Base64"),
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
                      "Signature Information",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
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
                                  "Scheme",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(
                                        '${signInfo.schemes}',
                                      ),
                                  child: Text(
                                    signInfo.schemes.join(" + "),
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  "Algorithm",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                InkWell(
                                  onTap:
                                      () => copyToClipboard(signInfo.algorithm),
                                  child: Text(
                                    signInfo.algorithm,
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  "Status",
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  "Created",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                InkWell(
                                  onTap:
                                      () =>
                                          copyToClipboard(signInfo.createDate),
                                  child: Text(
                                    signInfo.createDate,
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  "Expired",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                InkWell(
                                  onTap:
                                      () =>
                                          copyToClipboard(signInfo.expireDate),
                                  child: Text(
                                    signInfo.expireDate,
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  "Owner",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                InkWell(
                                  onTap: () => copyToClipboard(signInfo.issuer),
                                  child: Text(
                                    signInfo.issuer,
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  style: TextStyle(fontWeight: FontWeight.bold),
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
                                    style: TextStyle(color: Colors.grey[600]),
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
                                  "Format",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        Text("Add colon"),
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
                                        Text("Upper case"),
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
                            "View Data".toUpperCase(),
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

  Future<void> _showAppDetails(AppInfo app) async {
    final localizations = AppLocalizations.of(context)!;
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

                if (mounted) {
                  setState(() {
                    signatureSchemes = result.schemes;
                    signInfo = result;
                  });
                }
                var (appStor, appStoreUr) = await checkAppOnStore(
                  app.packageName,
                );
                if (mounted) {
                  setState(() {
                    if (appStor != null && appStoreUr != null) {
                      appStore = appStor;
                      appStoreUrl = appStoreUr;
                    }
                  });
                }
                final installerResult = await InstalledApps.getAppInfo(
                  app.installer,
                  BuiltWith.flutter,
                );
                if (mounted) {
                  setState(() {
                    if (installerResult != null) {
                      installer = installerResult.name;
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
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => copyToClipboard(app.versionName),
                                child: Padding(
                                  padding: EdgeInsets.only(top: 6, bottom: 4),
                                  child: Text(
                                    app.versionName,
                                    style: TextStyle(fontSize: 14),
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
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            InkWell(
                              onTap: () => copyToClipboard(app.packageName),
                              child: Text(
                                app.packageName,
                                style: TextStyle(color: Colors.grey[600]),
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
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard('${app.versionCode}'),
                              child: Text(
                                '${app.versionCode}',
                                style: TextStyle(color: Colors.grey[600]),
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
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(
                                    '${(app.packageSize / (1024 * 1024)).toStringAsFixed(2)}M',
                                  ),
                              child: Text(
                                '${(app.packageSize / (1024 * 1024)).toStringAsFixed(2)}M',
                                style: TextStyle(color: Colors.grey[600]),
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
                              "Signature",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            InkWell(
                              onTap:
                                  () =>
                                      signatureSchemes != null
                                          ? _showSignInfo(signInfo!)
                                          : null,
                              child: Text(
                                signatureSchemes != null
                                    ? signatureSchemes!.join(" + ")
                                    : "...",
                                style: TextStyle(color: Colors.grey[600]),
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
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            InkWell(
                              onTap: () => copyToClipboard(app.dataDir),
                              child: Text(
                                app.dataDir,
                                style: TextStyle(
                                  color: Colors.grey[600],
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
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(
                                    '/storage/emulated/0/Android/data/${app.packageName}',
                                  ),
                              child: Text(
                                '/storage/emulated/0/Android/data/${app.packageName}',
                                style: TextStyle(
                                  color: Colors.grey[600],
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
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            InkWell(
                              onTap: () => copyToClipboard(app.apkPath),
                              child: Text(
                                app.apkPath,
                                style: TextStyle(
                                  color: Colors.grey[600],
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
                              style: TextStyle(fontWeight: FontWeight.bold),
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
                                style: TextStyle(color: Colors.grey[600]),
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
                              style: TextStyle(fontWeight: FontWeight.bold),
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
                                style: TextStyle(color: Colors.grey[600]),
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
                              "Open in",
                              style: TextStyle(fontWeight: FontWeight.bold),
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
                            const Text(
                              'Installer',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(
                                    installer != "" ? installer : "...",
                                  ),
                              child: Text(
                                installer != "" ? installer : "...",
                                style: TextStyle(color: Colors.grey[600]),
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
                            const Text(
                              'UID',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            InkWell(
                              onTap:
                                  () => copyToClipboard(app.appUid.toString()),
                              child: Text(
                                "${app.appUid}",
                                style: TextStyle(color: Colors.grey[600]),
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
                            _extractApk(
                              app.apkPath,
                              app.splitSourceDirs,
                              app.name,
                              app.versionName,
                            );
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
    final brightness = Theme.of(context).brightness;
    final localizations = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: _onPopInvokedWithResult,
      child: Scaffold(
        appBar: AppBar(
          title:
              _isSearching
                  ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: localizations.searchApps,
                      border: InputBorder.none,
                      hintStyle: TextStyle(
                        color:
                            brightness == Brightness.dark
                                ? Colors.white70
                                : Colors.black54,
                      ),
                    ),
                    style: TextStyle(
                      color:
                          brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black,
                    ),
                  )
                  : Text(localizations.extractApk),
          actions: [
            IconButton(
              icon: Icon(_isSearching ? Icons.close : Icons.search),
              onPressed: _toggleSearch,
            ),
            PopupMenuButton<bool>(
              icon: const Icon(Icons.filter_list),
              onSelected: (value) {
                setState(() {
                  _excludeSystemApps = value;
                  _isSearching = false;
                  _searchController.clear();
                });
                _loadApps();
              },
              itemBuilder:
                  (context) => [
                    CheckedPopupMenuItem(
                      value: true,
                      checked: _excludeSystemApps,
                      child: Text(localizations.excludeSystemApps),
                    ),
                    CheckedPopupMenuItem(
                      value: false,
                      checked: !_excludeSystemApps,
                      child: Text(localizations.includeSystemApps),
                    ),
                  ],
            ),
          ],
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredApps.isEmpty
                ? Center(child: Text(localizations.noAppsFound))
                : RefreshIndicator(
                  onRefresh: _loadApps,
                  child: SafeArea(
                    top: false,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _filteredApps.length,
                      itemBuilder: (context, index) {
                        final app = _filteredApps[index];
                        bool isSplitApp = app.splitSourceDirs.isNotEmpty;
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          child: ListTile(
                            leading:
                                app.icon != null
                                    ? Image.memory(
                                      app.icon!,
                                      width: 40,
                                      height: 40,
                                    )
                                    : const Icon(Icons.android, size: 40),
                            title: Text(app.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  !isSplitApp
                                      ? "${app.versionName}    ${formatSize(app.packageSize)}"
                                      : "${app.versionName}    ${formatSize(app.packageSize)}    SPLIT+${formatSize(app.splitSourceDirs.fold(0, (sum, dir) => sum + File(dir).lengthSync()))}",
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  app.packageName,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                            onTap: () => _showAppDetails(app),
                          ),
                        );
                      },
                    ),
                  ),
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
