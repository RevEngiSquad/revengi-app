import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:revengi/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:revengi/utils/dio.dart';
import 'package:revengi/screens/home.dart';
import 'package:revengi/utils/platform.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final response = await dio.post(
          _isLogin ? '/login' : '/register',
          data:
              _isLogin
                  ? {
                    'username': _usernameController.text,
                    'password': _passwordController.text,
                  }
                  : {
                    'username': _usernameController.text,
                    'email': _emailController.text,
                    'password': _passwordController.text,
                  },
        );

        if (mounted) {
          // Save user session data
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);
          await prefs.setBool('isGuestUser', false);
          await prefs.setString('username', _usernameController.text);

          final apiKey = response.data['api_key'];
          if (apiKey != null) {
            await prefs.setString('apiKey', apiKey);
            dio.options.headers['X-API-Key'] = apiKey;
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${_isLogin ? AppLocalizations.of(context)!.login : AppLocalizations.of(context)!.register} successful',
                ),
              ),
            );
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const DashboardScreen()),
            );
          }
        }
      } on DioException catch (e) {
        String errorMessage = 'An error occurred';
        if (e.response?.data != null && e.response?.data['detail'] != null) {
          errorMessage = e.response?.data['detail'];
        } else if (e.type == DioExceptionType.connectionTimeout) {
          errorMessage = 'Connection timeout';
        } else if (e.type == DioExceptionType.connectionError) {
          errorMessage = 'No internet connection';
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;

    final card = Card(
      color:
          Theme.of(context).brightness == Brightness.dark
              ? const Color.fromARGB(87, 18, 18, 18)
              : const Color.fromARGB(177, 245, 245, 245),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isLogin
                    ? localizations.welcomeBack
                    : localizations.createAccount,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: localizations.username,
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return localizations.enterUsername;
                  }
                  if (value.length < 5 || value.length > 15) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(localizations.usernameLimit),
                        duration: Duration(seconds: 3),
                      ),
                    );
                    return ' ';
                  }
                  if (!RegExp(
                    r'^[a-zA-Z0-9]([_]?[a-zA-Z0-9]){4,14}$',
                  ).hasMatch(value)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(localizations.usernameCond),
                        duration: Duration(seconds: 3),
                      ),
                    );
                    return ' ';
                  }
                  return null;
                },
              ),
              if (!_isLogin) const SizedBox(height: 16),
              if (!_isLogin)
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: localizations.email,
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return localizations.enterEmail;
                    }
                    if (!RegExp(
                      r'^[a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)*@gmail\.com$',
                    ).hasMatch(value)) {
                      return localizations.emailCond;
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: localizations.password,
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed:
                        () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                obscureText: _obscurePassword,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return localizations.enterPassword;
                  }
                  if (value.length < 8) {
                    return localizations.passLen;
                  }
                  if (!_isLogin) {
                    if (!RegExp(
                      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&\.])[A-Za-z\d@$!%*?&\.]{8,}$',
                    ).hasMatch(value)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Password must include a lowercase, uppercase, number, special character (@\$!%*?&), and be 8+ chars.',
                          ),
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return ' ';
                    }
                  }
                  return null;
                },
              ),
              if (!_isLogin) const SizedBox(height: 16),
              if (!_isLogin)
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: localizations.confirmPassword,
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return localizations.pleaseConfirmPassword;
                    }
                    if (value != _passwordController.text) {
                      return localizations.passMisMatch;
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? const Color.fromARGB(37, 18, 18, 18)
                            : const Color.fromARGB(177, 245, 245, 245),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isLoading
                          ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Text(
                            _isLogin
                                ? localizations.login
                                : localizations.register,
                            style: const TextStyle(fontSize: 16),
                          ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed:
                    _isLoading
                        ? null
                        : () {
                          setState(() {
                            _isLogin = !_isLogin;
                          });
                        },
                child: Text(
                  _isLogin
                      ? localizations.suggestRegister
                      : localizations.suggestLogin,
                  style: TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed:
                    _isLoading
                        ? null
                        : () async {
                          final navigator = Navigator.of(context);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('isLoggedIn', true);
                          await prefs.setString('username', 'guest');
                          await prefs.setBool('isGuestUser', true);

                          if (mounted) {
                            navigator.pushReplacement(
                              MaterialPageRoute(
                                builder: (context) => const DashboardScreen(),
                              ),
                            );
                          }
                        },
                child: Text(
                  localizations.continueAsGuest,
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.black, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child:
                    isWeb()
                        ? Center(child: SizedBox(width: 400, child: card))
                        : isWindows()
                        ? Center(child: SizedBox(width: 400, child: card))
                        : isLinux()
                        ? Center(child: SizedBox(width: 400, child: card))
                        : card,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
