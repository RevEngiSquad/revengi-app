import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/platform.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplitApksMergerScreen extends StatefulWidget {
  const SplitApksMergerScreen({super.key});

  @override
  SplitApksMergerScreenState createState() => SplitApksMergerScreenState();
}

class SplitApksMergerScreenState extends State<SplitApksMergerScreen> {
  File? _selectedFile;
  String? _fileName;
  List<int> _fileBytes = [];
  String extractNativeLibs = 'manifest';
  bool validateResDir = false;
  bool cleanMeta = false;
  bool validateModules = false;
  String resDirName = '';
  final List<String> extractNativeLibsOptions = [
    'manifest',
    'none',
    'false',
    'true',
  ];
  final List<Map<String, String>> _logs = [];
  bool _showLogs = false;
  bool _isMerging = false;
  static const MethodChannel _methodChannel = MethodChannel(
    'flutter.native/helper',
  );
  static const EventChannel _eventChannel = EventChannel('flutter.native/logs');
  Stream? _logStream;
  StreamSubscription? _logSubscription;
  final ScrollController _logsScrollController = ScrollController();
  String? apkEditorJarPath;

  Future<void> logMessage(String msg, [String type = 'success']) async {
    if (kDebugMode) {
      print('Log: $msg');
    }
    setState(() {
      _logs.add({'msg': msg, 'type': type});
    });
    await Future.delayed(Duration.zero);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_logsScrollController.hasClients) {
        await _logsScrollController.animateTo(
          _logsScrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null) {
      if (result.files.single.extension != 'apks' &&
          result.files.single.extension != 'apkm' &&
          result.files.single.extension != 'xapk') {
        setState(() {
          _showLogs = true;
          _logs.clear();
        });
        logMessage('Please select a valid APKS, APKM or XAPK file.', 'error');
        return;
      }
      setState(() {
        _selectedFile =
            result.files.single.path != null
                ? File(result.files.single.path!)
                : null;
        _fileName = result.files.first.name;
        _fileBytes = result.files.first.bytes ?? [];
      });
    }
  }

  Future<String> _extractFile(File file) async {
    final tmpDir = Directory.systemTemp.createTempSync('extract_');
    final tmp = tmpDir.path;
    logMessage("Extracting to: $tmp");

    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    int count = 0;

    for (final file in archive) {
      final filename = tmpDir.path + Platform.pathSeparator + file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        await File(filename).writeAsBytes(data);
        if (filename.endsWith('.apk')) {
          count++;
        }
      } else {
        await Directory(filename).create(recursive: true);
      }
    }

    if (count == 0) {
      await tmpDir.delete(recursive: true);
      logMessage('No *.apk files found in the archive', 'error');
      throw Exception('No *.apk files found in the archive');
    }

