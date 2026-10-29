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
                      ? 'O diário ainda não está configurado'
                      : 'Não foi possível abrir o diário',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  missingConfiguration
                      ? 'A configuração está incompleta. Peça ajuda à pessoa que preparou o aplicativo.'
                      : 'Confira sua conexão com a internet e tente novamente.',
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
