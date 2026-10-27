import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/local_photo_service.dart';

class LocalEntryPhoto extends StatefulWidget {
  const LocalEntryPhoto({
    super.key,
    required this.uid,
    required this.entryId,
    required this.imagePath,
    required this.placeName,
    this.photos,
    this.fit = BoxFit.cover,
  });
  final String uid;
  final String entryId;
  final String imagePath;
  final String placeName;
  final LocalPhotoService? photos;
  final BoxFit fit;
  @override
  State<LocalEntryPhoto> createState() => _LocalEntryPhotoState();
}

class _LocalEntryPhotoState extends State<LocalEntryPhoto> {
  late Future<Uint8List?> _bytes;
  Future<Uint8List?> _load() => (widget.photos ?? LocalPhotoService()).read(
    uid: widget.uid,
    entryId: widget.entryId,
    relativePath: widget.imagePath,
  );
  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  @override
  void didUpdateWidget(covariant LocalEntryPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.entryId != widget.entryId ||
        oldWidget.imagePath != widget.imagePath ||
        oldWidget.photos != widget.photos) {
      _bytes = _load();
    }
  }

  Widget _unavailable() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_outlined, size: 36),
          const SizedBox(height: 8),
          const Text(
            'Foto não disponível neste dispositivo.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'Ela foi guardada no aparelho em que a memória foi criada.',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: () => setState(() => _bytes = _load()),
            child: const Text('Tentar abrir novamente'),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 4 / 3,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Abrindo foto do dispositivo',
              ),
            );
          }
          final bytes = snapshot.data;
          if (snapshot.hasError || bytes == null) return _unavailable();
          return Image.memory(
            bytes,
            fit: widget.fit,
            cacheWidth: 900,
            semanticLabel: 'Foto de ${widget.placeName}',
            errorBuilder: (_, _, _) => _unavailable(),
          );
        },
      ),
    ),
  );
}
