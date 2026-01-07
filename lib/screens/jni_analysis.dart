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
      int fileSizeBytes;

      if (isWeb()) {
        fileSizeBytes = result.files.first.bytes!.length;
      } else {
        fileSizeBytes = File(result.files.single.path!).lengthSync();
      }

      if (fileSizeBytes > 80 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'File size exceeds 80 MB limit. Please choose a smaller file.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

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
    final username = prefs.getString('username');
    if (username == "guest") {
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
      setState(() {
        if (e.response?.data != null &&
            e.response?.data is Map &&
            e.response?.data['detail'] != null) {
          _error =
              e.response?.data?['detail'] ?? localizations.errorDuringAnalysis;
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
                localizations.jniAnalysis,
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
                        Icons.code,
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
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
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
                          Icons.android,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _fileName ?? localizations.selectFiles("APK"),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color:
                                _fileName != null
                                    ? Colors.green
                                    : theme.textTheme.bodyMedium?.color,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isAnalyzing ? null : _pickFile,
                                icon: const Icon(Icons.file_upload),
                                label: Text(localizations.chooseFile("APK")),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      theme.colorScheme.surfaceContainerHighest,
                                  foregroundColor:
                                      theme.colorScheme.onSurfaceVariant,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
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
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colorScheme.primary,
                                  foregroundColor: theme.colorScheme.onPrimary,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_isAnalyzing)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.error),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_result != null)
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(15),
                              ),
                            ),
                            child: const Text(
                              "Analysis Result",
                              style: TextStyle(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(_result!),
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
