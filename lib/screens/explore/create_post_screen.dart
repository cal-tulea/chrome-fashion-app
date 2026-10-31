import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/ootd_feed_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _picker = ImagePicker();
  final _captionCtrl = TextEditingController();

  File? _image;
  bool _posting = false;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    setState(() => _image = File(x.path));
  }

  Future<void> _takePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (x == null) return;
    setState(() => _image = File(x.path));
  }

  Future<void> _post() async {
    if (_image == null) return;

    setState(() => _posting = true);
    await OotdFeedService().createPost(
      imageFile: _image!,
      caption: _captionCtrl.text,
    );
    await OotdFeedService().load();

    if (!mounted) return;
    setState(() => _posting = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F2),
      appBar: AppBar(title: const Text('New OOTD')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: 320,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black12),
            ),
            child: _image == null
                ? const Center(
                    child: Text(
                      'Add a photo',
                      style: TextStyle(color: Colors.black54),
                    ),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.file(_image!, fit: BoxFit.cover),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _posting ? null : _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _posting ? null : _takePhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _captionCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Caption (optional)…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (_image == null || _posting) ? null : _post,
              child: Text(_posting ? 'Posting…' : 'Post'),
            ),
          ),
        ],
      ),
    );
  }
}
