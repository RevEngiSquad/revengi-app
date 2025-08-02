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
      // print("Signature: ${sha1Digest}");
    }

    Adler32 adler32 = Adler32();
    adler32.add(dexData.sublist(12));

    var checksum = adler32.hash;
    adler32.close();
    // print("Checksum: ${checksum}");
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
    return Scaffold(
      appBar: AppBar(title: Text(localizations.dexRepair)),
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
                      localizations.selectFiles("DEX"),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      leading: const Icon(Icons.library_books),
                      title: const Text('Dex File'),
                      subtitle:
                          (_dexFile != null)
                              ? Text(_fileName!)
                              : Text(localizations.noFileSelected),
                      trailing: ElevatedButton(
                        onPressed: _isRepairing ? null : _pickDexFile,
                        child: Text(localizations.chooseFile("File")),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            ((_dexFile == null)) || _isRepairing
                                ? null
                                : _repairDexFile,
                        icon: const Icon(Icons.analytics),
                        label: Text(
                          _isRepairing
                              ? localizations.repairing
                              : localizations.repair,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isRepairing)
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
              Card(
                color: Colors.green[100],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _result!,
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
