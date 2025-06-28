import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:ollama_dart/ollama_dart.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class OllamaChatScreen extends StatefulWidget {
  const OllamaChatScreen({super.key});

  @override
  OllamaChatScreenState createState() => OllamaChatScreenState();
}

class OllamaChatScreenState extends State<OllamaChatScreen>
    with SingleTickerProviderStateMixin {
  late final OllamaClient client;
  TabController? _tabController;

  List<String> localModels = [];
  String? selectedModel;
  bool pulling = false;
  double pullProgress = 0.0;
  String? pullStatusText;
  bool chatInputEnabled = true;
  String systemMessage =
      "You are a an AI coding & helpful assistant. Your main goal is to follow the USER's instructions at each message. If you are unsure about the answer to the USER's request or how to satiate their request, you should gather more information. This can be done by asking the USER for more information. Bias towards not asking the user for help if you can find the answer yourself. You MUST reply in markdown format. You MUST use code blocks for code. Don't use emojis un-necessarily.";

  final List<ChatMessage> messages = [];
  final TextEditingController _inputController = TextEditingController();
  StreamSubscription<GenerateChatCompletionResponse>? _chatStreamSub;
  Timer? _typingTimer;
  int _typingDotCount = 1;

  final List<String> remoteCatalog = [
    'qwen3:0.6b-q4_K_M',
    'qwen2.5-coder:1.5b',
    'gemma3:1b',
    'llama3.2:1b-instruct-q4_1',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeClient();
  }

  Future<void> _initializeClient() async {
    String baseUrl = await _getBaseUrl();
    try {
      client = OllamaClient(baseUrl: baseUrl);
      await _loadLocalModels();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize Ollama client: $e')),
        );
        setState(() {
          chatInputEnabled = false;
        });
      }
    }
  }

  Future<String> _getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ollamaBaseUrl') ?? 'http://localhost:11434/api';
  }

  Future<void> _loadLocalModels() async {
    try {
      final res = await client.listModels();
      setState(() {
        localModels =
            res.models!.map((m) => m.model).whereType<String>().toList();
      });
    } catch (_) {}
  }

  Future<void> _pullModel(String model) async {
    setState(() {
      pulling = true;
      pullProgress = 0.0;
      pullStatusText = null;
    });

    try {
      final stream = client.pullModelStream(
        request: PullModelRequest(model: model),
      );

      int? total;
      int? completed;

      await for (var status in stream) {
        setState(() {
          total = status.total;
          completed = status.completed;
          if (total != null && completed != null && total! > 0) {
            pullProgress = completed! / total!;
            pullStatusText =
                'Downloading... ${(pullProgress * 100).toStringAsFixed(0)}%';
          } else {
            pullProgress = 0.0;
            pullStatusText = status.status?.toString() ?? '';
          }
        });
      }
      await _loadLocalModels();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to pull model. Is Ollama running?'),
          ),
        );
      }
      setState(() {
        pullStatusText = 'Failed to pull model: ${e.toString()}';
      });
    } finally {
      setState(() {
        pulling = false;
      });
    }
  }

  Future<void> _deleteModel(String model) async {
    // Umm... Yes we have DeleteModelRequest but
    // Currently i've no idea of getting falure, so we use dio
    final dio = Dio();
    final url = 'http://localhost:11434/api/delete';

    try {
      final response = await dio.delete(url, data: {'model': model});

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Model deleted: $model')));
        }
        setState(() {
          localModels.remove(model);
          if (selectedModel == model) selectedModel = null;
        });
      } else if (response.statusCode == 404) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Model not found: $model')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete model: $model')),
          );
        }
      }
    } catch (_) {}
  }

  void _startTypingAnimation() {
    _typingDotCount = 1;
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() {
        _typingDotCount = _typingDotCount % 3 + 1;
        if (messages.isNotEmpty && !messages.last.fromUser) {
          messages.last = messages.last.copyWith(text: '.' * _typingDotCount);
        }
      });
    });
  }

  void _stopTypingAnimation() {
    _typingTimer?.cancel();
    _typingTimer = null;
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty || selectedModel == null || !chatInputEnabled) return;

    setState(() => chatInputEnabled = false);
    _inputController.clear();
    final userMsg = ChatMessage(text: text, fromUser: true);
    setState(() => messages.add(userMsg));

    setState(() => messages.add(ChatMessage(text: '.', fromUser: false)));
    _startTypingAnimation();
    final history = [
      Message(role: MessageRole.system, content: systemMessage),
      ...messages
          .where(
            (m) =>
                !(m.text == '.' || m.text == '..' || m.text == '...') ||
                m.fromUser,
          )
          .map(
            (m) => Message(
              role: m.fromUser ? MessageRole.user : MessageRole.assistant,
              content: m.text,
            ),
          ),
      Message(role: MessageRole.user, content: text),
    ];

    _chatStreamSub?.cancel();
    _chatStreamSub = client
        .generateChatCompletionStream(
          request: GenerateChatCompletionRequest(
            model: selectedModel!,
            messages: history,
            keepAlive: 1,
          ),
        )
        .listen(
          (res) {
            final chunk = res.message.content;
            if (messages.isNotEmpty && !messages.last.fromUser) {
              _stopTypingAnimation();
              setState(
                () =>
                    messages.last = messages.last.copyWith(
                      text:
                          messages.last.text == '.' ||
                                  messages.last.text == '..' ||
                                  messages.last.text == '...'
                              ? chunk
                              : messages.last.text + chunk,
                    ),
              );
            } else {
              _stopTypingAnimation();
              setState(
                () => messages.add(ChatMessage(text: chunk, fromUser: false)),
              );
            }
          },
          onDone: () {
            _stopTypingAnimation();
            setState(() {
              chatInputEnabled = true;
              if (messages.isNotEmpty && !messages.last.fromUser) {
                messages.last = messages.last.copyWith(
                  text: messages.last.text,
                  fromUser: false,
                );
                messages.last = ChatMessage(
                  text: messages.last.text,
                  fromUser: false,
                );
              }
            });
          },
          onError: (err) {
            _stopTypingAnimation();
            setState(() => chatInputEnabled = true);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Failed to send message')),
              );
            }
          },
        );
  }

  @override
  void dispose() {
    _chatStreamSub?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Ollama LLM'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Models'), Tab(text: 'Chat')],
        ),
        actions: [
          if (_tabController?.index == 1)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'System Message',
              onPressed: () async {
                final controller = TextEditingController(text: systemMessage);
                final result = await showDialog<String>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('Set System Message'),
                        content: TextField(
                          controller: controller,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'System message',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed:
                                () => Navigator.pop(
                                  context,
                                  controller.text.trim(),
                                ),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                );
                if (result != null && result.isNotEmpty) {
                  setState(() => systemMessage = result);
                }
              },
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildModelsTab(), _buildChatTab()],
      ),
    );
  }

  Widget _buildModelsTab() {
    final hasLocalModels = localModels.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (hasLocalModels) ...[
              Text(
                'Downloaded Models:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: localModels.length,
                  itemBuilder: (_, i) {
                    final m = localModels[i];
                    final selected = m == selectedModel;
                    return Card(
                      color: selected ? Colors.blue[50] : null,
                      child: ListTile(
                        title: Text(m),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => _deleteModel(m),
                            ),
                            if (selected)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.blue,
                              ),
                          ],
                        ),
                        selected: selected,
                        onTap: () {
                          setState(() => selectedModel = m);
                          _tabController!.animateTo(1);
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            Text(
              'Download a model:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: remoteCatalog.length,
                itemBuilder: (_, i) {
                  final model = remoteCatalog[i];
                  return Card(
                    child: ListTile(
                      title: Text(model),
                      trailing:
                          pulling && selectedModel == model
                              ? SizedBox(
                                width: 200,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: LinearProgressIndicator(
                                        value:
                                            pullProgress > 0
                                                ? pullProgress
                                                : null,
                                      ),
                                    ),
                                    if (pullStatusText != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        pullStatusText!,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                              : IconButton(
                                icon: const Icon(Icons.download),
                                onPressed:
                                    pulling
                                        ? null
                                        : () async {
                                          selectedModel = model;
                                          await _pullModel(model);
                                        },
                              ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'OR\nProvide a model from https://ollama.com/library',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Enter a model name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      selectedModel = value.trim();
                    },
                    onSubmitted: (value) async {
                      if (value.trim().isNotEmpty && !pulling) {
                        setState(() {
                          selectedModel = value.trim();
                          pulling = true;
                        });
                        await _pullModel(selectedModel!);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder:
                      (context) => IconButton(
                        icon: const Icon(Icons.open_in_new),
                        tooltip: 'Open Ollama Library',
                        onPressed: () async {
                          final url = Uri.parse(
                            'https://ollama.com/library/${selectedModel ?? ''}',
                          );
                          if (await canLaunchUrl(url)) {
                            await launchUrl(
                              url,
                              mode: LaunchMode.externalApplication,
                            );
                          } else {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not launch URL'),
                              ),
                            );
                          }
                        },
                      ),
                ),
              ],
            ),
            if (pulling &&
                selectedModel != null &&
                !remoteCatalog.contains(selectedModel))
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: pullProgress > 0 ? pullProgress : null,
                      ),
                    ),
                    if (pullStatusText != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        pullStatusText!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            if (pulling && hasLocalModels)
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: pullProgress > 0 ? pullProgress : null,
                    ),
                  ),
                  if (pullStatusText != null) ...[
                    const SizedBox(width: 8),
                    Text(pullStatusText!, style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatTab() {
    final modelSelected = selectedModel != null;
    return SafeArea(
      child: Column(
        children: [
          if (!modelSelected)
            Expanded(
              child: Center(
                child: Text(
                  'Please select or download a model in the “Models” tab.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: messages.length,
                itemBuilder: (_, i) {
                  final m = messages[i];
                  final isLastAssistant =
                      i == messages.length - 1 &&
                      !m.fromUser &&
                      chatInputEnabled;
                  final brightness = Theme.of(context).brightness;
                  return Align(
                    alignment:
                        m.fromUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            m.fromUser
                                ? brightness == Brightness.dark
                                    ? Colors.blue[900]
                                    : Colors.blue[200]
                                : brightness == Brightness.dark
                                ? Colors.grey[800]
                                : Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child:
                          m.fromUser
                              ? Text(m.text)
                              : (isLastAssistant
                                  ? SelectionArea(
                                    child: GptMarkdown(
                                      m.text,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  )
                                  : SelectableText(m.text)),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    enabled: modelSelected && chatInputEnabled,
                    decoration: InputDecoration(
                      hintText:
                          modelSelected
                              ? 'Type your message…'
                              : 'Select a model to chat',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed:
                      modelSelected && chatInputEnabled ? _sendMessage : null,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(12),
                  ),
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool fromUser;
  ChatMessage({required this.text, this.fromUser = false});
  ChatMessage copyWith({String? text, bool? fromUser}) =>
      ChatMessage(text: text ?? this.text, fromUser: fromUser ?? this.fromUser);
}
