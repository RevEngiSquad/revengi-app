import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/platform.dart';
import 'package:revengi/utils/dartinfo.dart';

class FlutterAnalysisScreen extends StatefulWidget {
  const FlutterAnalysisScreen({super.key});

  @override
  State<FlutterAnalysisScreen> createState() => _FlutterAnalysisScreenState();
}

class _FlutterAnalysisScreenState extends State<FlutterAnalysisScreen> {
  File? _libappFile;
  File? _libflutterFile;
  bool _isAnalyzing = false;
  String? _result;
  String? _error;
  String? _fileName;
  List<int> _libappBytes = [];
  List<int> _libflutterBytes = [];

  Future<void> _pickLibappFile() async {
    final localizations = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null) {
      if (isWeb()) {
        setState(() {
          _fileName = result.files.first.name;
          _libappBytes = result.files.first.bytes!;
          _libappFile = null;
          _error = null;
          _result = null;
        });
      } else {
        setState(() {
          _libappFile = File(result.files.single.path!);
          _fileName = result.files.first.name;
          _error = null;
          _result = null;
        });
      }

      final bytes = isWeb() ? _libappBytes : await _libappFile!.readAsBytes();
      final elfMagic = bytes.sublist(0, 4);
      if (elfMagic[0] != 0x7f ||
          elfMagic[1] != 0x45 ||
          elfMagic[2] != 0x4c ||
          elfMagic[3] != 0x46) {
        setState(() {
          _error = localizations.selectValidFile("ELF");
          _libappFile = null;
          _libappBytes = [];
        });
      }
      if (_fileName != 'libapp.so') {
        setState(() {
          _error = localizations.selectValidFile("libapp.so");
          _libappFile = null;
          _libappBytes = [];
        });
      }
    }
  }

  Future<void> _pickLibflutterFile() async {
    final localizations = AppLocalizations.of(context)!;
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null) {
      if (isWeb()) {
        setState(() {
          _fileName = result.files.first.name;
          _libflutterBytes = result.files.first.bytes!;
          _libflutterFile = null;
          _error = null;
          _result = null;
        });
      } else {
        setState(() {
          _fileName = result.files.first.name;
          _libflutterFile = File(result.files.single.path!);
          _error = null;
          _result = null;
        });
      }
      final bytes =
          isWeb() ? _libflutterBytes : await _libflutterFile!.readAsBytes();
      final elfMagic = bytes.sublist(0, 4);
      if (elfMagic[0] != 0x7f ||
          elfMagic[1] != 0x45 ||
          elfMagic[2] != 0x4c ||
          elfMagic[3] != 0x46) {
        setState(() {
          _error = localizations.selectValidFile("ELF");
          _libflutterFile = null;
          _libflutterBytes = [];
        });
      }
      if (_fileName != 'libflutter.so') {
        setState(() {
          _error = localizations.selectValidFile("libflutter.so");
          _libflutterFile = null;
          _libflutterBytes = [];
        });
      }
    }
  }

  Future<void> _analyzeFiles() async {
    if ((isWeb() && (_libappBytes.isEmpty || _libflutterBytes.isEmpty)) ||
        (!isWeb() && (_libappFile == null || _libflutterFile == null))) {
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _error = null;
      _result = null;
    });

    try {
      final elfParser = ElfParser(
        flutterLibPath: isWeb() ? null : _libflutterFile?.path,
        appLibPath: isWeb() ? null : _libappFile?.path,
        flutterLibBytes: isWeb() ? Uint8List.fromList(_libflutterBytes) : null,
        appLibBytes: isWeb() ? Uint8List.fromList(_libappBytes) : null,
      );

      final rodataInfo = elfParser.extractRodataInfo();
      final snapshotInfo = elfParser.extractSnapshotHashFlags();
      String? dartVersion = rodataInfo?.$2;

      if (dartVersion == null && rodataInfo != null) {
        final sdkInfo = await elfParser.getSdkInfo();
        dartVersion = sdkInfo?.dartVersion;
      }
      final result = StringBuffer();
      if (rodataInfo != null) {
        result.writeln('Engine IDs: ${rodataInfo.$1.join(", ")}');
        result.writeln('Dart Version: ${dartVersion ?? "unknown"}');
        result.writeln('Architecture: ${rodataInfo.$3}');
      }

      if (snapshotInfo != null) {
        result.writeln('Snapshot Hash: ${snapshotInfo.$1}');
        result.writeln('Flags: [${snapshotInfo.$2.join(", ")}]');
      }

      setState(() {
        _result = result.toString();
      });
    } catch (e) {
      setState(() {
        _error = 'An error occurred during analysis: $e';
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
                localizations.flutterAnalysis,
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
                        Icons.flutter_dash,
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
                          Icons.library_books,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          localizations.selectFiles('Library'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        _buildFileTile(
                          theme: theme,
                          title: 'libapp',
                          subtitle:
                              (_libappFile != null || _libappBytes.isNotEmpty)
                                  ? isWeb()
                                      ? 'libapp.so'
                                      : _libappFile!.path
                                          .split(Platform.pathSeparator)
                                          .last
                                  : localizations.noFileSelected,
                          isFileSelected:
                              _libappFile != null || _libappBytes.isNotEmpty,
                          onPressed: _isAnalyzing ? null : _pickLibappFile,
                          buttonText: localizations.chooseFile("File"),
                        ),
                        Divider(height: 24, color: borderColor),
                        _buildFileTile(
                          theme: theme,
                          title: 'libflutter',
                          subtitle:
                              (_libflutterFile != null ||
                                      _libflutterBytes.isNotEmpty)
                                  ? isWeb()
                                      ? 'libflutter.so'
                                      : _libflutterFile!.path
                                          .split(Platform.pathSeparator)
                                          .last
                                  : localizations.noFileSelected,
                          isFileSelected:
                              _libflutterFile != null ||
                              _libflutterBytes.isNotEmpty,
                          onPressed: _isAnalyzing ? null : _pickLibflutterFile,
                          buttonText: localizations.chooseFile("File"),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed:
                                (isWeb()
                                            ? (_libappBytes.isEmpty ||
                                                _libflutterBytes.isEmpty)
                                            : (_libappFile == null ||
                                                _libflutterFile == null)) ||
                                        _isAnalyzing
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
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
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
                            child: SelectableText.rich(
                              TextSpan(
                                style: const TextStyle(fontSize: 14),
                                children:
                                    _result!.split('\n').map((line) {
                                      if (line.isEmpty) {
                                        return const TextSpan(text: '\n');
                                      }
                                      final parts = line.split(': ');
                                      if (parts.length == 2) {
                                        return TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '${parts[0]}: ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                            ),
                                            TextSpan(
                                              text: parts[1],
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            const TextSpan(text: '\n'),
                                          ],
                                        );
                                      }
                                      return TextSpan(text: '$line\n');
                                    }).toList(),
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

  Widget _buildFileTile({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required bool isFileSelected,
    required VoidCallback? onPressed,
    required String buttonText,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isFileSelected ? Colors.green : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            elevation: 0,
          ),
          child: Text(buttonText),
        ),
      ],
    );
  }
}
