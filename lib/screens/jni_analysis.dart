import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/platform.dart';
import 'package:revengi/utils/dio.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferences;

class JniAnalysisScreen extends StatefulWidget {
  const JniAnalysisScreen({super.key});

  @override
  State<JniAnalysisScreen> createState() => _JniAnalysisScreenState();
}

class _JniAnalysisScreenState extends State<JniAnalysisScreen> {
  File? _selectedFile;
  bool _isAnalyzing = false;
  String? _result;
  String? _error;
  String? _fileName;
  List<int> _fileBytes = [];

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: isWeb() ? FileType.custom : FileType.any,
      allowedExtensions: isWeb() ? ['apk'] : null,
    );

    if (result != null) {
      if (isWeb()) {
        setState(() {
          _selectedFile = null;
          _fileName = result.files.first.name;
          _fileBytes = result.files.first.bytes!;
          _error = null;
          _result = null;
        });
      } else {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _fileName = result.files.first.name;
          _error = null;
          _result = null;
        });
      }
    }
  }

  Future<void> _analyzeFile() async {
    final localizations = AppLocalizations.of(context)!;

    final prefs = await SharedPreferences.getInstance();
    final isGuestUser = prefs.getBool('isGuestUser') ?? false;
    if (isGuestUser) {
      setState(() {
        _error = localizations.guestNotAllowed;
      });
      return;
    }

    if ((isWeb() && _fileBytes.isEmpty) ||
        (!isWeb() && _selectedFile == null)) {
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _error = null;
      _result = null;
    });

    try {
      final formData = FormData.fromMap({
        'apk_file':
            isWeb()
                ? MultipartFile.fromBytes(_fileBytes, filename: _fileName)
                : await MultipartFile.fromFile(
                  _selectedFile!.path,
                  filename:
                      _fileName ??
                      _selectedFile!.path.split(Platform.pathSeparator).last,
                ),
      });

      final response = await dio.post('/analyze/jni', data: formData);

      setState(() {
        _result = response.data.toString();
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
      appBar: AppBar(title: Text(localizations.jniAnalysis)),
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
                    if (_selectedFile != null || _fileBytes.isNotEmpty)
                      isWeb()
                          ? Text(
                            'Selected: $_fileName',
                            style: const TextStyle(color: Colors.green),
                          )
                          : Text(
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
                                (isWeb()
                                            ? _fileBytes.isEmpty
                                            : _selectedFile == null) ||
                                        _isAnalyzing
                                    ? null
                                    : _analyzeFile,
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isAnalyzing)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
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
            else if (_result != null)
              Expanded(
                child: Card(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(_result!),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
