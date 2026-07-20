import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../data/wardrobe_repository.dart';
import '../domain/clothing_tag_result.dart';
import 'cutout_editor_screen.dart';
import 'wardrobe_change_notifier.dart';

final class UploadRouteArgs {
  const UploadRouteArgs({required this.token, required this.email});
  final String token;
  final String email;
}

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({required this.token, required this.email, super.key});
  final String token;
  final String email;
  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  static const _idleStatus = 'Choose a clothing photo';
  static const _categories = [
    'Tops',
    'Bottoms',
    'Outerwear',
    'Shoes',
    'Dresses',
    'Accessories',
    'Uniform',
    'Custom',
  ];
  final _picker = ImagePicker();
  final _repository = WardrobeRepository(ApiClient());
  final _name = TextEditingController();
  final _color = TextEditingController();
  final _customCategory = TextEditingController();
  File? _cutout;
  File? _taggingImage;
  String _category = 'Custom';
  String _status = _idleStatus;
  String? _error;
  bool _busy = false;
  bool _wornItemDetected = false;
  String? _idempotencyKey;
  Timer? _retryTimer;
  DateTime? _retryAvailableAt;

  @override
  void dispose() {
    final cutout = _cutout;
    if (cutout != null) {
      _deleteTemporaryFile(cutout);
    }
    final taggingImage = _taggingImage;
    if (taggingImage != null) {
      _deleteTemporaryFile(taggingImage);
    }
    _retryTimer?.cancel();
    _name.dispose();
    _color.dispose();
    _customCategory.dispose();
    super.dispose();
  }

  Future<void> _choose(ImageSource source) async {
    if (_busy) {
      return;
    }
    await _clearTaggingImage();
    final previousCutout = _cutout;
    _cutout = null;
    if (previousCutout != null) {
      await _deleteTemporaryFile(previousCutout);
    }
    File? cutoutSource;
    File? rawCutout;
    File? taggingImage;
    setState(() {
      _busy = true;
      _error = null;
      _wornItemDetected = false;
      _cutout = null;
      _idempotencyKey = const Uuid().v4();
      _retryAvailableAt = null;
      _status = 'Opening image...';
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
      if (!mounted) {
        return;
      }
      final edited = await Navigator.of(context).push<File>(
        MaterialPageRoute(
          builder: (_) => CutoutEditorScreen(image: File(picked.path)),
        ),
      );
      if (edited == null) {
        if (mounted) {
          setState(() => _status = _idleStatus);
        }
        return;
      }
      if (mounted) {
        setState(() => _status = 'Removing background...');
      }
      cutoutSource = await _prepareForCutout(edited);
      rawCutout = File(
        '${(await getTemporaryDirectory()).path}/la_maison_rapidapi_cutout_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await rawCutout.writeAsBytes(
        await _repository.removeBackground(
          image: cutoutSource,
          token: widget.token,
        ),
        flush: true,
      );
      await _deleteTemporaryFile(cutoutSource);
      cutoutSource = null;
      final cutout = await _prepareCutoutForUpload(rawCutout);
      await _deleteTemporaryFile(rawCutout);
      rawCutout = null;
      if (mounted) {
        setState(() {
          _cutout = cutout;
          _status = 'Identifying garment...';
        });
      }
      taggingImage = await _downscaleForTagging(edited);
      _taggingImage = taggingImage;
      taggingImage = null;
      final tags = await _repository.tag(
        taggingImage: _taggingImage!,
        token: widget.token,
      );
      await _clearTaggingImage();
      if (tags.isWornOnPerson) {
        await _deleteTemporaryFile(cutout);
        if (mounted) {
          setState(() {
            _cutout = null;
            _wornItemDetected = true;
            _status = _idleStatus;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _applyTags(tags);
          _status = 'Review item';
          _retryAvailableAt = null;
        });
      }
      _retryTimer?.cancel();
    } catch (error) {
      final isNonClothing = _isNonClothingError(error);
      final cutout = _cutout;
      if (isNonClothing && cutout != null) {
        await _deleteTemporaryFile(cutout);
      }
      if (mounted) {
        setState(() {
          _error = _messageFor(error);
          if (isNonClothing) {
            _cutout = null;
          }
          _status = _cutout != null ? 'Review item' : _idleStatus;
        });
        if (_cutout != null && _taggingImage != null) {
          final cooldown = _retryAfterSeconds(error) ?? 0;
          if (cooldown > 0) _startRetryCooldown(cooldown);
        }
      }
    } finally {
      if (cutoutSource != null) {
        await _deleteTemporaryFile(cutoutSource);
      }
      if (rawCutout != null) {
        await _deleteTemporaryFile(rawCutout);
      }
      if (taggingImage != null) {
        await _deleteTemporaryFile(taggingImage);
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _applyTags(ClothingTagResult tags) {
    _category = _categories.contains(tags.category) ? tags.category : 'Custom';
    _name.text = tags.itemName ?? '';
    _color.text = tags.color ?? '';
    _customCategory.text =
        _category == 'Custom' ? tags.customCategory ?? '' : '';
  }

  int get _retrySeconds {
    final availableAt = _retryAvailableAt;
    if (availableAt == null) return 0;
    final milliseconds = availableAt.difference(DateTime.now()).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds / 1000).ceil();
  }

  int? _retryAfterSeconds(Object error) {
    if (error is! DioException) return null;
    final header = error.response?.headers.value('retry-after');
    if (header == null) return null;
    final seconds = int.tryParse(header);
    return seconds == null ? null : seconds.clamp(1, 300);
  }

  void _startRetryCooldown(int seconds) {
    _retryTimer?.cancel();
    _retryAvailableAt = DateTime.now().add(
      Duration(seconds: seconds.clamp(1, 300)),
    );
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_retrySeconds == 0) {
        setState(() => _retryAvailableAt = null);
        timer.cancel();
        return;
      }
      setState(() {});
    });
  }

  Future<void> _clearTaggingImage() async {
    final taggingImage = _taggingImage;
    _taggingImage = null;
    if (taggingImage != null) {
      await _deleteTemporaryFile(taggingImage);
    }
  }

  Future<void> _retryAutoTag() async {
    final taggingImage = _taggingImage;
    if (_busy || _retrySeconds > 0 || taggingImage == null || _cutout == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Identifying garment...';
    });
    try {
      final tags = await _repository.tag(
        taggingImage: taggingImage,
        token: widget.token,
      );
      await _clearTaggingImage();
      if (tags.isWornOnPerson) {
        final cutout = _cutout;
        if (cutout != null) await _deleteTemporaryFile(cutout);
        if (mounted) {
          setState(() {
            _cutout = null;
            _wornItemDetected = true;
            _status = _idleStatus;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _applyTags(tags);
          _status = 'Review item';
          _retryAvailableAt = null;
        });
      }
      _retryTimer?.cancel();
    } catch (error) {
      final isNonClothing = _isNonClothingError(error);
      if (isNonClothing) {
        final cutout = _cutout;
        if (cutout != null) await _deleteTemporaryFile(cutout);
        await _clearTaggingImage();
      }
      if (mounted) {
        setState(() {
          _error = _messageFor(error);
          if (isNonClothing) {
            _cutout = null;
          }
          _status = _cutout != null ? 'Review item' : _idleStatus;
        });
        if (_cutout != null && _taggingImage != null) {
          final cooldown = _retryAfterSeconds(error) ?? 0;
          if (cooldown > 0) _startRetryCooldown(cooldown);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final cutout = _cutout;
    if (cutout == null || _busy) {
      return;
    }
    if (_category == 'Custom' && _customCategory.text.trim().isEmpty) {
      setState(() => _error = 'Enter a custom category name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Saving item...';
    });
    try {
      await _repository.manualUpload(
        cutout: cutout,
        token: widget.token,
        itemName: _name.text.trim(),
        category: _category,
        color: _color.text.trim(),
        customCategory:
            _category == 'Custom' ? _customCategory.text.trim() : null,
        idempotencyKey: _idempotencyKey ??= const Uuid().v4(),
      );
      await _deleteTemporaryFile(cutout);
      await _clearTaggingImage();
      if (mounted) {
        ref.read(wardrobeRevisionProvider.notifier).notifyChanged();
        setState(() {
          _cutout = null;
          _status = 'Item saved';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _messageFor(error);
          _status = 'Review item';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  img.Image _resizeToMaxSide(img.Image source, int maxSide) =>
      math.max(source.width, source.height) <= maxSide
          ? source
          : source.width >= source.height
          ? img.copyResize(source, width: maxSide)
          : img.copyResize(source, height: maxSide);
  Future<File> _prepareForCutout(File original) async {
    final source = img.decodeImage(await original.readAsBytes());
    if (source == null) {
      throw StateError('The selected image could not be decoded.');
    }
    final file = File(
      '${(await getTemporaryDirectory()).path}/la_maison_cutout_source_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(
      img.encodeJpg(
        _resizeToMaxSide(img.bakeOrientation(source), 1280),
        quality: 92,
      ),
      flush: true,
    );
    return file;
  }

  Future<File> _prepareCutoutForUpload(File cutout) async {
    final source = img.decodeImage(await cutout.readAsBytes());
    if (source == null) {
      throw StateError('The cutout could not be processed.');
    }
    final file = File(
      '${(await getTemporaryDirectory()).path}/la_maison_cutout_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(
      img.encodePng(_resizeToMaxSide(source, 1600), level: 6),
      flush: true,
    );
    return file;
  }

  Future<File> _downscaleForTagging(File original) async {
    final source = img.decodeImage(await original.readAsBytes());
    if (source == null) {
      throw StateError('The selected image could not be decoded.');
    }
    final file = File(
      '${(await getTemporaryDirectory()).path}/la_maison_tagging_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(
      img.encodeJpg(_resizeToMaxSide(source, 1280), quality: 85),
      flush: true,
    );
    return file;
  }

  Future<void> _deleteTemporaryFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // A stale temporary file is safe to leave for the operating system.
    }
  }

  bool _isNonClothingError(Object error) =>
      error is DioException &&
      error.response?.statusCode == 422 &&
      error.response?.data is Map &&
      ((error.response!.data as Map)['detail'] as String? ?? '').startsWith(
        'No clothing item was detected',
      );
  String _messageFor(Object error) {
    if (error is DioException &&
        error.response?.data is Map &&
        (error.response!.data as Map)['detail'] is String) {
      return (error.response!.data as Map)['detail'] as String;
    }
    if (error is StateError) {
      return error.message.toString();
    }
    return 'Could not add this item. Please try again.';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Add to wardrobe'),
        automaticallyImplyLeading: !_busy,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(_status, style: Theme.of(context).textTheme.titleMedium),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_wornItemDetected) _wornWarning(),
            if (_cutout != null) _reviewForm(),
            if (_cutout == null && !_busy) ...[
              _guidance(),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _choose(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Take photo'),
              ),
              OutlinedButton.icon(
                onPressed: () => _choose(ImageSource.gallery),
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
    ),
  );

  Widget _guidance() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F1FA),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text(
      'For a clean cutout, photograph one item laid flat or hanging on a contrasting background.',
    ),
  );
  Widget _wornWarning() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'We detected this item is being worn.\nFor a clean cutout, try photographing it flat or on a hanger instead.',
      ),
    ),
  );
  Widget _reviewForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      Image.file(_cutout!, height: 230),
      const SizedBox(height: 16),
      TextField(
        controller: _name,
        maxLength: 120,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        key: ValueKey(_category),
        initialValue: _category,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Category'),
        items:
            _categories
                .map(
                  (category) =>
                      DropdownMenuItem(value: category, child: Text(category)),
                )
                .toList(),
        onChanged:
            _busy
                ? null
                : (value) {
                  if (value != null) {
                    setState(() => _category = value);
                  }
                },
      ),
      if (_category == 'Custom') ...[
        const SizedBox(height: 10),
        TextField(
          controller: _customCategory,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Custom category'),
        ),
      ],
      const SizedBox(height: 10),
      TextField(
        controller: _color,
        maxLength: 50,
        decoration: const InputDecoration(labelText: 'Color'),
      ),
      const SizedBox(height: 20),
      if (_taggingImage != null) ...[
        OutlinedButton.icon(
          onPressed: _busy || _retrySeconds > 0 ? null : _retryAutoTag,
          icon: const Icon(Icons.refresh),
          label: Text(
            _retrySeconds > 0
                ? 'Retry auto-tagging in ${_retrySeconds}s'
                : 'Retry auto-tagging',
          ),
        ),
        const SizedBox(height: 10),
      ],
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('Save item'),
      ),
    ],
  );
}
