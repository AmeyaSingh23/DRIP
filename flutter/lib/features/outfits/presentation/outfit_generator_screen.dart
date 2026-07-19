import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../../creative/presentation/creative_space_screen.dart';
import '../data/outfit_repository.dart';
import '../domain/outfit_preview.dart';

class OutfitGeneratorScreen extends StatefulWidget {
  const OutfitGeneratorScreen({required this.token, super.key});

  final String token;

  @override
  State<OutfitGeneratorScreen> createState() => _OutfitGeneratorScreenState();
}

class _OutfitGeneratorScreenState extends State<OutfitGeneratorScreen> {
  final _repository = OutfitRepository(ApiClient());
  final _occasion = TextEditingController();
  final _notes = TextEditingController();
  OutfitPreview? _preview;
  String? _error;
  bool _generating = false;
  bool _saving = false;
  String? _saveIdempotencyKey;

  @override
  void dispose() {
    _occasion.dispose();
    _notes.dispose();
    super.dispose();
  }

  String _messageFor(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (error.type == DioExceptionType.receiveTimeout) {
      return 'Outfit generation is taking longer than expected. Please try again.';
    }
    return 'Could not generate an outfit. Please try again.';
  }

  Future<void> _generate() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _generating = true;
      _error = null;
      _preview = null;
      _saveIdempotencyKey = null;
    });
    try {
      final preview = await _repository.generate(
        token: widget.token,
        occasion: _occasion.text,
        styleNotes: _notes.text,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _saveIdempotencyKey = const Uuid().v4();
        });
      }
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _save() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() => _saving = true);
    try {
      await _repository.save(
        token: widget.token,
        preview: preview,
        itemLayout: const [],
        idempotencyKey: _saveIdempotencyKey ??= const Uuid().v4(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Outfit saved to your wardrobe history.'),
          ),
        );
        setState(() {
          _preview = null;
          _saveIdempotencyKey = null;
        });
      }
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _generating || _saving;
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && busy && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Your outfit is still being processed. Please wait.',
              ),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create an outfit'),
          automaticallyImplyLeading: !busy,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Use your wardrobe',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Gemini selects from your saved items only. Generation is a preview until you choose Save.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _occasion,
              enabled: !busy,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: 'Occasion (optional)',
                hintText: 'College, dinner, gym...',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              enabled: !busy,
              maxLength: 240,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Style notes (optional)',
                hintText: 'Comfortable, minimal, colourful...',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy ? null : _generate,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: Text(
                _generating ? 'Creating outfit...' : 'Generate outfit',
              ),
            ),
            if (_generating) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 28),
              Text(
                _preview!.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(_preview!.rationale),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    _preview!.items
                        .map(
                          (item) => SizedBox(
                            width: 150,
                            height: 190,
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Image.network(
                                        item.cloudinaryUrl,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text(
                                      item.itemName ?? item.category,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : _save,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save outfit'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          busy
                              ? null
                              : () => context.push(
                                '/creative',
                                extra: CreativeRouteArgs(
                                  token: widget.token,
                                  initialItems: _preview!.items,
                                  initialName: _preview!.name,
                                  initialOccasion: _preview!.occasion,
                                  startCollapsed: true,
                                ),
                              ),
                      icon: const Icon(Icons.palette_outlined),
                      label: const Text('Style on canvas'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
