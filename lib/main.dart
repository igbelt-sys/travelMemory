import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'screens/setup_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WanderLogApp());
}

class WanderLogApp extends StatelessWidget {
  const WanderLogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WanderLog',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: const FirebaseBootstrap(),
  );
}

class FirebaseBootstrap extends StatefulWidget {
  const FirebaseBootstrap({super.key, this.initialize});

  final Future<FirebaseApp> Function()? initialize;

  @override
  State<FirebaseBootstrap> createState() => _FirebaseBootstrapState();
}

class _FirebaseBootstrapState extends State<FirebaseBootstrap> {
  late Future<FirebaseApp> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<FirebaseApp> _initialize() async {
    if (widget.initialize != null) return widget.initialize!();
    return Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FirebaseApp>(
    future: _initialization,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return SetupScreen(
          missingConfiguration: snapshot.error is UnsupportedError,
          onRetry: () => setState(() => _initialization = _initialize()),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return const AuthGate();
    },
  );
}
