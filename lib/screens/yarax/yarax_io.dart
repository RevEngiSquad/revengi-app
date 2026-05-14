import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/platform.dart';

class YaraxScannerScreen extends StatefulWidget {
  const YaraxScannerScreen({super.key});

  @override
  State<YaraxScannerScreen> createState() => _YaraxScannerScreenState();
}

class _YaraxScannerScreenState extends State<YaraxScannerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const MethodChannel _channel = MethodChannel('flutter.native/helper');

  final TextEditingController _ruleController = TextEditingController();

  Uint8List? _compiledRulesBytes;
  String? _compiledRulesFileName;

  String? _selectedFilePath;
  String? _selectedFileName;
  String? _selectedAppName;

  bool _isScanning = false;
  bool _isValidating = false;
  String? _validationResult;
  bool _validationSuccess = false;

  Map<String, dynamic>? _scanResults;
  String? _scanError;

  List<AppInfo> _userApps = [];
  List<AppInfo> _systemApps = [];
  List<AppInfo> _filteredApps = [];
  bool _isLoadingApps = false;
  bool _includeSystemApps = false;
  final TextEditingController _appSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadApps();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ruleController.dispose();
    _appSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() => _isLoadingApps = true);
    try {
      final userApps =
          await InstalledApps.getInstalledApps(false, true, '');
      _userApps = userApps;
      _filteredApps = List.from(_userApps);
      if (_includeSystemApps) {
        final systemApps =
            await InstalledApps.getInstalledApps(true, true, '');
        _systemApps = systemApps;
        _filteredApps = List.from(_userApps)
          ..addAll(_systemApps);
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoadingApps = false);
    }
  }

  void _filterApps(String query) {
    final allApps = List<AppInfo>.from(_userApps);
    if (_includeSystemApps) {
      allApps.addAll(_systemApps);
    }
    setState(() {
      if (query.isEmpty) {
        _filteredApps = allApps;
      } else {
        _filteredApps = allApps
            .where((app) =>
                app.name.toLowerCase().contains(query.toLowerCase()) ||
                app.packageName
                    .toLowerCase()
                    .contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _validateRules() async {
    final source = _ruleController.text.trim();
    if (source.isEmpty) return;

    setState(() {
      _isValidating = true;
      _validationResult = null;
    });

    try {
      final result = await _channel.invokeMethod<String>(
        'yaraxValidateSource',
        {'source': source},
      );
      if (result != null) {
        final parsed = jsonDecode(result) as Map<String, dynamic>;
        if (parsed['valid'] == true) {
          setState(() {
            _validationSuccess = true;
            _validationResult = null;
          });
        } else {
          setState(() {
            _validationSuccess = false;
            _validationResult = parsed['error'] as String?;
          });
        }
      }
    } on PlatformException catch (e) {
      setState(() {
        _validationSuccess = false;
        _validationResult = e.message;
      });
    } finally {
      setState(() => _isValidating = false);
    }
  }

  Future<void> _saveCompiledRules() async {
    final source = _ruleController.text.trim();
    if (source.isEmpty) return;

    setState(() => _isScanning = true);

    try {
      final compiled = await _channel.invokeMethod<Uint8List>(
        'yaraxCompileFromSource',
        {'source': source},
      );
      if (compiled == null) {
        setState(() => _isScanning = false);
        return;
      }

      final dir = Directory(await getDownloadsDirectory());
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final outputPath =
          '${dir.path}${Platform.pathSeparator}rules.yarac';
      await File(outputPath).writeAsBytes(compiled);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!
                  .yaraxCompiledRulesSaved(outputPath),
            ),
          ),
        );
      }
    } on PlatformException catch (e) {
      _showError(e.message ?? 'Compilation failed');
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _loadYaracFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yarac'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      setState(() {
        _compiledRulesBytes = bytes;
        _compiledRulesFileName = result.files.single.name;
      });
    }
  }

  Future<void> _pickFileToScan() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _selectedFileName = result.files.single.name;
        _selectedAppName = null;
        _scanResults = null;
        _scanError = null;
      });
    }
  }

  Future<void> _scan() async {
    final bool usingSource = _tabController.index == 0;
    final String? filePath = _selectedFilePath;

    setState(() {
      _isScanning = true;
      _scanResults = null;
      _scanError = null;
    });

    try {
      String result;

      if (usingSource) {
        final source = _ruleController.text.trim();
        if (source.isEmpty) {
          setState(() => _isScanning = false);
          return;
        }
        if (filePath != null) {
          result = await _channel.invokeMethod<String>(
            'yaraxScanWithSource',
            {'source': source, 'filePath': filePath},
          ) ?? '{"matches":[],"nonMatching":[]}';
        } else {
          setState(() {
            _isScanning = false;
            _scanError = 'No file selected to scan';
          });
          return;
        }
      } else {
        if (_compiledRulesBytes == null) {
          setState(() => _isScanning = false);
          return;
        }
        if (filePath != null) {
          result = await _channel.invokeMethod<String>(
            'yaraxScanWithCompiledRules',
            {
              'serializedRules': _compiledRulesBytes,
              'filePath': filePath,
            },
          ) ?? '{"matches":[],"nonMatching":[]}';
        } else {
          setState(() {
            _isScanning = false;
            _scanError = 'No file selected to scan';
          });
          return;
        }
      }

      final parsed = jsonDecode(result) as Map<String, dynamic>;
      setState(() {
        _scanResults = parsed;
        if (parsed.containsKey('error')) {
          _scanError = parsed['error'] as String?;
        }
      });
    } on PlatformException catch (e) {
      setState(() => _scanError = e.message ?? 'Scan failed');
    } catch (e) {
      setState(() => _scanError = e.toString());
    } finally {
      setState(() => _isScanning = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _showAppPicker() {
    _appSearchController.clear();
    _filterApps('');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Text(
                            AppLocalizations.of(context)!.yaraxScanInstalledApp,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _appSearchController,
                        decoration: InputDecoration(
                          hintText: AppLocalizations.of(context)!.searchApps,
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (value) {
                          _filterApps(value);
                          setSheetState(() {});
                        },
                      ),
                    ),
                    SwitchListTile(
                      title: Text(AppLocalizations.of(context)!.includeSystemApps),
                      value: _includeSystemApps,
                      onChanged: (val) async {
                        setSheetState(() => _includeSystemApps = val);
                        await _loadApps();
                        _filterApps(_appSearchController.text);
                        setSheetState(() {});
                      },
                    ),
                    Expanded(
                      child: _isLoadingApps
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: _filteredApps.length,
                              itemBuilder: (context, index) {
                                final app = _filteredApps[index];
                                return ListTile(
                                  leading: app.icon != null
                                      ? Image.memory(app.icon!, width: 40, height: 40)
                                      : const Icon(Icons.android, size: 40),
                                  title: Text(app.name,
                                      style: const TextStyle(fontSize: 14)),
                                  subtitle: Text(app.packageName,
                                      style: const TextStyle(fontSize: 12)),
                                  onTap: () {
                                    setState(() {
                                      _selectedFilePath = app.apkPath;
                                      _selectedFileName = app.name;
                                      _selectedAppName = app.name;
                                      _scanResults = null;
                                      _scanError = null;
                                    });
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildWriteRulesTab() {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.code, size: 16, color: Colors.white70),
                        const SizedBox(width: 8),
                        Text(
                          localizations.yaraxWriteRules,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _ruleController,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      decoration: InputDecoration(
                        hintText: 'rule example {\n  strings:\n    \$a = "text" ascii wide\n  condition:\n    \$a\n}',
                        hintStyle: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(12),
                      ),
                      onChanged: (_) {
                        setState(() {
                          _validationResult = null;
                          _validationSuccess = false;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_validationResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _validationResult!,
                style: TextStyle(
                  color: _validationSuccess ? Colors.green : Colors.redAccent,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          if (_validationSuccess)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                localizations.yaraxRulesValid,
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isValidating ? null : _validateRules,
                  icon: _isValidating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(localizations.yaraxValidate),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: const BorderSide(color: Colors.green),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isScanning ? null : _saveCompiledRules,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(localizations.yaraxSaveCompiled),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadCompiledTab() {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
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
                  Icons.description_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _compiledRulesFileName != null
                      ? _compiledRulesFileName!
                      : localizations.yaraxSelectYaracFile,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _compiledRulesFileName != null
                        ? Colors.green
                        : theme.textTheme.bodyMedium?.color,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadYaracFile,
                  icon: const Icon(Icons.file_upload),
                  label: Text(localizations.chooseFile('YARAC')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
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
        ],
      ),
    );
  }

  Widget _buildScanTargetSection() {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final borderColor = theme.dividerColor;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              localizations.yaraxSelectFile,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (_selectedFileName != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    _selectedAppName != null
                        ? Icons.android
                        : Icons.insert_drive_file,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedAppName ?? _selectedFileName ?? '',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _selectedFilePath = null;
                        _selectedFileName = null;
                        _selectedAppName = null;
                        _scanResults = null;
                        _scanError = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickFileToScan,
                    icon: const Icon(Icons.folder_open),
                    label: Text(localizations.chooseFile('file')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showAppPicker,
                    icon: const Icon(Icons.android),
                    label: Text(localizations.yaraxScanInstalledApp),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton() {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final bool usingSource = _tabController.index == 0;
    final bool hasRules =
        usingSource ? _ruleController.text.trim().isNotEmpty : _compiledRulesBytes != null;
    final bool hasTarget = _selectedFilePath != null;

    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: (hasRules && hasTarget && !_isScanning) ? _scan : null,
        icon: _isScanning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.shield_outlined),
        label: Text(
          _isScanning
              ? localizations.yaraxScanning
              : localizations.yaraxScan,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildResultsSection() {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_isScanning) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_scanError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Error',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _scanError!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_scanResults == null) return const SizedBox.shrink();

    final matches = (_scanResults!['matches'] as List?) ?? [];
    final nonMatching = (_scanResults!['nonMatching'] as List?) ?? [];

    if (matches.isEmpty && nonMatching.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            localizations.yaraxNoMatches,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizations.yaraxScanResults,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (matches.isNotEmpty) ...[
          Text(
            '${localizations.yaraxMatchingRules} (${matches.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 8),
          ...matches.map((match) => _buildRuleCard(match, theme)),
        ],
        if (nonMatching.isNotEmpty) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            title: Text(
              '${localizations.yaraxNonMatchingRules} (${nonMatching.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            initiallyExpanded: false,
            children: nonMatching.map<Widget>((rule) {
              return ListTile(
                dense: true,
                leading: const Icon(Icons.remove_circle_outline,
                    size: 18, color: Colors.grey),
                title: Text(rule['identifier'] as String? ?? ''),
                subtitle: Text(rule['namespace'] as String? ?? '',
                    style: const TextStyle(fontSize: 11)),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildRuleCard(dynamic match, ThemeData theme) {
    final rule = match as Map<String, dynamic>;
    final identifier = rule['identifier'] as String? ?? '';
    final namespace = rule['namespace'] as String? ?? '';
    final tags = (rule['tags'] as List?)?.cast<String>() ?? [];
    final patterns = (rule['patterns'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                identifier,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            if (tags.isNotEmpty)
              ...tags.map((tag) => Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )),
          ],
        ),
        children: [
          if (namespace != 'default')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Namespace: $namespace',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
          if (patterns.isNotEmpty) ...[
            Text(
              AppLocalizations.of(context)!.yaraxPatterns,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 4),
            ...patterns.map((p) {
              final pat = p as Map<String, dynamic>;
              final patId = pat['identifier'] as String? ?? '';
              final matches = (pat['matches'] as List?) ?? [];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patId,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                    const SizedBox(height: 4),
                    ...matches.map((m) {
                      final matchData = m as Map<String, dynamic>;
                      final offset = matchData['offset'] as int? ?? 0;
                      final length = matchData['length'] as int? ?? 0;
                      final hexData = matchData['data'] as String? ?? '';
                      final dataStr = matchData['data_str'] as String?;
                      final xorKey = matchData['xor_key'];

                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${AppLocalizations.of(context)!.yaraxOffset}: $offset',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  '${AppLocalizations.of(context)!.yaraxLength}: $length',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                ),
                                if (xorKey != null)
                                  Text(
                                    '  XOR: $xorKey',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.textTheme.bodySmall?.color,
                                    ),
                                  ),
                                const Spacer(),
                                if (hexData.isNotEmpty)
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                          ClipboardData(text: hexData));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(content: Text('Copied to clipboard')),
                                      );
                                    },
                                    child: const Icon(Icons.copy, size: 14),
                                  ),
                              ],
                            ),
                            if (dataStr != null && dataStr.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  dataStr,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: theme.colorScheme.primary,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            stretch: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                localizations.yaraxScanner,
                style: TextStyle(
                  color: theme.textTheme.titleLarge?.color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
              titlePadding: const EdgeInsets.only(bottom: 64),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFEF4444).withValues(alpha: 0.15),
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
                        Icons.shield_outlined,
                        size: 200,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: localizations.yaraxWriteRules),
                Tab(text: localizations.yaraxLoadCompiled),
              ],
            ),
          ),
        ],
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 320,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildWriteRulesTab(),
                    _buildLoadCompiledTab(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildScanTargetSection(),
              const SizedBox(height: 16),
              _buildScanButton(),
              const SizedBox(height: 16),
              _buildResultsSection(),
            ],
          ),
        ),
      ),
    );
  }
}