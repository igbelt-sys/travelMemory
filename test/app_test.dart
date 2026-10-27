import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wanderlog/main.dart';
import 'package:wanderlog/screens/auth_screen.dart';
import 'package:wanderlog/screens/new_entry_screen.dart';
import 'package:wanderlog/services/auth_service.dart';
import 'package:wanderlog/services/travel_entry_service.dart';
import 'package:wanderlog/theme/app_theme.dart';

class FakeAuth extends AuthService {
  int calls = 0;
  String? email;
  Completer<void>? pending;
  Object? failure;

  @override
  Future<void> signIn(String email, String password) async {
    calls++;
    this.email = email;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<void> signUp(String email, String password) => signIn(email, password);
}

class FakeEntries implements TravelEntryService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget shell(Widget child) => MaterialApp(
  theme: AppTheme.light,
  locale: const Locale('pt', 'BR'),
  supportedLocales: const [Locale('pt', 'BR')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: child,
);

void main() {
  testWidgets('sem configuração real mostra orientação em vez de falhar', (
    tester,
  ) async {
    await tester.pumpWidget(
      shell(
        FirebaseBootstrap(
          initialize: () async =>
              throw UnsupportedError('Configuração não disponível'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Falta conectar seu diário ao Firebase'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validação impede envio vazio', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(shell(AuthScreen(auth: auth)));
    await tester.tap(find.text('Entrar no meu diário'));
    await tester.pumpAndSettle();
    expect(auth.calls, 0);
    expect(find.text('Informe um e-mail válido.'), findsOneWidget);
    expect(find.text('Informe sua senha.'), findsOneWidget);
  });

  testWidgets('login impede duplicação e traduz erro do Firebase', (
    tester,
  ) async {
    final auth = FakeAuth()
      ..pending = Completer<void>()
      ..failure = FirebaseAuthException(code: 'invalid-credential');
    await tester.pumpWidget(shell(AuthScreen(auth: auth)));
    await tester.enterText(find.byType(TextFormField).at(0), 'ana@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'segredo');
    await tester.tap(find.text('Entrar no meu diário'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(auth.calls, 1);
    auth.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('E-mail ou senha incorretos'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('cadastro exige confirmação da senha', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(shell(AuthScreen(auth: auth)));
    await tester.ensureVisible(
      find.text('Primeira viagem por aqui? Criar conta'),
    );
    await tester.tap(find.text('Primeira viagem por aqui? Criar conta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'ana@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'segredo');
    await tester.enterText(find.byType(TextFormField).at(2), 'diferente');
    await tester.ensureVisible(find.text('Criar minha conta'));
    await tester.tap(find.text('Criar minha conta'));
    await tester.pumpAndSettle();
    expect(find.text('As senhas precisam ser iguais.'), findsOneWidget);
    expect(auth.calls, 0);
  });

  testWidgets(
    'foto é exigida somente quando a opção de incluir foto é ativada',
    (tester) async {
      await tester.pumpWidget(
        shell(NewEntryScreen(uid: 'ana', entries: FakeEntries())),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Praia');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Um dia especial',
      );
      await tester.tap(find.byKey(const ValueKey('includePhoto')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(
        find.text('Escolha uma foto para guardar esta memória.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('login cabe em celular estreito com texto ampliado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
        child: shell(AuthScreen(auth: FakeAuth())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Entrar no meu diário'));
    expect(tester.takeException(), isNull);
  });
}