    return tmp;
  }

  @override
  void initState() {
    super.initState();
    if (isAndroid()) {
      _logStream = _eventChannel.receiveBroadcastStream();
      _logSubscription = _logStream?.listen((event) {
        if (event is Map && event.containsKey('msg')) {
          logMessage(event['msg'] ?? '', event['type'] ?? 'success');
          if (event['type'] == 'mergeComplete') {
            setState(() {
              _isMerging = false;
            });
          }
        } else if (event is String) {
          logMessage(event);
          if (event == 'mergeComplete') {
            setState(() {
              _isMerging = false;
            });
          }
        }
      });
      _logSubscription?.onDone(() {});
    } else {
      _loadJarPath();
    }
  }

  Future<void> _loadJarPath() async {
    if (isWindows() || isLinux()) {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        apkEditorJarPath = prefs.getString('apkeditor_jar_path');
      });
    }
  }

  Future<void> _setJarPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('apkeditor_jar_path', path);
    setState(() {
      apkEditorJarPath = path;
    });
  }

  Future<void> _setJarPathSettings() async {
    final controller = TextEditingController(text: apkEditorJarPath ?? '');
    final localizations = AppLocalizations.of(context)!;
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(localizations.setJarPath),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: localizations.pathToApkeditorJar,
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(localizations.cancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: Text(localizations.save),
              ),
            ],
          ),
    );
    if (result != null && result.isNotEmpty) {
      await _setJarPath(result);
    }
  }

  Future<void> _mergeFileTask() async {
    setState(() {
      _showLogs = true;
      _logs.clear();
      _isMerging = true;
    });
    final Directory dir = Directory(await getDownloadsDirectory());
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    var outputFile = '${dir.path}${Platform.pathSeparator}$_fileName.apk';

    if (isAndroid()) {
      final options = {
        'extractNativeLibs': extractNativeLibs,
        'validateResDir': validateResDir,
        'cleanMeta': cleanMeta,
        'validateModules': validateModules,
        'resDirName': resDirName,
        'outputFile': outputFile,
      };

      logMessage('Starting merge with options:');
      options.forEach((key, value) {
        logMessage('$key: $value');
      });

      try {
        var dir = await _extractFile(_selectedFile!);
        options['extractedDir'] = dir;

        logMessage('Extracted directory: $dir');

        await _methodChannel.invokeMethod('startMerge', options);
      } catch (e) {
        logMessage(e.toString(), 'error');
        setState(() {
          _isMerging = false;
        });
      }
    } else if (isWindows() || isLinux()) {
      if (apkEditorJarPath == null || apkEditorJarPath!.isEmpty) {
        logMessage('Please set the apkeditor jar path in settings.', 'error');
        setState(() {
          _isMerging = false;
        });
        return;
      }
      var inputFile = _selectedFile!.path;
      try {
        final cmdargs = [
          '-jar',
          apkEditorJarPath!,
          'm',
          '-f',
          '-i',
          inputFile,
          '-o',
          outputFile,
          '-extractNativeLibs',
          extractNativeLibs,
        ];
        if (cleanMeta) {
          cmdargs.add('-clean-meta');
        }
        if (validateModules) {
          cmdargs.add('-validate-modules');
        }
        if (validateResDir) {
          cmdargs.add('-vrd');
        }
        if (resDirName.isNotEmpty) {
          cmdargs.add('-res-dir');
          cmdargs.add(resDirName);
        }
        logMessage('Running: java ${cmdargs.join(' ')}');
        final process = await Process.start('java', cmdargs);
        process.stdout.transform(SystemEncoding().decoder).listen((data) {
          logMessage(data);
        });
        process.stderr.transform(SystemEncoding().decoder).listen((data) {
          logMessage(data, 'error');
        });
        final exitCode = await process.exitCode;
        if (exitCode == 0) {
          logMessage('Merge completed: $outputFile');
        } else {
          logMessage('Merge failed with exit code $exitCode', 'error');
        }
      } catch (e) {
        logMessage('Error running java: $e', 'error');
      }
      setState(() {
        _isMerging = false;
      });
    } else {
      logMessage('Unsupported platform', 'error');
      setState(() {
        _isMerging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final borderColor = theme.dividerColor;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            stretch: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                localizations.mergeSplitApks,
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
                        Icons.merge_type,
                        size: 200,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (isWindows() || isLinux())
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: localizations.setJarPath,
                  onPressed: _setJarPathSettings,
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.folder_zip,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedFile != null || _fileBytes.isNotEmpty
                              ? '$_fileName'
                              : localizations.selectFiles("APK"),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color:
                                _selectedFile != null || _fileBytes.isNotEmpty
                                    ? Colors.green
                                    : theme.textTheme.bodyMedium?.color,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.file_upload),
                          label: Text(localizations.chooseFile("APK")),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primaryContainer,
                            foregroundColor:
                                theme.colorScheme.onPrimaryContainer,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('Extract Native Libs'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: extractNativeLibs,
                                icon: const Icon(Icons.arrow_drop_down),
                                borderRadius: BorderRadius.circular(12),
                                items:
                                    extractNativeLibsOptions
                                        .map(
                                          (opt) => DropdownMenuItem(
                                            value: opt,
                                            child: Text(opt),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    extractNativeLibs = value!;
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        Divider(height: 1, color: borderColor),
                        SwitchListTile(
                          title: Text(localizations.vrd),
                          value: validateResDir,
                          activeColor: theme.colorScheme.primary,
                          onChanged: (val) {
                            setState(() {
                              validateResDir = val;
                            });
                          },
                        ),
                        Divider(height: 1, color: borderColor),
                        SwitchListTile(
                          title: Text(localizations.cleanMeta),
                          value: cleanMeta,
                          activeColor: theme.colorScheme.primary,
                          onChanged: (val) {
                            setState(() {
                              cleanMeta = val;
                            });
                          },
                        ),
                        Divider(height: 1, color: borderColor),
                        SwitchListTile(
                          title: Text(localizations.validateModules),
                          value: validateModules,
                          activeColor: theme.colorScheme.primary,
                          onChanged: (val) {
                            setState(() {
                              validateModules = val;
                            });
                          },
                        ),
                        Divider(height: 1, color: borderColor),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'res/',
                              filled: true,
                              fillColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              prefixIcon: const Icon(Icons.folder_open),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                            onChanged: (val) {
                              setState(() {
                                resDirName = val;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.merge_type),
                      label: Text(
                        localizations.merge.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed:
                          (_selectedFile != null || _fileBytes.isNotEmpty) &&
                                  !_isMerging
                              ? _mergeFileTask
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_showLogs)
                    Container(
                      height: 300,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.1),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.terminal,
                                  size: 16,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Output Log',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => setState(() => _logs.clear()),
                                  child: const Icon(
                                    Icons.delete_outline,
                                    size: 16,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              controller: _logsScrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: _logs.length,
                              itemBuilder: (context, idx) {
                                final log = _logs[idx];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '> ${log['msg']}',
                                    style: TextStyle(
                                      color:
                                          log['type'] == 'error'
                                              ? const Color(0xFFFF5252)
                                              : const Color(0xFF69F0AE),
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
