import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:revengi/screens/splash.dart';

class UninstallScreen extends StatelessWidget {
  const UninstallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.greenAccent, width: 2),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                localizations.uninstallWarning,
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 24,
                  fontFamily: 'Courier',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.black,
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const SplashScreen()),
                  );
                },
                child: Text(
                  localizations.iLoveThisApp,
                  style: TextStyle(fontFamily: 'Courier'),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                onPressed: () => SystemNavigator.pop(),
                child: Text(
                  localizations.iDonTLoveThisApp,
                  style: TextStyle(fontFamily: 'Courier'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
