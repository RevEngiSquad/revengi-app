import 'package:flutter/material.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:yaml/yaml.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

class SmaliGrammarScreen extends StatefulWidget {
  const SmaliGrammarScreen({super.key});

  @override
  State<SmaliGrammarScreen> createState() => _SmaliGrammarScreenState();
}

class _SmaliGrammarScreenState extends State<SmaliGrammarScreen> {
  List<Map<String, dynamic>> _allInstructions = [];
  List<Map<String, dynamic>> _filteredInstructions = [];
  bool _isLoading = true;
  String? _error;
  static const String _prefKey = 'show_smali_info_dialog';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initialize();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final localizations = AppLocalizations.of(context)!;
    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(localizations.briefSummary),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(localizations.smaligInfo2),
                  SizedBox(height: 16),
                  Text("${localizations.keyComponents}:", style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('• opcode: Hexadecimal representation'),
                  Text('• name: Opcode name'),
                  Text('• format: Opcode format'),
                  Text('• syntax: Usual syntax'),
                  Text('• args_info: Argument information'),
                  SizedBox(height: 16),
                  Text("${localizations.registerInformation}:", style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('• vA: Destination register (4-bit, registers 0-15)'),
                  Text('• vAA: 8-bit register (0-255)'),
                  Text('• vAAAA: 16-bit register (0-65535)'),
                  Text('• vB: Source register'),
                  SizedBox(height: 16),
                  Text("${localizations.arguments}:", style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('• #+X: Literal value'),
                  Text('• +X: Relative instruction address offset'),
                  Text('• kind@X: Literal constant pool index'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(localizations.ok),
              ),
              TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool(_prefKey, false);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: Text(localizations.neverShowAgain),
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
          style: const TextStyle(
             fontFamily: 'monospace',
             backgroundColor: Color(0x20808080), 
          ),
        ),
      );
      currentPosition = match.end;
    }

    if (currentPosition < text.length) {
      spans.add(TextSpan(text: text.substring(currentPosition)));
    }

    return SelectableText.rich(
       TextSpan(
          children: spans,
          style: const TextStyle(height: 1.5), 
       ),
    );
  }

  Widget _buildLabeledText(
    BuildContext context,
    String label,
    String content, {
    bool useMonospace = true,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        useMonospace
            ? _buildFormattedText(content)
            : SelectableText(content, style: const TextStyle(height: 1.5)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            pinned: true,
            stretch: false,
            backgroundColor: theme.colorScheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                 localizations.smaliGrammar,
                 style: TextStyle(color: theme.colorScheme.onSurface),
              ),
              centerTitle: true,
              background: Stack(
                fit: StackFit.expand,
                children: [
                   Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                           colors: [
                              theme.colorScheme.primary.withValues(alpha: 0.1),
                              theme.colorScheme.surface,
                           ],
                           begin: Alignment.topCenter,
                           end: Alignment.bottomCenter,
                        ),
                      ),
                   ),
                   Positioned(
                      right: -20,
                      top: -10,
                      child: Opacity(
                        opacity: 0.1,
                        child: Icon(
                           Icons.code,
                           size: 150,
                           color: theme.colorScheme.primary,
                        ),
                      ),
                   ),
                ],
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(80),
              child: Container(
                 padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                 color: theme.colorScheme.surface,
                 child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search opcode, name...',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: _filterInstructions,
                ),
              ),
            ),
          ),

          if (_isLoading)
             const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
             )
          else if (_error != null)
             SliverFillRemaining(
                child: Center(child: Text('Error: $_error', style: TextStyle(color: theme.colorScheme.error))),
             )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final instruction = _filteredInstructions[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: Theme(
                        data: theme.copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          shape: const Border(),
                          collapsedShape: const Border(),
                          textColor: theme.colorScheme.onSurface,
                          iconColor: theme.colorScheme.primary,
                          title: Row(
                            children: [
                              Container(
                                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                 decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                 ),
                                 child: Text(
                                    instruction['opcode'],
                                    style: TextStyle(
                                       fontFamily: 'monospace',
                                       fontWeight: FontWeight.bold,
                                       color: theme.colorScheme.primary,
                                    ),
                                 ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                   instruction['name'],
                                   style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              instruction['short_desc'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                 color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Divider(color: theme.dividerColor.withValues(alpha: 0.5)),
                                  const SizedBox(height: 16),
                                  

                                  GridView.count(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    crossAxisCount: 2,
                                    childAspectRatio: 2.5,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    children: [
                                       _buildLabeledText(context, 'Format', instruction['format'], useMonospace: false),
                                       _buildLabeledText(context, 'Format ID', instruction['format_id'], useMonospace: false),
                                       _buildLabeledText(context, 'Syntax', instruction['syntax'], useMonospace: false),
                                    ],
                                  ),
                                  
                                  const SizedBox(height: 16),
                                  _buildLabeledText(context, 'Arguments', instruction['args_info']),
                                  
                                  const SizedBox(height: 16),
                                  _buildLabeledText(context, 'Description', instruction['long_desc']),
                                  
                                  if (instruction['note'] != null && instruction['note'].isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                         color: Colors.amber.withValues(alpha: 0.1),
                                         borderRadius: BorderRadius.circular(12),
                                         border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                      ),
                                      child: _buildLabeledText(context, 'Note', instruction['note']),
                                    ),
                                  ],
                                  
                                  if (instruction['example'] != null && instruction['example'].isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Text('Example', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: SelectableText(
                                        instruction['example'],
                                        style: const TextStyle(fontFamily: 'monospace'),
                                      ),
                                    ),
                                    if (instruction['example_desc'] != null) ...[
                                        const SizedBox(height: 8),
                                        Text(instruction['example_desc'], style: theme.textTheme.bodySmall),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: _filteredInstructions.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
