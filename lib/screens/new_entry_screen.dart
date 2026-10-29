import 'dart:async';

import 'package:flutter/material.dart';

import '../models/travel_entry.dart';

import '../services/entry_validation.dart';
import '../services/current_location_service.dart';
import '../services/error_messages.dart';
import '../services/photo_service.dart';
import '../services/travel_entry_service.dart';
import '../services/local_photo_service.dart';

class NewEntryScreen extends StatefulWidget {
  const NewEntryScreen({
    super.key,
    required this.uid,
    required this.entries,
    this.initialPhoto,
    this.photos,
    this.locationService,
    this.localPhotos = true,
  });
  final String uid;
  final TravelEntryService entries;
  final TravelPhoto? initialPhoto;
  final PhotoService? photos;
  final CurrentLocationService? locationService;
  final bool localPhotos;

  @override
  State<NewEntryScreen> createState() => _NewEntryScreenState();
}

class _NewEntryScreenState extends State<NewEntryScreen> {
  final _form = GlobalKey<FormState>();
  final _place = TextEditingController();
  final _description = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  late final _photos = widget.photos ?? PhotoService();
  late final _locationService =
      widget.locationService ?? CurrentLocationService();
  late TravelPhoto? _photo = widget.initialPhoto;
  late bool _includePhoto = widget.initialPhoto != null;
  bool _busy = false;
  bool _picking = false;
  bool _locating = false;
  String? _locationMessage;
  bool _locationFailed = false;
  double _progress = 0;
  String? _error;
  String? _cleanupWarning;
  TravelUploadAttempt? _attempt;
  bool _cancelling = false;
  bool get _canIncludePhoto =>
      !widget.localPhotos || LocalPhotoService.supported;
  bool get _locked => _busy || (_attempt != null && !_attempt!.canEdit);

  void _changed(String _) {
    if (!_busy && (_attempt?.canEdit ?? false)) setState(() => _attempt = null);
  }

  void _coordinateChanged(String value) {
    _changed(value);
    if (_locationMessage != null) {
      setState(() {
        _locationMessage = null;
        _locationFailed = false;
      });
    }
  }

