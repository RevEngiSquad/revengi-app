import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/platform.dart';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';

class DexRepairScreen extends StatefulWidget {
  const DexRepairScreen({super.key});

  @override
  State<DexRepairScreen> createState() => _DexRepairScreenState();
}

class _DexRepairScreenState extends State<DexRepairScreen> {
  File? _dexFile;
  bool _isRepairing = false;
  String? _result;
  String? _error;
  String? _fileName;

  // ignore: non_constant_identifier_names
  final List<List<int>> DEX_MAGIC_VERSIONS = [
    [100, 101, 120, 10, 48, 51, 53, 0], // "dex\n035\0"
    [100, 101, 120, 10, 48, 51, 55, 0], // "dex\n037\0"
    [100, 101, 120, 10, 48, 51, 56, 0], // "dex\n038\0"
    [100, 101, 120, 10, 48, 51, 57, 0], // "dex\n039\0"
    [100, 101, 120, 10, 48, 51, 28, 0], // "dex\n040\0"
  ];

  Future<void> _pickDexFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);

    if (result != null) {
      setState(() {
        _dexFile = File(result.files.single.path!);
        _fileName = result.files.first.name;
        _error = null;
        _result = null;
      });
    }
  }

  bool isValidDexMagic(Uint8List dexFile) {
    return DEX_MAGIC_VERSIONS.any(
      (magic) => dexFile.sublist(0, 8).toList().toString() == magic.toString(),
    );
  }

  Uint8List repairDexMagic(Uint8List dexData) {
    if (!isValidDexMagic(dexData)) {
      dexData.setAll(0, DEX_MAGIC_VERSIONS[0]);
    }
    return dexData;
  }

  Uint8List updateDexHashes(Uint8List dexData, {bool repairSha1 = false}) {
    if (repairSha1) {
      var sha1Digest = sha1.convert(dexData.sublist(32));
      dexData.setAll(12, sha1Digest.bytes);
    }

    Adler32 adler32 = Adler32();
    adler32.add(dexData.sublist(12));

    var checksum = adler32.hash;
    adler32.close();
    dexData.buffer.asByteData().setUint32(8, checksum, Endian.little);

    return dexData;
  }

  Future<void> _repairDexFile() async {
    if (_dexFile == null) return;

    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _isRepairing = true;
      _error = null;
      _result = null;
    });

    try {
      Uint8List dexData;
      dexData = await _dexFile!.readAsBytes();

      var repairedDex = repairDexMagic(dexData);
      repairedDex = updateDexHashes(repairedDex, repairSha1: true);

      final Directory dir = Directory(await getDownloadsDirectory());
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      var outputPath = File(
        '${dir.path}/repaired_${_fileName ?? _dexFile!.path.split(Platform.pathSeparator).last}',
      );
      if (outputPath.existsSync()) {
        final randomNumber = DateTime.now().millisecondsSinceEpoch;
        outputPath = File(
          '${dir.path}/repaired_${randomNumber}_${_fileName ?? _dexFile!.path.split(Platform.pathSeparator).last}',
        );
      }
      await outputPath.writeAsBytes(repairedDex);
      setState(() {
        _result = localizations.repairDexSuccess(outputPath.path);
      });
    } catch (e) {
      setState(() {
        _error = localizations.repairDexError(e.toString());
      });
    } finally {
      setState(() {
        _isRepairing = false;
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
                localizations.dexRepair,
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
                        Icons.auto_fix_high,
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
                          _fileName ?? localizations.selectFiles("DEX"),
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
                        ElevatedButton.icon(
                          onPressed: _isRepairing ? null : _pickDexFile,
                          icon: const Icon(Icons.file_upload),
                          label: Text(localizations.chooseFile("File")),
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
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_dexFile == null) || _isRepairing
                              ? null
                              : _repairDexFile,
                      icon:
                          _isRepairing
                              ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                              : const Icon(Icons.analytics),
                      label: Text(
                        _isRepairing
                            ? localizations.repairing
                            : localizations.repair.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                  const SizedBox(height: 24),
                  if (_error != null)
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
                              _result!,
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
