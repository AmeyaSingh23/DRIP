import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

class CutoutEditorScreen extends StatefulWidget {
  const CutoutEditorScreen({required this.image, super.key});

  final File image;

  @override
  State<CutoutEditorScreen> createState() => _CutoutEditorScreenState();
}

class _CutoutEditorScreenState extends State<CutoutEditorScreen> {
  late File _current;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _current = widget.image;
  }

  Future<void> _rotate(int degrees) async {
    setState(() => _editing = true);
    try {
      final source = img.decodeImage(await _current.readAsBytes());
      if (source == null) throw StateError('The photo could not be rotated.');
      final rotated = img.copyRotate(source, angle: degrees);
      final directory = await getTemporaryDirectory();
      final output = File(
        '${directory.path}/la_maison_photo_rotate_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await output.writeAsBytes(img.encodePng(rotated, level: 6), flush: true);
      if (mounted) setState(() => _current = output);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not rotate this photo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _crop() async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: _current.path,
        compressFormat: ImageCompressFormat.png,
        compressQuality: 100,
        maxWidth: 1280,
        maxHeight: 1280,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop photo',
            toolbarColor: Theme.of(context).colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
          ),
        ],
      );
      if (cropped != null && mounted) {
        setState(() => _current = File(cropped.path));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the crop tool. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Adjust photo'),
      actions: [
        TextButton(
          onPressed: _editing ? null : () => Navigator.pop(context, _current),
          child: const Text('Continue'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text(
              'Crop tightly while keeping the full garment in frame. Your original photo won’t be changed.',
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(24),
              color: const Color(0xFFFAFAF8),
              alignment: Alignment.center,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.file(_current, fit: BoxFit.contain),
              ),
            ),
          ),
          if (_editing) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _EditorAction(
                  icon: Icons.rotate_left,
                  label: 'Rotate left',
                  onPressed: _editing ? null : () => _rotate(-90),
                ),
                _EditorAction(
                  icon: Icons.crop,
                  label: 'Crop',
                  onPressed: _editing ? null : _crop,
                ),
                _EditorAction(
                  icon: Icons.rotate_right,
                  label: 'Rotate right',
                  onPressed: _editing ? null : () => _rotate(90),
                ),
                _EditorAction(
                  icon: Icons.restart_alt,
                  label: 'Reset',
                  onPressed:
                      _editing
                          ? null
                          : () => setState(() => _current = widget.image),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _EditorAction extends StatelessWidget {
  const _EditorAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(onPressed: onPressed, icon: Icon(icon)),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
