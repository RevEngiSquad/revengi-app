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

    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    if (username == "guest") {
      setState(() {
        _error = localizations.guestNotAllowed;
      });
      return;
    }

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
                localizations.mtHook,
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
                        Icons.book, // Matches Home Screen Icon (ToolType.mthook -> Icons.book)
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
                                    (_selectedFile == null) || _isAnalyzing
                                        ? null
                                        : _analyzeFile,
                                icon: const Icon(Icons.analytics),
                                label: Text(
                                  _isAnalyzing
                                      ? localizations.generating
                                      : localizations.generate,
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
                  if (_isAnalyzing) ...[
                    if (_uploadProgress > 0 && _uploadProgress < 1)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(localizations.uploading),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _uploadProgress,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    if (_downloadProgress > 0 && _downloadProgress < 1)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(localizations.downloading),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _downloadProgress,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    if (_uploadProgress == 0 && _downloadProgress == 0)
                      const Center(child: CircularProgressIndicator()),
                  ] else if (_error != null)
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
                  else if (_successMessage != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _successMessage!,
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
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
