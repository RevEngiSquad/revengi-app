import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/utils/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AboutScreen extends StatefulWidget {
  final String currentVersion;

  const AboutScreen({super.key, required this.currentVersion});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  Future<Release>? releaseFuture;

  @override
  void initState() {
    super.initState();
    releaseFuture = fetchLatestRelease();
  }

  Future<Release> fetchLatestRelease() async {
    final prefs = await SharedPreferences.getInstance();
    final releaseKey = "rnotes_${widget.currentVersion}";

    if (prefs.containsKey(releaseKey)) {
      final cachedNotes = prefs.getString(releaseKey);
      return Release(name: "Cached Release", body: cachedNotes!);
    }

    try {
      prefs.getKeys().where((key) => key.startsWith("rnotes_")).forEach((key) {
        prefs.remove(key);
      });

      final response = await dio.get(
        'https://api.github.com/repos/RevEngiSquad/revengi-app/releases/tags/v${widget.currentVersion}',
      );

      if (response.statusCode == 200) {
        final release = Release.fromJson(response.data);
        final filteredBody = _filterBody(release.body);
        await prefs.setString(releaseKey, filteredBody);
        return Release(name: release.name, body: filteredBody);
      } else {
        throw Exception('Failed to load release notes');
      }
    } catch (e) {
      throw Exception('Error fetching release notes: $e');
    }
  }

  String _filterBody(String body) {
    final lines = body.split('\n');
    final filteredLines = <String>[];
    bool skipLine = false;

    for (final line in lines) {
      if (line.startsWith('> [!TIP]') ||
          line.startsWith('> [!NOTE]') ||
          line.startsWith('Full Changelog:')) {
        skipLine = true;
        continue;
      }
      if (skipLine) {
        continue;
      }
      skipLine = false;
      filteredLines.add(line);
    }

    return filteredLines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Scaffold(
        appBar: AppBar(title: Text(localizations.about)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      theme.brightness == Brightness.dark
                          ? 'assets/dark_splash.png'
                          : 'assets/light_splash.png',
                      height: 100,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      localizations.appTitle,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Version ${widget.currentVersion}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FutureBuilder<Release>(
                      future: releaseFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        } else if (snapshot.hasError) {
                          return const SizedBox.shrink();
                        } else if (snapshot.hasData) {
                          final release = snapshot.data!;
                          return Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  GptMarkdown(
                                    release.body,
                                    style: const TextStyle(fontSize: 14),
                                    onLinkTap: (url, title) async {
                                      final uri = Uri.parse(url);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        } else {
                          return const SizedBox.shrink();
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                localizations.developer,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              PersonCard(
                name: developer.name,
                image: Image.asset(developer.iconUrl),
                isDeveloper: true,
              ),
              const SizedBox(height: 32),

              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.attribution),
                  label: Text(localizations.licenses),
                  onPressed: () {
                    showLicensePage(
                      context: context,
                      applicationName: localizations.appTitle,
                      applicationVersion: widget.currentVersion,
                      applicationLegalese: '© ${DateTime.now().year} RevEngi',
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  spacing: 16,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.attach_money),
                      label: Text(localizations.donate),
                      onPressed: () async {
                        final url = Uri.parse('https://revengi.in/donate');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.star),
                      label: const Text('GitHub'),
                      onPressed: () async {
                        final url = Uri.parse(
                          'https://github.com/RevEngiSquad/revengi-app',
                        );
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.email),
                      label: Text(localizations.mail),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                      ),
                      onPressed: () async {
                        final url = Uri.parse('mailto:support@revengi.in');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Release {
  final String name;
  final String body;

  Release({required this.name, required this.body});

  factory Release.fromJson(Map<String, dynamic> json) {
    return Release(name: json['name'] as String, body: json['body'] as String);
  }
}

class Contributor {
  final String name;
  final String iconUrl;

  Contributor({required this.name, required this.iconUrl});

  factory Contributor.fromJson(Map<String, dynamic> json) {
    return Contributor(
      name: json['name'] as String,
      iconUrl: json['icon'] as String,
    );
  }
}

class PersonCard extends StatelessWidget {
  final String name;
  final Widget image;
  final bool isDeveloper;

  const PersonCard({
    super.key,
    required this.name,
    required this.image,
    this.isDeveloper = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipOval(child: SizedBox(width: 60, height: 60, child: image)),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: isDeveloper ? 18 : 14),
            maxLines: 1,
            overflow: TextOverflow.visible,
            softWrap: false,
          ),
        ],
      ),
    );
  }
}

final Contributor developer = Contributor(
  name: 'Abhi',
  iconUrl: 'assets/dev.png',
);
