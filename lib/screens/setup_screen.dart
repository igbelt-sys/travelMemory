import 'package:flutter/material.dart';

class SetupScreen extends StatelessWidget {
  const SetupScreen({
    super.key,
    required this.missingConfiguration,
    required this.onRetry,
  });
  final bool missingConfiguration;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.travel_explore,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'WanderLog',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  missingConfiguration
                      ? 'Falta conectar seu diário ao Firebase'
                      : 'Não foi possível iniciar seu diário',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  missingConfiguration
                      ? 'A configuração real ainda não foi adicionada. Siga o README do projeto para executar flutterfire configure e habilitar os serviços. Depois, reinicie o aplicativo.'
                      : 'Confira sua conexão e a configuração do Firebase para esta plataforma. O README contém as instruções de configuração.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
