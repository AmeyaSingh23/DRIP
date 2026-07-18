import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:native_cutout/native_cutout.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';
import '../data/wardrobe_repository.dart';
import '../domain/clothing_item_draft.dart';
import 'cutout_editor_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({required this.token, super.key});

  final String token;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  static const _idleStatus = 'Choose a clothing photo';
  final _picker = ImagePicker();
  final _repository = WardrobeRepository(ApiClient());
  ClothingItemDraft? _draft;
  String? _error;
  String _status = _idleStatus;
  bool _busy = false;

  Future<void> _choose(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _draft = null;
      _status = 'Opening image…';
    });
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (picked == null) {
        if (mounted) {
          setState(() => _status = _idleStatus);
        }
        return;
      }
      final selectedPhoto = File(picked.path);
      if (!mounted) return;
      setState(() => _status = 'Adjust your photo…');
      final editedPhoto = await Navigator.of(context).push<File>(
        MaterialPageRoute(
          builder: (_) => CutoutEditorScreen(image: selectedPhoto),
        ),
      );
      if (editedPhoto == null) {
        if (mounted) setState(() => _status = _idleStatus);
        return;
      }
      if (mounted) setState(() => _status = 'Preparing on-device cutout…');
      await _ensureCutoutModel();
      final cutout = await _removeBackground(editedPhoto);
      if (mounted) setState(() => _status = 'Optimizing cutout for upload…');
      final uploadCutout = await _prepareCutoutForUpload(cutout);
      if (mounted) {
        setState(() => _status = 'Downscaling the original for Gemini…');
      }
      final taggingImage = await _downscaleForTagging(editedPhoto);
      if (mounted) setState(() => _status = 'Identifying and saving tags…');
      final draft = await _repository.upload(
        cutout: uploadCutout,
        taggingImage: taggingImage,
        token: widget.token,
      );
      if (mounted) {
        setState(() {
          _draft = draft;
          _status = 'Review the detected tags';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _messageFor(error);
          _status = _idleStatus;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ensureCutoutModel() async {
    if (await NativeCutout.isModelAvailable()) return;
    if (mounted) {
      setState(() => _status = 'Downloading on-device cutout model…');
    }
    if (!await NativeCutout.downloadModel()) {
      throw StateError(
        'The on-device cutout model could not start downloading. Check your connection and try again.',
      );
    }

    // Android downloads this optional ML Kit module separately. A completed
    // request can still need a moment before the module becomes usable.
    for (var attempt = 0; attempt < 45; attempt++) {
      if (await NativeCutout.isModelAvailable()) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw StateError(
      'The on-device cutout model is still downloading. Please try again in a moment.',
    );
  }

  Future<File> _removeBackground(File original) async {
    Future<CutoutResult> remove() => NativeCutout.removeBackground(
      original.path,
      options: const CutoutOptions(cropToSubject: true, writeToCache: true),
    );

    final result = await remove();
    if (result case CutoutFileSuccess(:final path)) return File(path);

    if (result is CutoutFailure && result.message.contains('optional module')) {
      await _ensureCutoutModel();
      final retry = await remove();
      if (retry case CutoutFileSuccess(:final path)) return File(path);
      throw StateError(
        retry is CutoutFailure
            ? retry.message
            : 'Could not remove the background.',
      );
    }
    throw StateError(
      result is CutoutFailure
          ? result.message
          : 'Could not remove the background.',
    );
  }

  img.Image _resizeToMaxSide(img.Image source, int maxSide) {
    if (math.max(source.width, source.height) <= maxSide) return source;
    return source.width >= source.height
        ? img.copyResize(source, width: maxSide)
        : img.copyResize(source, height: maxSide);
  }

  Future<File> _prepareCutoutForUpload(File cutout) async {
    final source = img.decodeImage(await cutout.readAsBytes());
    if (source == null) {
      throw StateError(
        'The cutout could not be processed. Please choose the photo again.',
      );
    }
    final resized = _resizeToMaxSide(source, 1600);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/drip_cutout_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(img.encodePng(resized, level: 6), flush: true);
    return file;
  }

  Future<File> _downscaleForTagging(File original) async {
    final source = img.decodeImage(await original.readAsBytes());
    if (source == null) {
      throw StateError('The selected image could not be decoded.');
    }
    final resized = _resizeToMaxSide(source, 1280);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/drip_tagging_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(img.encodeJpg(resized, quality: 85), flush: true);
    return file;
  }

  String _messageFor(Object error) {
    if (error is DioException) {
      final response = error.response;
      final data = response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
      if (response?.statusCode == 413) {
        return 'The photo is too large. Please choose a smaller image and try again.';
      }
      if (response?.statusCode == 401) {
        return 'Your session has expired. Please sign in again.';
      }
      if (error.type == DioExceptionType.receiveTimeout) {
        return 'AI tagging is taking longer than expected. Please try again in a moment.';
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout) {
        return 'Could not reach DRIP. Check that the backend is running and your phone is connected.';
      }
    }
    if (error is StateError) return error.message.toString();
    return 'Could not add this item. Please try again.';
  }

  Future<void> _saveEdits() async {
    final draft = _draft;
    if (draft == null) return;
    final name = TextEditingController(text: draft.itemName ?? '');
    final color = TextEditingController(text: draft.color ?? '');
    final customCategory = TextEditingController(
      text: draft.category == 'Custom' ? draft.customCategory ?? '' : '',
    );
    const categories = [
      'Tops',
      'Bottoms',
      'Outerwear',
      'Shoes',
      'Dresses',
      'Accessories',
      'Uniform',
      'Custom',
    ];
    var selectedCategory =
        categories.contains(draft.category) ? draft.category : 'Custom';
    var showCustomCategoryError = false;
    final result = await showDialog<List<String>>(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Review item tags'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          key: const ValueKey('item-name'),
                          controller: name,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: selectedCategory,
                          decoration: const InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            labelText: 'Category',
                          ),
                          items:
                              categories
                                  .map(
                                    (category) => DropdownMenuItem(
                                      value: category,
                                      child: Text(category),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() {
                                selectedCategory = value;
                                showCustomCategoryError = false;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        Visibility(
                          visible: selectedCategory == 'Custom',
                          child: TextField(
                            key: const ValueKey('custom-category'),
                            controller: customCategory,
                            textCapitalization: TextCapitalization.words,
                            maxLength: 100,
                            decoration: InputDecoration(
                              labelText: 'Custom category',
                              hintText: 'For example: Activewear',
                              filled: true,
                              fillColor: Colors.white,
                              errorText:
                                  showCustomCategoryError
                                      ? 'Enter a custom category name.'
                                      : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          key: const ValueKey('item-color'),
                          controller: color,
                          decoration: const InputDecoration(
                            labelText: 'Color',
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (selectedCategory == 'Custom' &&
                            customCategory.text.trim().isEmpty) {
                          setDialogState(() => showCustomCategoryError = true);
                          return;
                        }
                        Navigator.pop(context, [
                          name.text.trim(),
                          selectedCategory,
                          selectedCategory == 'Custom'
                              ? customCategory.text.trim()
                              : '',
                          color.text.trim(),
                        ]);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );
    name.dispose();
    color.dispose();
    customCategory.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _error = null;
      _status = 'Saving your edits…';
    });
    try {
      final updated = await _repository.update(
        draft: draft,
        token: widget.token,
        itemName: result[0],
        category: result[1],
        customCategory: result[2].isEmpty ? null : result[2],
        color: result[3],
      );
      setState(() {
        _draft = updated;
        _status = 'Item saved';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _messageFor(error);
          _status = 'Review the detected tags';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add to wardrobe')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_status),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 20),
          if (_draft != null) ...[
            Image.network(
              _draft!.cloudinaryUrl,
              height: 220,
              errorBuilder:
                  (_, _, _) => const Icon(Icons.image_not_supported, size: 80),
            ),
            Text('AI confidence: ${(_draft!.aiConfidence * 100).round()}%'),
            if (_draft!.userVerified)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Verified by you'),
              ),
            if (!_draft!.userVerified && _draft!.aiConfidence < 0.6)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'No clear clothing item was detected. Try one item on a contrasting background.',
                  textAlign: TextAlign.center,
                ),
              ),
            FilledButton(
              onPressed: _saveEdits,
              child: const Text('Review / edit tags'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F1FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'For a clean cutout, photograph one item laid flat or hanging on a contrasting background.',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : () => _choose(ImageSource.camera),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take photo'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _choose(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose from gallery'),
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    ),
  );
}
