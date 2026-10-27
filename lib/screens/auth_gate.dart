import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/travel_entry_service.dart';
import '../services/photo_service.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.auth, this.entries, this.photos});
  final AuthService? auth;
  final TravelEntryService? entries;
  final PhotoService? photos;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final _auth = widget.auth ?? AuthService();
  late final _entries = widget.entries ?? TravelEntryService();
  late final _photos = widget.photos ?? PhotoService();
  late final _session = _auth.authStateChanges;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _session,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(
            child: Text(
              'Não foi possível verificar sua sessão. Reinicie o aplicativo.',
            ),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      return user == null
          ? AuthScreen(auth: _auth)
          : _SessionNavigator(
              key: ValueKey(user.uid),
              user: user,
              auth: _auth,
              entries: _entries,
              photos: _photos,
            );
    },
  );
}

// Todas as rotas privadas são descartadas ao sair ou trocar de conta,
// inclusive um formulário aberto acima da tela principal.
class _SessionNavigator extends StatefulWidget {
  const _SessionNavigator({
    super.key,
    required this.user,
    required this.auth,
    required this.entries,
    required this.photos,
  });
  final User user;
  final AuthService auth;
  final TravelEntryService entries;
  final PhotoService photos;
  @override
  State<_SessionNavigator> createState() => _SessionNavigatorState();
}

class _SessionNavigatorState extends State<_SessionNavigator> {
  final _navigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    onPopWithResult: (_) => _navigator.currentState?.maybePop(),
    child: ScaffoldMessenger(
      child: Navigator(
        key: _navigator,
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (_) => HomeScreen(
            user: widget.user,
            auth: widget.auth,
            entries: widget.entries,
            photos: widget.photos,
          ),
        ),
      ),
    ),
  );
}
