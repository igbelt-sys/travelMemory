import 'package:flutter/material.dart';

import '../models/travel_entry.dart';
import '../widgets/entry_photo.dart';
import '../widgets/local_entry_photo.dart';
import '../services/local_photo_service.dart';
import '../services/travel_entry_service.dart';
import '../services/error_messages.dart';

class EntryDetailsScreen extends StatefulWidget {
  const EntryDetailsScreen({
    super.key,
    required this.entry,
    this.uid,
    this.localPhotos,
    this.entries,
  });
  final TravelEntry entry;
  final String? uid;
  final LocalPhotoService? localPhotos;
  final TravelEntryService? entries;

  @override
  State<EntryDetailsScreen> createState() => _EntryDetailsScreenState();
}

class _EntryDetailsScreenState extends State<EntryDetailsScreen> {
  TravelEntry get entry => widget.entry;
  String? get uid => widget.uid;
  LocalPhotoService? get localPhotos => widget.localPhotos;
  bool _confirming = false;
  bool _deleting = false;

  Future<void> _confirmDeletion() async {
    if (_confirming || _deleting) return;
    final service = widget.entries;
    final owner = uid;
    if (service == null || owner == null) return;
    setState(() => _confirming = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir memória?'),
        content: SingleChildScrollView(
          child: Text(
            '“${entry.placeName}” será excluída do seu diário. '
            'Essa ação não pode ser desfeita. '
            '${entry.isLocalPhoto ? 'A cópia da foto neste aplicativo também será removida; a imagem original da galeria será mantida.' : ''}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _confirming = false);
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      final result = await service.deleteEntry(uid: owner, entry: entry);
      if (!mounted || !service.hasSession(owner)) return;
      setState(() => _deleting = false);
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted || !service.hasSession(owner)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível excluir a memória. ${errorMessage(error)}',
          ),
          duration: const Duration(seconds: 7),
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final location = entry.location;
    String coordinate(double value) =>
        value.toStringAsFixed(5).replaceAll('.', ',');
    return PopScope(
      canPop: !_deleting,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Sua memória'),
          automaticallyImplyLeading: !_deleting,
          actions: [
            if (widget.entries != null && uid != null)
              IconButton(
                tooltip: 'Excluir memória',
                onPressed: _deleting || _confirming || entry.hasPendingWrites
                    ? null
                    : _confirmDeletion,
                icon: _deleting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          semanticsLabel: 'Excluindo memória',
                        ),
                      )
                    : const Icon(Icons.delete_outline),
              ),
          ],
          bottom: _deleting
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(32),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('Excluindo memória…'),
                  ),
                )
              : null,
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (entry.isLocalPhoto)
                      LocalEntryPhoto(
                        uid: uid ?? '',
                        entryId: entry.id,
                        imagePath: entry.imagePath!,
                        placeName: entry.placeName,
                        photos: localPhotos,
                        fit: BoxFit.contain,
                      )
                    else if (entry.hasPhoto)
                      EntryPhoto(
                        imageUrl: entry.imageUrl!,
                        placeName: entry.placeName,
                        fit: BoxFit.contain,
                      ),
                    if (!entry.hasPhoto)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: Text('Memória sem foto'),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Semantics(
                            header: true,
                            child: Text(
                              entry.placeName,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.primary,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Memória registrada em',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.createdAt == null
                                ? 'Sincronizando data…'
                                : MaterialLocalizations.of(
                                    context,
                                  ).formatFullDate(entry.createdAt!.toLocal()),
                          ),
                          const SizedBox(height: 24),
                          SelectableText(
                            entry.description,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(height: 1.6),
                          ),
                          const SizedBox(height: 28),
                          const Divider(),
                          const SizedBox(height: 12),
                          Semantics(
                            header: true,
                            child: Text(
                              'Localização',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (location != null)
                            SelectableText(
                              'Latitude: ${coordinate(location.latitude)}\nLongitude: ${coordinate(location.longitude)}',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(height: 1.6),
                            )
                          else
                            Text(
                              'Localização não informada.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
