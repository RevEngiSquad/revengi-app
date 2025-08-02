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
      // We deliberatily do this here because dart's analyser nags about _logSubscription being unused
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
    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.mergeSplitApks),
        actions: [
          if (isWindows() || isLinux())
            IconButton(
              icon: Icon(Icons.settings),
              tooltip: localizations.setJarPath,
              onPressed: _setJarPathSettings,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(localizations.selectFiles("APK")),
              if (_selectedFile != null || _fileBytes.isNotEmpty)
                Text(
                  'Selected: $_fileName',
                  style: TextStyle(color: Colors.green),
                ),
              SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _pickFile,
                icon: Icon(Icons.file_upload),
                label: Text(localizations.chooseFile("APK")),
              ),
              SizedBox(height: 20),
              Text('extractNativeLibs:'),
              DropdownButton<String>(
                value: extractNativeLibs,
                items:
                    extractNativeLibsOptions
                        .map(
                          (opt) =>
                              DropdownMenuItem(value: opt, child: Text(opt)),
                        )
                        .toList(),
                onChanged: (value) {
                  setState(() {
                    extractNativeLibs = value!;
                  });
                },
              ),
              SwitchListTile(
                title: Text(localizations.vrd),
                value: validateResDir,
                onChanged: (val) {
                  setState(() {
                    validateResDir = val;
                  });
                },
              ),
              SwitchListTile(
                title: Text(localizations.cleanMeta),
                value: cleanMeta,
                onChanged: (val) {
                  setState(() {
                    cleanMeta = val;
                  });
                },
              ),
              SwitchListTile(
                title: Text(localizations.validateModules),
                value: validateModules,
                onChanged: (val) {
                  setState(() {
                    validateModules = val;
                  });
                },
              ),
              TextField(
                decoration: InputDecoration(labelText: 'res/'),
                onChanged: (val) {
                  setState(() {
                    resDirName = val;
                  });
                },
              ),
              SizedBox(height: 24),
              Center(
                child: ElevatedButton.icon(
                  icon: Icon(Icons.merge_type),
                  label: Text(localizations.merge),
                  onPressed:
                      (_selectedFile != null || _fileBytes.isNotEmpty) &&
                              !_isMerging
                          ? _mergeFileTask
                          : null,
                  style: ElevatedButton.styleFrom(minimumSize: Size(160, 48)),
                ),
              ),
              SizedBox(height: 32),
              if (_showLogs)
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                    // border: Border.all(color: Colors.greenAccent, width: 1),
                  ),
                  padding: EdgeInsets.all(12),
                  child: ListView.builder(
                    controller: _logsScrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, idx) {
                      final log = _logs[idx];
                      return Text(
                        log['msg'] ?? '',
                        style: TextStyle(
                          color:
                              log['type'] == 'error'
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                          fontFamily: 'monospace',
                          fontSize: 14,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
