import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:native_cutout/native_cutout.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../data/background_upload_queue.dart';
import '../data/wardrobe_repository.dart';
import '../domain/clothing_item_draft.dart';
import 'cutout_editor_screen.dart';
import 'wardrobe_item_editor_dialog.dart';

final class UploadRouteArgs {
  const UploadRouteArgs({required this.token, required this.email});

  final String token;
  final String email;
}

class UploadScreen extends StatefulWidget {
  const UploadScreen({required this.token, required this.email, super.key});

  final String token;
  final String email;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  static const _idleStatus = 'Choose a clothing photo';
  final _picker = ImagePicker();
  final _repository = WardrobeRepository(ApiClient());
  final _backgroundQueue = BackgroundUploadQueue();
  ClothingItemDraft? _draft;
  File? _manualCutout;
  bool _manualTaggingNeeded = false;
  String? _error;
  String _status = _idleStatus;
  bool _busy = false;
  String? _idempotencyKey;
  String? _queuedJobId;
  Timer? _jobWatcher;
  bool _checkingJob = false;

  @override
  void dispose() {
    _jobWatcher?.cancel();
    super.dispose();
  }

  Future<void> _choose(ImageSource source) async {
    if (_busy) return;
    File? cutoutSource;
    File? taggingImage;
    setState(() {
      _busy = true;
      _error = null;
      _draft = null;
      _manualCutout = null;
      _manualTaggingNeeded = false;
      _idempotencyKey = const Uuid().v4();
      _queuedJobId = null;
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
      final preparedCutoutSource = await _prepareForCutout(editedPhoto);
      cutoutSource = preparedCutoutSource;
      final cutout = await _removeBackground(preparedCutoutSource);
      await _deleteTemporaryFile(preparedCutoutSource);
      cutoutSource = null;
      if (mounted) setState(() => _status = 'Optimizing cutout for upload…');
      final uploadCutout = await _prepareCutoutForUpload(cutout);
      await NativeCutout.clearCache();
      _manualCutout = uploadCutout;
      if (mounted) {
        setState(() => _status = 'Downscaling the original for Gemini…');
      }
      final preparedTaggingImage = await _downscaleForTagging(editedPhoto);
      taggingImage = preparedTaggingImage;
      if (mounted) setState(() => _status = 'Queueing secure upload…');
      final job = await _backgroundQueue.enqueueAuto(
        id: const Uuid().v4(),
        idempotencyKey: _idempotencyKey!,
        ownerEmail: widget.email,
        cutout: uploadCutout,
        taggingImage: preparedTaggingImage,
      );
      await _deleteTemporaryFile(preparedTaggingImage);
      taggingImage = null;
      await _deleteTemporaryFile(uploadCutout);
      if (mounted) {
        setState(() {
          _queuedJobId = job.id;
          _manualCutout = null;
          _status = 'Upload queued. You can safely leave this screen.';
        });
        _watchJob(job.id);
      }
    } catch (error) {
      final isNonClothing = _isNonClothingError(error);
      if (isNonClothing && _manualCutout != null) {
        await _deleteTemporaryFile(_manualCutout!);
        _manualCutout = null;
      }
      if (mounted) {
        setState(() {
          _error = _messageFor(error);
          _manualTaggingNeeded = _manualCutout != null && !isNonClothing;
          _status =
              _manualTaggingNeeded
                  ? 'Auto-tagging failed. Add details manually.'
                  : _idleStatus;
        });
      }
    } finally {
      if (cutoutSource != null) await _deleteTemporaryFile(cutoutSource);
      if (taggingImage != null) await _deleteTemporaryFile(taggingImage);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _watchJob(String jobId) {
    _jobWatcher?.cancel();
    _checkJob(jobId);
    _jobWatcher = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkJob(jobId),
    );
  }

  Future<void> _checkJob(String jobId) async {
    if (_checkingJob) return;
    _checkingJob = true;
    try {
      final job = await _backgroundQueue.read(jobId);
      if (!mounted || job == null || _queuedJobId != jobId) return;
      switch (job.status) {
        case BackgroundUploadStatus.queued:
          if (job.error != null) setState(() => _status = 'Retrying upload…');
          return;
        case BackgroundUploadStatus.completed:
          _jobWatcher?.cancel();
          setState(() {
            _queuedJobId = null;
            _draft = job.completedDraft;
            _error = null;
            _status = 'Review the detected tags';
          });
          return;
        case BackgroundUploadStatus.manualRequired:
          _jobWatcher?.cancel();
          setState(() {
            _queuedJobId = null;
            _manualCutout = File(job.cutoutPath);
            _manualTaggingNeeded = true;
            _error = job.error;
            _status = 'Auto-tagging failed. Add details manually.';
          });
          return;
        case BackgroundUploadStatus.rejected:
        case BackgroundUploadStatus.failed:
          _jobWatcher?.cancel();
          setState(() {
            _queuedJobId = null;
            _manualCutout = null;
            _manualTaggingNeeded = false;
            _error = job.error;
            _status = _idleStatus;
          });
          return;
      }
    } finally {
      _checkingJob = false;
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

  Future<File> _prepareForCutout(File original) async {
    final source = img.decodeImage(await original.readAsBytes());
    if (source == null) {
      throw StateError('The selected image could not be decoded.');
    }

    final normalized = _resizeToMaxSide(img.bakeOrientation(source), 1280);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/drip_cutout_source_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(
      img.encodeJpg(normalized, quality: 92),
      flush: true,
    );
    return file;
  }

  Future<void> _deleteTemporaryFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cache cleanup must never interrupt a successful wardrobe operation.
    }
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

  bool _isNonClothingError(Object error) {
    if (error is! DioException || error.response?.statusCode != 422) {
      return false;
    }
    final data = error.response?.data;
    return data is Map &&
        data['detail'] is String &&
        (data['detail'] as String).startsWith('No clothing item was detected');
  }

  Future<void> _saveEdits() async {
    final draft = _draft;
    if (draft == null) return;
    final result = await showDialog<ItemEditValues>(
      context: context,
      builder:
          (context) =>
              WardrobeItemEditorDialog(item: draft, title: 'Review item tags'),
    );
    if (result == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Saving your edits…';
    });
    try {
      final updated = await _repository.update(
        draft: draft,
        token: widget.token,
        itemName: result.itemName,
        category: result.category,
        customCategory: result.customCategory,
        color: result.color,
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveManualTags() async {
    final cutout = _manualCutout;
    if (cutout == null) return;
    final result = await showDialog<ItemEditValues>(
      context: context,
      builder:
          (context) => WardrobeItemEditorDialog(
            item: ClothingItemDraft(
              id: '',
              cloudinaryUrl: cutout.path,
              category: 'Custom',
            ),
            title: 'Add item details',
          ),
    );
    if (result == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Saving your item…';
    });
    try {
      final job = await _backgroundQueue.enqueueManual(
        id: const Uuid().v4(),
        idempotencyKey: _idempotencyKey ??= const Uuid().v4(),
        ownerEmail: widget.email,
        cutout: cutout,
        itemName: result.itemName,
        category: result.category,
        color: result.color,
        customCategory: result.customCategory,
      );
      await _deleteTemporaryFile(cutout);
      if (mounted) {
        setState(() {
          _queuedJobId = job.id;
          _manualCutout = null;
          _manualTaggingNeeded = false;
          _status = 'Upload queued. You can safely leave this screen.';
        });
        _watchJob(job.id);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _messageFor(error);
          _status = 'Manual save failed. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _busy && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your image is still being processed. Please wait.'),
          ),
        );
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Add to wardrobe'),
        automaticallyImplyLeading: !_busy,
      ),
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
            if (_queuedJobId != null) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              const Text(
                'DRIP will retry this upload automatically when a connection is available.',
                textAlign: TextAlign.center,
              ),
            ] else if (_manualTaggingNeeded && _manualCutout != null) ...[
              const SizedBox(height: 12),
              Image.file(_manualCutout!, height: 180),
              FilledButton(
                onPressed: _busy ? null : _saveManualTags,
                child: const Text('Add tags manually'),
              ),
            ],
            const SizedBox(height: 20),
            if (_draft != null) ...[
              Image.network(
                _draft!.cloudinaryUrl,
                height: 220,
                errorBuilder:
                    (_, _, _) =>
                        const Icon(Icons.image_not_supported, size: 80),
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
                onPressed: _busy ? null : _saveEdits,
                child: const Text('Review / edit tags'),
              ),
            ] else if (_queuedJobId == null) ...[
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
    ),
  );
}
