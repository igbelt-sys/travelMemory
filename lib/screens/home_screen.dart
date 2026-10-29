import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/travel_entry.dart';
import '../services/auth_service.dart';
import '../services/error_messages.dart';
import '../services/photo_service.dart';
import '../services/travel_entry_service.dart';
import '../widgets/travel_entry_card.dart';
import 'new_entry_screen.dart';
import 'entry_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.user,
    required this.auth,
    this.entries,
    this.photos,
  });
  final User user;
  final AuthService auth;
  final TravelEntryService? entries;
  final PhotoService? photos;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late TravelEntryService _entries;
  late final _photos = widget.photos ?? PhotoService();
  late Stream<List<TravelEntry>> _stream;
  int _generation = 0;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _entries = widget.entries ?? TravelEntryService();
    _stream = _watchEntries();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverPhoto());
    }
  }

  Stream<List<TravelEntry>> _watchEntries() {
    try {
      return _entries.watchEntries(widget.user.uid);
    } catch (error, stack) {
      return Stream.error(error, stack);
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid ||
        oldWidget.entries != widget.entries) {
      _entries = widget.entries ?? TravelEntryService();
      _stream = _watchEntries();
      _generation++;
      _signingOut = false;
    }
  }

  Future<void> _openDetails(TravelEntry entry) async {
    if (_signingOut || !_entries.hasSession(widget.user.uid)) return;
    FocusScope.of(context).unfocus();
    final result = await Navigator.of(context).push<TravelDeletionResult>(
      MaterialPageRoute(
        builder: (_) => EntryDetailsScreen(
          entry: entry,
          uid: widget.user.uid,
          localPhotos: _entries.localPhotos,
          entries: _entries,
        ),
      ),
    );
    if (result != null && mounted && _entries.hasSession(widget.user.uid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.cleanupError == null
                ? 'Memória excluída do seu diário.'
                : 'Memória excluída. Não foi possível remover a cópia da foto. '
                      'Ela pode continuar armazenada no dispositivo ou serviço de fotos.',
          ),
          duration: Duration(seconds: result.cleanupError == null ? 4 : 9),
        ),
      );
    }
  }

  Future<void> _recoverPhoto() async {
    try {
      final photo = await _photos.recoverLostPhoto();
      if (photo != null &&
          mounted &&
          !_signingOut &&
          _entries.hasSession(widget.user.uid)) {
        await _addEntry(photo: photo);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
      }
    }
  }

  Future<void> _addEntry({TravelPhoto? photo}) async {
    if (_signingOut || !_entries.hasSession(widget.user.uid)) return;
    FocusScope.of(context).unfocus();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NewEntryScreen(
          uid: widget.user.uid,
          entries: _entries,
          initialPhoto: photo,
          photos: _photos,
        ),
      ),
    );
    if (saved == true && mounted && _entries.hasSession(widget.user.uid)) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memória guardada no seu diário!')),
      );
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() => _signingOut = true);
    try {
      await widget.auth.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'WanderLog',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      actions: [
        IconButton(
          tooltip: 'Sair da conta',
          onPressed: _signingOut ? null : _signOut,
          icon: _signingOut
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _signingOut ? null : _addEntry,
      icon: const Icon(Icons.add),
      label: const Text('Nova memória'),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _signingOut || !_entries.hasSession(widget.user.uid)
              ? const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Encerrando sessão',
                  ),
                )
              : StreamBuilder<List<TravelEntry>>(
                  key: ValueKey('${widget.user.uid}:$_generation'),
                  stream: _stream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Carregando suas memórias',
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.cloud_off_outlined, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  errorMessage(snapshot.error!),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: () => setState(() {
                                    _stream = _watchEntries();
                                    _generation++;
                                  }),
                                  child: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Carregando suas memórias',
                        ),
                      );
                    }
                    final entries = snapshot.data!;
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
                      itemCount: entries.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'SEU DIÁRIO • MUNDO AFORA',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      letterSpacing: 1.4,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondary,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Lugares que ficam\ncom você.',
                                style: Theme.of(context).textTheme.headlineLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Guarde os lugares e momentos que marcaram suas viagens.',
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  const Icon(Icons.lock_outline, size: 16),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '${entries.length} ${entries.length == 1 ? 'memória' : 'memórias'} • Só você pode ver',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              if (entries.isEmpty)
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(28),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.luggage_outlined,
                                          size: 64,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          'Seu diário ainda está vazio',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                        const SizedBox(height: 10),
                                        const Text(
                                          'Comece contando sobre um lugar que ficou na sua memória. Se quiser, adicione uma foto.',
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 20),
                                        FilledButton(
                                          onPressed: _addEntry,
                                          child: const Text(
                                            'Adicionar uma memória',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: TravelEntryCard(
                            key: ValueKey(entries[index - 1].id),
                            entry: entries[index - 1],
                            uid: widget.user.uid,
                            localPhotos: _entries.localPhotos,
                            onTap: () => _openDetails(entries[index - 1]),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    ),
  );
}
