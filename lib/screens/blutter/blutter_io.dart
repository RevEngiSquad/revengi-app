import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
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
      setState(() {
        if (e.response?.data != null &&
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
                localizations.blutter,
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
                        Icons.build,
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
                          _apkFile != null
                              ? _apkFile!.path
                                  .split(Platform.pathSeparator)
                                  .last
                              : localizations.selectFiles("APK/Zip"),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color:
                                _apkFile != null
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
                                onPressed: _isAnalyzing ? null : _pickApkFile,
                                icon: const Icon(Icons.file_upload),
                                label: Text(localizations.chooseFile("File")),
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
                                    (_apkFile == null || _isAnalyzing)
                                        ? null
                                        : _analyzeFiles,
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color:
                          theme.brightness == Brightness.dark
                              ? Colors.orange.withValues(alpha: 0.1)
                              : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GptMarkdown(
                            localizations.blutterNote,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ),
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
                          const Icon(
                            Icons.check_circle_outline,
                            color: Colors.green,
                          ),
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
