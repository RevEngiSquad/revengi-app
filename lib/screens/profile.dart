import 'package:flutter/material.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/screens/user.dart';
import 'package:revengi/utils/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _handleLogout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    await prefs.remove('apiKey');
    await prefs.setBool('isLoggedIn', false);
    dio.options.headers.remove('X-API-Key');

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: FutureBuilder<SharedPreferences>(
        future: SharedPreferences.getInstance(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final prefs = snapshot.data!;
          final username = prefs.getString('username') ?? 'N/A';
          final apiKey = prefs.getString('apiKey') ?? 'N/A';
          final isGuest = username == "guest" || username == "N/A";

          return CustomScrollView(
            slivers: [

              SliverAppBar(
                expandedHeight: 140.0,
                pinned: true,
                stretch: true,
                backgroundColor: theme.colorScheme.surface,
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(
                    localizations.profile,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  centerTitle: true,
                  background: Stack(
                    children: [
                       Positioned(
                          top: -50,
                          right: -50,
                           child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primary.withValues(alpha: 0.1),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                                  blurRadius: 60,
                                  spreadRadius: 20,
                                ),
                              ],
                            ),
                           ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(Icons.logout, color: theme.colorScheme.error),
                    onPressed: () => _handleLogout(context),
                  ),
                ],
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [

                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          child: Text(
                            username.isNotEmpty ? username[0].toUpperCase() : '?',
                            style: theme.textTheme.displayMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        username,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                       Text(
                        isGuest ? 'Guest User' : 'Standard User',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 32),


                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.key, 
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                          title: Text(localizations.apiKey),
                          subtitle: Text(
                            apiKey,
                            style: const TextStyle(fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy_all),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(localizations.copiedToClipboard),
                                ),
                              );
                              Clipboard.setData(ClipboardData(text: apiKey));
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),


                      if (!isGuest) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            localizations.apiRateLimits,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                           decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(16),
                             border: Border.all(color: theme.dividerColor),
                          ),
                          child: Column(
                            children: [
                              _buildLimitTile(context, '/analyze/jni', '2 per min'),
                              Divider(height: 1, indent: 16),
                              _buildLimitTile(context, '/dex2c', '2 per min'),
                              Divider(height: 1, indent: 16),
                              _buildLimitTile(context, '/mthook', '5 per min'),
                              Divider(height: 1, indent: 16),
                              _buildLimitTile(context, '/blutter', '3 per min'),
                              Divider(height: 1, indent: 16),
                              _buildLimitTile(context, '/analyze/flutter', '5 per min'),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLimitTile(BuildContext context, String endpoint, String limit) {
    return ListTile(
      visualDensity: VisualDensity.compact,
      title: Text(
          endpoint,
          style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          limit,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}
