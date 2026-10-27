import 'package:flutter/material.dart';

/// Mantém o espaço da foto estável enquanto carrega ou apresenta uma falha.
class EntryPhoto extends StatefulWidget {
  const EntryPhoto({
    super.key,
    required this.imageUrl,
    required this.placeName,
    this.fit = BoxFit.cover,
    this.aspectRatio = 4 / 3,
  });
  final String imageUrl;
  final String placeName;
  final BoxFit fit;
  final double aspectRatio;

  @override
  State<EntryPhoto> createState() => _EntryPhotoState();
}

class _EntryPhotoState extends State<EntryPhoto> {
  int _revision = 0;
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await NetworkImage(widget.imageUrl).evict();
    if (!mounted) return;
    setState(() {
      _revision++;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: widget.aspectRatio,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Image.network(
        widget.imageUrl,
        key: ValueKey((widget.imageUrl, _revision)),
        fit: widget.fit,
        semanticLabel: 'Foto de ${widget.placeName}',
        frameBuilder: (context, child, frame, synchronous) =>
            synchronous || frame != null
            ? child
            : const Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Carregando foto',
                ),
              ),
        errorBuilder: (context, error, stack) => Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, size: 32),
                const SizedBox(height: 8),
                const Text(
                  'Não foi possível carregar a foto.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _retrying ? null : _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Recarregar foto'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
