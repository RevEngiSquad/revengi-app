import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/dartinfo.dart';
import 'package:revengi/utils/platform.dart';
import 'package:revengi/utils/dio.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;

class BlutterAnalysisScreen extends StatefulWidget {
  const BlutterAnalysisScreen({super.key});

  @override
  State<BlutterAnalysisScreen> createState() => _BlutterAnalysisScreenState();
}

class _BlutterAnalysisScreenState extends State<BlutterAnalysisScreen> {
  File? _apkFile;
  File? _libappFile;
  File? _libflutterFile;
  bool _isAnalyzing = false;
  String? _error;
  String? _successMessage;
  late double _uploadProgress;
  late double _downloadProgress;

  Future<void> _pickApkFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null) {
      setState(() {
        _apkFile = File(result.files.single.path!);
        _error = null;
        _successMessage = null;
      });

      if (_apkFile!.path.split(Platform.pathSeparator).last.endsWith('.zip') ||
          _apkFile!.path.split(Platform.pathSeparator).last.endsWith('.apk')) {
        await _extractFiles();
      }
    }
  }

  Future<void> _extractFiles() async {
    if (_apkFile == null) return;

    final localizations = AppLocalizations.of(context)!;
    final Directory directory = Directory.systemTemp;
    final apkPath = _apkFile!.path;
    final zipFile = File(apkPath);
    String fileEnd = "arm64-v8a/libapp.so";
    if (apkPath.split(Platform.pathSeparator).last.endsWith('.zip')) {
      fileEnd = "libapp.so";
    }

    try {
      final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());

      for (final file in archive) {
        if (file.isFile && file.name.endsWith(fileEnd)) {
          final data = file.content as List<int>;
          _libappFile = File('${directory.path}/libapp.so')
            ..writeAsBytesSync(data);
        } else if (file.isFile && file.name.endsWith('libflutter.so')) {
          final data = file.content as List<int>;
          _libflutterFile = File('${directory.path}/libflutter.so')
            ..writeAsBytesSync(data);
        }
      }

      if (_libappFile == null || _libflutterFile == null) {
        throw Exception('libapp.so or libflutter.so not found in the archive');
      }

      setState(() {
        _error = null;
      });
    } catch (e) {
      setState(() {
        _error = localizations.failedToExtractFiles(e.toString());
      });
    }
  }

  Future<void> _analyzeFiles() async {
    if (_libappFile == null || _libflutterFile == null) return;
    final localizations = AppLocalizations.of(context)!;

    setState(() {
      _isAnalyzing = true;
      _error = null;
      _successMessage = null;
      _uploadProgress = 0;
      _downloadProgress = 0;
    });

    try {
      final elfParser = ElfParser(flutterLibPath: _libflutterFile!.path);
      final rodataInfo = elfParser.extractRodataInfo();
      String? dartVersion = rodataInfo?.$2;
      if (dartVersion == null && rodataInfo != null) {
        final sdkInfo = await elfParser.getSdkInfo();
        dartVersion = sdkInfo?.dartVersion;
      }
      if (dartVersion!.endsWith('.dev') || dartVersion.endsWith('.beta')) {
        _error = localizations.unsupportedDartVersion(dartVersion);
        return;
      }
      final formData = FormData.fromMap({
        'libapp': await MultipartFile.fromFile(
          _libappFile!.path,
          filename: _libappFile!.path
              .split(Platform.pathSeparator)
              .last
              .replaceAll("Temp/", ""),
        ),
      });

      final response = await dio.post(
        '/blutter',
        data: formData,
        options: Options(responseType: ResponseType.bytes),
        queryParameters: {'dart_version': dartVersion},
        onSendProgress: (int sent, int total) {
          setState(() {
            _uploadProgress = sent / total;
          });
        },
        onReceiveProgress: (int received, int total) {
          if (total != -1) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );

      // Save response bytes to file
      final Directory dir = Directory(await getDownloadsDirectory());
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      String? filename;
      final contentDisposition = response.headers['content-disposition']?.first;
      if (contentDisposition != null) {
        final regexExtended = RegExp(r"filename\*=([^']*)''([^;\n]+)");
        final regexStandard = RegExp(r'filename="?([^";\n]+)"?');
        final matchExtended = regexExtended.firstMatch(contentDisposition);
        if (matchExtended != null) {
          filename = Uri.decodeFull(matchExtended.group(2)!);
        } else {
          final matchStandard = regexStandard.firstMatch(contentDisposition);
          if (matchStandard != null) {
            filename = matchStandard.group(1);
          }
        }
      }
      filename ??= 'blutter_output.zip';
      final selectedFileName =
          _apkFile!.path.split(Platform.pathSeparator).last.split('.').first;
      var outputFile = File(
        '${dir.path}/$filename'.replaceAll(".zip", '_$selectedFileName.zip'),
      );
      if (outputFile.existsSync()) {
        final randomNumber = DateTime.now().millisecondsSinceEpoch;
        final newFilename = filename.replaceAll('.zip', '_$randomNumber.zip');
        outputFile = File('${dir.path}/$newFilename');
      }
      await outputFile.writeAsBytes(response.data);

      setState(() {
        _successMessage = 'Analysis saved to: ${outputFile.path}';
      });
    } on DioException catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      setState(() {
        if (username == "guest") {
          _error = localizations.guestNotAllowed;
        } else if (e.response?.data != null &&
            e.response?.data is Map &&
            e.response?.data['detail'] != null) {
          _error =
              e.response?.data?['detail'] ?? localizations.errorDuringAnalysis;
        } else if (e.type == DioExceptionType.connectionTimeout) {
          _error = 'Connection timeout';
        } else if (e.type == DioExceptionType.connectionError) {
          _error = 'No internet connection';
        } else {
          _error =
              'An error occurred during analysis, please make sure you\'ve selected the correct files';
        }
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
        _uploadProgress = 0;
        _downloadProgress = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.blutter)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.selectFiles("APK/Zip"),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.android),
                      title: const Text('APK/Zip File'),
                      subtitle:
                          _apkFile != null
                              ? Text(
                                _apkFile!.path
                                    .split(Platform.pathSeparator)
                                    .last,
                                style: const TextStyle(color: Colors.green),
                              )
                              : Text(localizations.noFileSelected),
                      trailing: ElevatedButton(
                        onPressed: _isAnalyzing ? null : _pickApkFile,
                        child: Text(localizations.chooseFile("File")),
                      ),
                    ),
                    const SizedBox(height: 16),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Note: ',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: localizations.blutterNote,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_apkFile == null || _isAnalyzing)
                                ? null
                                : _analyzeFiles,
                        icon: const Icon(Icons.analytics),
                        label: Text(
                          _isAnalyzing
                              ? localizations.analyzing
                              : localizations.analyze,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isAnalyzing) ...[
              if (_uploadProgress > 0 && _uploadProgress < 1)
                Column(
                  children: [
                    Text(localizations.uploading),
                    LinearProgressIndicator(value: _uploadProgress),
                    const SizedBox(height: 8),
                  ],
                ),
              if (_downloadProgress > 0 && _downloadProgress < 1)
                Column(
                  children: [
                    Text(localizations.downloading),
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 8),
                  ],
                ),
              if (_uploadProgress == 0 && _downloadProgress == 0)
                const Center(child: CircularProgressIndicator()),
            ] else if (_error != null)
              Card(
                color: Colors.red[100],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red[900]),
                  ),
                ),
              )
            else if (_successMessage != null)
              Card(
                color: Colors.green[100],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _successMessage!,
                    style: TextStyle(color: Colors.green[900]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
