import 'package:flutter/material.dart';
import 'package:yaml/yaml.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class SmaliInstructionDialog extends StatefulWidget {
  const SmaliInstructionDialog({super.key});

  @override
  State<SmaliInstructionDialog> createState() => _SmaliInstructionDialogState();
}

class _SmaliInstructionDialogState extends State<SmaliInstructionDialog> {
  List<Map<String, dynamic>> _allInstructions = [];
  List<Map<String, dynamic>> _filteredInstructions = [];
  bool _isLoading = true;
  String? _error;
  static const String _prefKey = 'show_smali_info_dialog';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final shouldShowDialog = prefs.getBool(_prefKey) ?? true;

    if (shouldShowDialog && mounted) {
      await _showInfoDialog();
    }

    await _loadInstructions();
  }

  Future<void> _showInfoDialog() async {
    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Smali Grammar Information'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'This view contains the grammar for the Smali language (Dalvik Bytecode Opcodes).',
                  ),
                  SizedBox(height: 16),
                  Text('Key components:'),
                  Text('• opcode: Hexadecimal representation'),
                  Text('• name: Opcode name'),
                  Text('• format: Opcode format'),
                  Text('• syntax: Usual syntax'),
                  Text('• args_info: Argument information'),
                  SizedBox(height: 16),
                  Text('Register information:'),
                  Text('• vA: Destination register (4-bit, registers 0-15)'),
                  Text('• vAA: 8-bit register (0-255)'),
                  Text('• vAAAA: 16-bit register (0-65535)'),
                  Text('• vB: Source register'),
                  SizedBox(height: 16),
                  Text('Arguments:'),
                  Text('• #+X: Literal value'),
                  Text('• +X: Relative instruction address offset'),
                  Text('• kind@X: Literal constant pool index'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_prefKey, false);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Never show again'),
              ),
            ],
          ),
    );
  }

  Future<void> _loadInstructions() async {
    try {
      final yamlContent = await rootBundle.loadString(
        'assets/smali_grammar.yaml',
      );
      final yamlDoc = loadYaml(yamlContent) as YamlList;

      _allInstructions =
          yamlDoc.map((instruction) {
            return {
              'opcode': instruction['opcode'] as String,
              'name': instruction['name'] as String,
              'format': instruction['format'] as String,
              'format_id': instruction['format_id'] as String,
              'syntax': instruction['syntax'] as String,
              'args_info': instruction['args_info'] as String,
              'short_desc': instruction['short_desc'] as String,
              'long_desc': instruction['long_desc'] as String,
              'note': instruction['note'],
              'example': instruction['example'],
              'example_desc': instruction['example_desc'],
            };
          }).toList();

      _allInstructions.sort((a, b) => a['name'].compareTo(b['name']));
      _filteredInstructions = List.from(_allInstructions);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterInstructions(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredInstructions = List.from(_allInstructions);
      } else {
        _filteredInstructions =
            _allInstructions
                .where(
                  (instruction) =>
                      instruction['name'].toLowerCase().contains(
                        query.toLowerCase(),
                      ) ||
                      instruction['opcode'].toLowerCase().contains(
                        query.toLowerCase(),
                      ) ||
                      instruction['short_desc'].toLowerCase().contains(
                        query.toLowerCase(),
                      ),
                )
                .toList();
      }
    });
  }

  Widget _buildFormattedText(String text) {
    final List<InlineSpan> spans = [];
    final regex = RegExp(r'`([^`]+)`');
    int currentPosition = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > currentPosition) {
        spans.add(TextSpan(text: text.substring(currentPosition, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      );
      currentPosition = match.end;
    }

    if (currentPosition < text.length) {
      spans.add(TextSpan(text: text.substring(currentPosition)));
    }

    return SelectableText.rich(TextSpan(children: spans));
  }

  Widget _buildLabeledText(
    String label,
    String content, {
    bool useMonospace = true,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          '$label: ',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Expanded(
          child:
              useMonospace
                  ? _buildFormattedText(content)
                  : SelectableText(content),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Error loading Smali grammar: $_error',
            style: TextStyle(color: Colors.red[900]),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search by name, opcode or description...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
            onChanged: _filterInstructions,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _filteredInstructions.length,
            itemBuilder: (context, index) {
              final instruction = _filteredInstructions[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ExpansionTile(
                  title: Text(
                    '${instruction['name']} (${instruction['opcode']})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    instruction['short_desc'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabeledText(
                            'Format',
                            instruction['format'],
                            useMonospace: false,
                          ),
                          _buildLabeledText(
                            'Format ID',
                            instruction['format_id'],
                            useMonospace: false,
                          ),
                          _buildLabeledText(
                            'Syntax',
                            instruction['syntax'],
                            useMonospace: false,
                          ),
                          const SizedBox(height: 8),
                          _buildLabeledText(
                            'Arguments',
                            instruction['args_info'],
                          ),
                          const SizedBox(height: 8),
                          _buildLabeledText(
                            'Description',
                            instruction['long_desc'],
                          ),
                          if (instruction['note'] != null &&
                              instruction['note'].isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _buildLabeledText('Note', instruction['note']),
                          ],
                          if (instruction['example'] != null &&
                              instruction['example'].isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const SelectableText(
                              'Example:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: SelectableText(
                                instruction['example'],
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                            ),
                            if (instruction['example_desc'] != null)
                              _buildLabeledText(
                                'Example Desc.',
                                instruction['example_desc'],
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
