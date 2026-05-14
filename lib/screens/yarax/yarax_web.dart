import 'package:flutter/material.dart';
import 'package:revengi/l10n/app_localizations.dart';

class YaraxScannerScreen extends StatelessWidget {
  const YaraxScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(localizations.yaraxScanner)),
      body: Center(
        child: Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(
                  localizations.yaraxUnsupportedOnWeb,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  localizations.featureNeedsApp,
                  style: const TextStyle(fontSize: 15, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}