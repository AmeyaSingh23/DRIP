import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
import '../../../core/widgets/hanger_loading_indicator.dart';

final class UploadRouteArgs {
  const UploadRouteArgs({ required this.email});
  final String email;
}

@pragma('vm:entry-point')
img.Image? _decodeImageIsolateWorker(Uint8List bytes) {
  return img.decodeImage(bytes);
}

Future<img.Image?> _decodeImageIsolate(Uint8List bytes) => compute(_decodeImageIsolateWorker, bytes);


class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({ required this.email, super.key});
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
  void initState() {
    super.initState();
  }

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
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
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
        _name.clear();
        _customCategory.clear();
        _color.clear();
        _category = 'Custom';
        setState(() => _status = 'Removing background...');
      }
      cutoutSource = await _prepareForCutout(edited);
      rawCutout = File(
        '${(await getTemporaryDirectory()).path}/la_maison_rapidapi_cutout_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await rawCutout.writeAsBytes(
        await _repository.removeBackground(
          image: cutoutSource,
          
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
    FocusScope.of(context).unfocus();
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
    final source = await _decodeImageIsolate(await original.readAsBytes());
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
    final source = await _decodeImageIsolate(await cutout.readAsBytes());
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
    final source = await _decodeImageIsolate(await original.readAsBytes());
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
        final length = await file.length();
        if (length > 0) {
          final zeros = List<int>.filled(length, 0);
          await file.writeAsBytes(zeros, flush: true);
        }
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
    if (error is DioException && error.response?.statusCode != 500) {
      final detail = error.response?.data is Map ? (error.response!.data as Map)['detail'] : null;
      if (detail is String && detail.isNotEmpty) {
        return detail;
      }
    }
    if (error is StateError) {
      return error.message.toString();
    }
    return 'Could not add this item. Please try again.';
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Add to wardrobe'),
        automaticallyImplyLeading: !_busy,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              color: Theme.of(context).colorScheme.surface,
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: Theme.of(context).textTheme.titleMedium),
              if (_error != null) _errorBox(_error!),
              if (_wornItemDetected) _wornWarning(),
              if (_cutout != null) _reviewForm(),
              if (_cutout == null && !_busy) ...[
                const SizedBox(height: 16),
                _guidance(),
                const SizedBox(height: 16),
                _glassButton(
                onPressed: _busy ? null : () => _choose(ImageSource.camera),
                icon: Icons.camera_alt,
                label: 'Take photo',
                isGlass: true,
              ),
              const SizedBox(height: 12),
              _glassButton(
                onPressed: _busy ? null : () => _choose(ImageSource.gallery),
                icon: Icons.photo_library,
                label: 'Choose from gallery',
                isGlass: true,
              ),
              ],
              if (_busy && _cutout == null)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: HangerLoadingIndicator()),
                ),
            ],
          ),
        ),
      ),
    ),
    ),
  );

  Widget _errorBox(String message) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.red.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.2),
        child: Text(
          message,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.red[200] : Colors.red[900],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

  Widget _guidance() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        color: Theme.of(context).colorScheme.surface,
        child: Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Theme.of(context).colorScheme.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'For a clean cutout, photograph one item laid flat or hanging on a contrasting background.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
  );

  Widget _wornWarning() => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.orange.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.2),
        child: Text(
          'We detected this item is being worn.\nFor a clean cutout, try photographing it flat or on a hanger instead.',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark ? Colors.orange[200] : Colors.orange[900],
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );

  InputDecoration _glassInputDecoration(String hint, {bool isDropdown = false}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
      filled: true,
      fillColor: Colors.transparent,
      counterText: "",
      suffixIcon: _status == 'Identifying garment...' ? Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onSurface),
        ),
      ) : isDropdown ? Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.onSurface) : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 4),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }

  void _showCategoryPicker() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[900]!.withOpacity(0.85)
                : Colors.white.withOpacity(0.85),
            child: SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 16),
                children: _categories.map((c) => ListTile(
                  title: Text(c, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w500)),
                  onTap: () {
                    setState(() => _category = c);
                    Navigator.pop(context);
                  },
                )).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassButton({
    required VoidCallback? onPressed,
    IconData? icon,
    required String label,
    Color? backgroundColor,
    Color? textColor,
    bool isGlass = false,
  }) {
    final bgColor = isGlass
        ? (Theme.of(context).brightness == Brightness.dark ? Colors.grey[900]!.withOpacity(0.50) : Colors.white.withOpacity(0.50))
        : (backgroundColor ?? Theme.of(context).colorScheme.primary);
    final fgColor = isGlass
        ? Theme.of(context).colorScheme.onSurface
        : (textColor ?? Theme.of(context).colorScheme.onPrimary);
    
    Widget buttonBody = Material(
      color: onPressed == null ? bgColor.withOpacity(0.3) : bgColor,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: onPressed == null ? fgColor.withOpacity(0.5) : fgColor),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: onPressed == null ? fgColor.withOpacity(0.5) : fgColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isGlass) {
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: buttonBody,
          ),
        ),
      );
    }
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: buttonBody,
    );
  }

  Widget _glassField({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: child,
      ),
    );
  }

  Widget _charCounter(TextEditingController controller, int max) {
    return Align(
      alignment: Alignment.centerRight,
      child: ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, value, child) => Padding(
          padding: const EdgeInsets.only(top: 4, right: 4),
          child: Text(
            '${value.text.length}/$max',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _reviewForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      Image.file(_cutout!, height: 230),
      const SizedBox(height: 16),
      _fieldLabel('Name'),
      _glassField(
        child: TextField(
          controller: _name,
          maxLength: 120,
          decoration: _glassInputDecoration('Enter item name'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          enabled: !_busy,
        ),
      ),
      _charCounter(_name, 120),
      const SizedBox(height: 10),
      _fieldLabel('Category'),
      _glassField(
        child: InkWell(
          onTap: _busy ? null : _showCategoryPicker,
          child: InputDecorator(
            decoration: _glassInputDecoration('Select a category', isDropdown: true),
            isEmpty: _category.isEmpty,
            child: Text(_category, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          ),
        ),
      ),
      if (_category == 'Custom') ...[
        const SizedBox(height: 16),
        _fieldLabel('Custom Category'),
        _glassField(
          child: TextField(
            controller: _customCategory,
            maxLength: 100,
            decoration: _glassInputDecoration('Enter custom category'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            enabled: !_busy,
          ),
        ),
        _charCounter(_customCategory, 100),
      ],
      const SizedBox(height: 16),
      _fieldLabel('Color'),
      _glassField(
        child: TextField(
          controller: _color,
          maxLength: 50,
          decoration: _glassInputDecoration('Enter color'),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          enabled: !_busy,
        ),
      ),
      _charCounter(_color, 50),
      const SizedBox(height: 24),
      if (_error != null && _taggingImage != null) ...[
        _glassButton(
          onPressed: _busy || _retrySeconds > 0 ? null : _retryAutoTag,
          icon: Icons.refresh,
          label: _retrySeconds > 0
                ? 'Retry auto-tagging in ${_retrySeconds}s'
                : 'Retry auto-tagging',
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
          textColor: Theme.of(context).colorScheme.onErrorContainer,
        ),
        const SizedBox(height: 12),
      ],
      _glassButton(
        onPressed: _busy ? null : _save,
        label: _status == 'Saving item...' ? 'Saving...' : 'Save item',
        backgroundColor: Theme.of(context).colorScheme.secondary,
        textColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
      ),
    ],
  );
}


