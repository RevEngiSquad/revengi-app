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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            stretch: true,
            backgroundColor: theme.colorScheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
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
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 48),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surface,
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.2,
                              ),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          theme.brightness == Brightness.dark
                              ? 'assets/dark_splash.png'
                              : 'assets/light_splash.png',
                          height: 80,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        localizations.appTitle,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Version ${widget.currentVersion}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "What's New",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<Release>(
                    future: releaseFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      } else if (snapshot.hasError) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Could not load release notes.',
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        );
                      } else if (snapshot.hasData) {
                        final release = snapshot.data!;
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: theme.dividerColor),
                          ),
                          child: GptMarkdown(
                            release.body,
                            style: theme.textTheme.bodyMedium!,
                            onLinkTap: (url, title) async {
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                          ),
                        );
                      } else {
                        return const SizedBox.shrink();
                      }
                    },
                  ),
                  const SizedBox(height: 32),

                  Text(
                    localizations.developer,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            developer.iconUrl,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                developer.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Lead Developer',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      _ActionButton(
                        icon: Icons.attribution,
                        label: localizations.licenses,
                        onTap: () {
                          showLicensePage(
                            context: context,
                            applicationName: localizations.appTitle,
                            applicationVersion: widget.currentVersion,
                            applicationLegalese:
                                '© ${DateTime.now().year} RevEngi',
                          );
                        },
                      ),
                      _ActionButton(
                        icon: Icons.attach_money,
                        label: localizations.donate,
                        onTap: () => _launch('https://revengi.in/donate'),
                      ),
                      _ActionButton(
                        icon: Icons.star,
                        label: 'GitHub',
                        onTap:
                            () => _launch(
                              'https://github.com/RevEngiSquad/revengi-app',
                            ),
                      ),
                      _ActionButton(
                        icon: Icons.email,
                        label: localizations.mail,
                        onTap: () => _launch('mailto:support@revengi.in'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launch(String urlString) async {
    final url = Uri.parse(urlString);
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
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

final Contributor developer = Contributor(
  name: 'Abhi',
  iconUrl: 'assets/dev.png',
);
