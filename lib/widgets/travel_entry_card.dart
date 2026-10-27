import 'package:flutter/material.dart';

import '../models/travel_entry.dart';
import 'entry_photo.dart';
import 'local_entry_photo.dart';
import '../services/local_photo_service.dart';

class TravelEntryCard extends StatelessWidget {
  const TravelEntryCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.uid,
    this.localPhotos,
  });
  final TravelEntry entry;
  final String? uid;
  final LocalPhotoService? localPhotos;
  final VoidCallback onTap;

  String get _excerpt {
    final text = entry.description.trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.runes.length > 180
        ? '${String.fromCharCodes(text.runes.take(180))}…'
        : text;
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Semantics(
      button: true,
      label: 'Abrir memória de ${entry.placeName}',
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.isLocalPhoto)
              LocalEntryPhoto(
                uid: uid ?? '',
                entryId: entry.id,
                imagePath: entry.imagePath!,
                placeName: entry.placeName,
                photos: localPhotos,
              )
            else if (entry.hasPhoto)
              EntryPhoto(imageUrl: entry.imageUrl!, placeName: entry.placeName),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.place_outlined,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry.placeName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _excerpt,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.createdAt == null
                              ? 'Sincronizando data…'
                              : MaterialLocalizations.of(
                                  context,
                                ).formatMediumDate(entry.createdAt!.toLocal()),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
