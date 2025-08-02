import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/dio.dart';
import 'package:revengi/utils/platform.dart' show getDownloadsDirectory;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;

class MTHookAnalysisScreen extends StatefulWidget {
  const MTHookAnalysisScreen({super.key});

  @override
  State<MTHookAnalysisScreen> createState() => _MTHookAnalysisScreenState();
}

class _MTHookAnalysisScreenState extends State<MTHookAnalysisScreen> {
  File? _selectedFile;
  bool _isAnalyzing = false;
  String? _error;
  String? _successMessage;
  String? _fileName;
  late double _uploadProgress;
  late double _downloadProgress;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _error = null;
        _successMessage = null;
      });
      _fileName = result.files.single.name;
      if (!_fileName!.endsWith('.apk')) {
        setState(() {
          _error = 'Please select an APK file';
          _selectedFile = null;
        });
      }
    }
  }

  Future<void> _analyzeFile() async {
    if (_selectedFile == null) return;
    final localizations = AppLocalizations.of(context)!;

    setState(() {
      _isAnalyzing = true;
      _error = null;
      _successMessage = null;
      _uploadProgress = 0;
      _downloadProgress = 0;
    });

    try {
      final formData = FormData.fromMap({
        'apk_file': await MultipartFile.fromFile(
          _selectedFile!.path,
          filename:
              _fileName ??
              _selectedFile!.path.split(Platform.pathSeparator).last,
        ),
      });

      final response = await dio.post(
        '/mthook',
        data: formData,
        options: Options(responseType: ResponseType.bytes),
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
      filename ??= 'output.zip';
      var outputFile = File('${dir.path}/$filename');
      if (outputFile.existsSync()) {
        final randomNumber = DateTime.now().millisecondsSinceEpoch;
        final newFilename = filename.replaceAll('.zip', '_$randomNumber.zip');
        outputFile = File('${dir.path}/$newFilename');
      }
      await outputFile.writeAsBytes(response.data);

      setState(() {
        _successMessage = 'Saved to: ${outputFile.path}';
      });
    } on DioException catch (e) {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      setState(() {
        if (username == "guest") {
          _error = localizations.guestNotAllowed;
        } else {
          if (e.response?.data != null &&
              e.response?.data is Map &&
              e.response?.data['detail'] != null) {
            _error =
                e.response?.data?['detail'] ??
                localizations.errorDuringAnalysis;
          }
        }
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.mtHook)),
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
                      localizations.selectFiles("APK"),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_selectedFile != null)
                      Text(
                        'Selected: ${_fileName ?? _selectedFile!.path.split(Platform.pathSeparator).last}',
                        style: const TextStyle(color: Colors.green),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isAnalyzing ? null : _pickFile,
                            icon: const Icon(Icons.file_upload),
                            label: Text(localizations.chooseFile("APK")),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                (_selectedFile == null) || _isAnalyzing
                                    ? null
                                    : _analyzeFile,
                            icon: const Icon(Icons.analytics),
                            label: Text(
                              _isAnalyzing
                                  ? localizations.generating
                                  : localizations.generate,
                            ),
                          ),
                        ),
                      ],
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
