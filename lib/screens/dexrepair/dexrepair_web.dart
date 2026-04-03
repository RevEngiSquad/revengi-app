import 'dart:typed_data';
import 'dart:js_interop';
import 'package:dio/dio.dart' show ResponseType;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:web/web.dart' as web;

class DexRepairScreen extends StatefulWidget {
  const DexRepairScreen({super.key});

  @override
  State<DexRepairScreen> createState() => _DexRepairScreenState();
}

class _DexRepairScreenState extends State<DexRepairScreen> {
  bool _isRepairing = false;
  String? _result;
  String? _error;
  String? _fileName;
  List<int> _dexFileBytes = [];

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
        _fileName = result.files.first.name;
        _dexFileBytes = result.files.first.bytes!;
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

    var checksum = getAdler32(dexData.sublist(12));
    // print("Checksum: ${checksum}");
    dexData.buffer.asByteData().setUint32(8, checksum, Endian.little);

    return dexData;
  }

  Future<void> _repairDexFile() async {
    if (_dexFileBytes.isEmpty) return;

    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _isRepairing = true;
      _error = null;
      _result = null;
    });

    try {
      Uint8List dexData;
      dexData = Uint8List.fromList(_dexFileBytes);

      var repairedDex = repairDexMagic(dexData);
      repairedDex = updateDexHashes(repairedDex, repairSha1: true);
      final filename = '${_fileName!.replaceAll('.dex', '')}_repaired.dex';

      final bytes = Uint8List.fromList(repairedDex);
      String url = web.URL.createObjectURL(
        web.Blob(
          <JSUint8Array>[bytes.toJS].toJS,
          web.BlobPropertyBag(type: ResponseType.bytes.toString()),
        ),
      );
      web.Document htmlDocument = web.document;
      web.HTMLAnchorElement anchor =
          htmlDocument.createElement('a') as web.HTMLAnchorElement;
      anchor.href = url;
      anchor.style.display = filename;
      anchor.download = filename;
      web.document.body!.add(anchor);
      anchor.click();
      anchor.remove();
      setState(() {
        _result = localizations.downloading;
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
                          (_dexFileBytes.isNotEmpty)
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
                            ((_dexFileBytes.isEmpty)) || _isRepairing
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
