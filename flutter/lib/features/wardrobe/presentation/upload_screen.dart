import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:native_cutout/native_cutout.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';
import '../data/wardrobe_repository.dart';
import '../domain/clothing_item_draft.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({required this.token, super.key});

  final String token;

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final _picker = ImagePicker();
  final _repository = WardrobeRepository(ApiClient());
  ClothingItemDraft? _draft;
  String? _error;
  String _status = 'Choose a clothing photo';
  bool _busy = false;

  Future<void> _choose(ImageSource source) async {
    setState(() { _busy = true; _error = null; _status = 'Opening image…'; });
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 92);
      if (picked == null) return;
      final original = File(picked.path);
      setState(() => _status = 'Preparing on-device cutout…');
      if (!await NativeCutout.isModelAvailable() && !await NativeCutout.downloadModel()) {
        throw StateError('The on-device model could not be downloaded. Connect once and retry.');
      }
      final result = await NativeCutout.removeBackground(original.path, options: const CutoutOptions(cropToSubject: true, writeToCache: true));
      if (result is! CutoutFileSuccess) {
        throw StateError(result is CutoutFailure ? result.message : 'Could not remove the background.');
      }
      setState(() => _status = 'Downscaling the original for Gemini…');
      final taggingImage = await _downscaleForTagging(original);
      setState(() => _status = 'Identifying and saving tags…');
      final draft = await _repository.upload(cutout: File(result.path), taggingImage: taggingImage, token: widget.token);
      if (mounted) setState(() => _draft = draft);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<File> _downscaleForTagging(File original) async {
    final source = img.decodeImage(await original.readAsBytes());
    if (source == null) throw StateError('The selected image could not be decoded.');
    final resized = source.width > 1024 ? img.copyResize(source, width: 1024) : source;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/drip_tagging_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(img.encodeJpg(resized, quality: 82), flush: true);
    return file;
  }

  Future<void> _saveEdits() async {
    final draft = _draft;
    if (draft == null) return;
    final name = TextEditingController(text: draft.itemName ?? '');
    final category = TextEditingController(text: draft.category);
    final color = TextEditingController(text: draft.color ?? '');
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review item tags'),
        content: SingleChildScrollView(child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          TextField(controller: category, decoration: const InputDecoration(labelText: 'Category')),
          TextField(controller: color, decoration: const InputDecoration(labelText: 'Color')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, [name.text, category.text, color.text]), child: const Text('Save')),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _status = 'Saving your edits…');
    try {
      final updated = await _repository.update(draft: draft, token: widget.token, itemName: result[0], category: result[1], color: result[2]);
      setState(() { _draft = updated; _status = 'Item saved'; });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Add to wardrobe')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_status),
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: Colors.red))],
            const SizedBox(height: 20),
            if (_draft != null) ...[
              Image.network(_draft!.cloudinaryUrl, height: 220, errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported, size: 80)),
              Text('AI confidence: ${(_draft!.confidence * 100).round()}%'),
              FilledButton(onPressed: _saveEdits, child: const Text('Review / edit tags')),
            ] else ...[
              FilledButton.icon(onPressed: _busy ? null : () => _choose(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('Take photo')),
              OutlinedButton.icon(onPressed: _busy ? null : () => _choose(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('Choose from gallery')),
            ],
            if (_busy) const Padding(padding: EdgeInsets.only(top: 20), child: LinearProgressIndicator()),
          ]),
        ),
      );
}