  @override
  void dispose() {
    if (_locating) _locationService.cancel();
    final attempt = _attempt;
    if (attempt != null) unawaited(attempt.cancel());
    _place.dispose();
    _description.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_locked || _picking || _locating) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final photo = await _photos.pick();
      if (photo != null && mounted) {
        setState(() {
          _photo = photo;
          _attempt = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorMessage(error));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    if (_locked || _picking || _locating) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _locating = true;
      _locationMessage = null;
    });
    try {
      final point = await _locationService.capture();
      if (!mounted) return;
      if (!widget.entries.hasSession(widget.uid)) return;
      setState(() {
        _latitude.text = point.latitude.toString().replaceAll('.', ',');
        _longitude.text = point.longitude.toString().replaceAll('.', ',');
        _attempt = null;
        _locationFailed = false;
        _locationMessage =
            'Localização preenchida. Você pode ajustar ou apagar as coordenadas antes de salvar.';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _locationFailed = true;
          _locationMessage = error is CurrentLocationException
              ? error.message
              : const CurrentLocationException(
                  CurrentLocationFailure.unavailable,
                ).message;
        });
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _picking || _locating || !_form.currentState!.validate()) {
      return;
    }
    if (_includePhoto && _photo == null) {
      setState(() => _error = 'Escolha uma foto para guardar esta memória.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
      _cleanupWarning = null;
      _cancelling = false;
    });
    try {
      final location = parseLocation(_latitude.text, _longitude.text);
      _attempt ??= await widget.entries.prepareUpload(
        uid: widget.uid,
        placeName: _place.text,
        description: _description.text,
        photo: _includePhoto ? _photo : null,
        location: location,
        savePhotoLocally: widget.localPhotos,
      );
      if (!mounted) return;
      await _attempt!.save(
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _progress = progress;
              final failure = _attempt?.lastError;
              if (failure != null) {
                _error = errorMessage(failure);
              }
            });
          }
        },
      );
      if (mounted && widget.entries.hasSession(widget.uid)) {
        setState(() => _busy = false);
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = errorMessage(error);
          if (error is TravelUploadException && error.cleanupError != null) {
            _cleanupWarning =
                'Também não foi possível remover a foto desta tentativa. Ela pode ter permanecido no armazenamento. Seus dados foram preservados.';
          }
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_picking,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && mounted && _busy) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Aguarde a confirmação ou cancele o envio antes de sair.',
            ),
          ),
        );
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Nova memória'),
        leading: IconButton(
          tooltip: 'Voltar',
          onPressed: _busy || _picking
              ? null
              : () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Um lugar. Mil lembranças.',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    const Text('Conte sobre o lugar. A foto é opcional.'),
                    const SizedBox(height: 24),
                    SwitchListTile.adaptive(
                      key: const ValueKey('includePhoto'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Incluir foto'),
                      subtitle: const Text(
                        'A foto fica salva neste aparelho.',
                      ),
                      value: _includePhoto,
                      onChanged:
                          _locked || _picking || _locating || !_canIncludePhoto
                          ? null
                          : (value) {
                              setState(() {
                                _includePhoto = value;
                                _attempt = null;
                                _error = null;
                                _cleanupWarning = null;
                              });
                            },
                    ),
                    if (!_canIncludePhoto)
                      const Text(
                        'Para incluir fotos locais, use o aplicativo instalado no celular. As memórias continuam disponíveis aqui.',
                      ),
                    if (_includePhoto && widget.localPhotos)
                      const Text(
                        'A foto continuará disponível ao entrar nesta conta no mesmo aparelho. Em outro aparelho, a foto não estará disponível.',
                      ),
                    if (_includePhoto) ...[
                      if (_photo != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Image.memory(
                              _photo!.bytes,
                              fit: BoxFit.cover,
                              semanticLabel: 'Prévia da foto selecionada',
                              errorBuilder: (_, _, _) => const Center(
                                child: Text(
                                  'Esta imagem não pôde ser exibida. Escolha outra foto.',
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton.icon(
                        onPressed: _locked || _picking || _locating
                            ? null
                            : _pickPhoto,
                        icon: _picking
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _photo == null
                              ? 'Escolher foto da galeria'
                              : 'Trocar foto',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'JPG, PNG ou WebP • até 10 MB',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      key: const ValueKey('placeName'),
                      controller: _place,
                      enabled: !_locked,
                      onChanged: _changed,
                      maxLength: TravelEntry.maxPlaceNameLength,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nome do local',
                        hintText: 'Ex.: Praia do Rosa',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                      validator: (value) =>
                          TravelEntry.validatePlaceName(value ?? ''),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('description'),
                      controller: _description,
                      enabled: !_locked,
                      onChanged: _changed,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: TravelEntry.maxDescriptionLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Sua memória',
                        hintText: 'O que tornou esse lugar especial?',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) =>
                          TravelEntry.validateDescription(value ?? ''),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Onde essa história aconteceu?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Se souber, informe a latitude e a longitude do lugar.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('useCurrentLocation'),
                      onPressed: _locked || _picking || _locating
                          ? null
                          : _useCurrentLocation,
                      icon: _locating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                semanticsLabel: 'Obtendo localização',
                              ),
                            )
                          : const Icon(Icons.my_location),
                      label: Text(
                        _locating
                            ? 'Obtendo localização…'
                            : 'Usar minha localização',
                      ),
                    ),
                    if (_locationMessage != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _locationMessage!,
                          style: TextStyle(
                            color: _locationFailed
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('latitude'),
                      controller: _latitude,
                      enabled: !_locked && !_locating,
                      onChanged: _coordinateChanged,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        hintText: 'Ex.: -27,12345',
                      ),
                      validator: (value) => validateCoordinate(
                        value ?? '',
                        latitude: true,
                        otherValue: _longitude.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('longitude'),
                      controller: _longitude,
                      enabled: !_locked && !_locating,
                      onChanged: _coordinateChanged,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        hintText: 'Ex.: -48,12345',
                      ),
                      validator: (value) => validateCoordinate(
                        value ?? '',
                        latitude: false,
                        otherValue: _latitude.text,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 20),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                    if (_busy) ...[
                      const SizedBox(height: 24),
                      LinearProgressIndicator(
                        value:
                            _attempt == null ||
                                (_attempt?.needsReconciliation ?? false)
                            ? null
                            : _progress < 1
                            ? _progress
                            : null,
                        semanticsLabel: 'Enviando memória',
                      ),
                      const SizedBox(height: 10),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _attempt == null
                              ? (_includePhoto
                                    ? 'Validando foto…'
                                    : 'Preparando memória…')
                              : (_attempt?.isCleaningUp ?? false)
                              ? 'Removendo a foto após a falha…'
                              : (_attempt?.needsReconciliation ?? false)
                              ? 'Verificando envio anterior…'
                              : _progress < 1
                              ? (widget.localPhotos
                                    ? 'Guardando foto neste aparelho…'
                                    : 'Enviando foto… ${(_progress * 100).round()}%')
                              : 'Guardando sua memória… Aguarde a confirmação.',
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Mantenha o aplicativo aberto e conectado à internet.',
                      ),
                    ],
                    if (_cleanupWarning != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(_cleanupWarning!),
                      ),
                    ],
                    if (_attempt?.needsReconciliation ?? false) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'A confirmação do envio anterior ficou pendente. Verifique o envio para continuar sem criar outra memória.',
                      ),
                    ],
                    if (_busy && (_attempt?.canCancel ?? false)) ...[
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: _cancelling
                            ? null
                            : () async {
                                setState(() => _cancelling = true);
                                await _attempt?.cancel();
                                if (mounted) setState(() {});
                              },
                        child: Text(
                          _cancelling ? 'Cancelando…' : 'Cancelar envio',
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const ValueKey('saveEntry'),
                      onPressed: _busy || _picking || _locating ? null : _save,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(
                        _busy
                            ? 'Salvando…'
                            : (_attempt?.needsReconciliation ?? false)
                            ? 'Verificar envio'
                            : 'Salvar',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Esta memória ficará visível apenas para você.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
