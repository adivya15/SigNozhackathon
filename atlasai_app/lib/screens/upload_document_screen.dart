import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/storage_service.dart';

class UploadDocumentScreen extends StatefulWidget {
  const UploadDocumentScreen({super.key});

  @override
  State<UploadDocumentScreen> createState() =>
      _UploadDocumentScreenState();
}

class _UploadDocumentScreenState
    extends State<UploadDocumentScreen> {
  final StorageService _storageService = StorageService();
  final TextEditingController _equipmentController =
      TextEditingController();

  bool _loading = false;
  String? _fileName;
  Map<String, dynamic>? _result;
  String? _error;

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (picked == null || picked.files.single.path == null) {
      return;
    }

    final file = File(picked.files.single.path!);

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
      _fileName = picked.files.single.name;
    });

    try {
      final result = await _storageService.uploadAndIngest(
        file,
        picked.files.single.name,
        equipmentId: _equipmentController.text.trim().isEmpty
            ? null
            : _equipmentController.text.trim(),
      );

      setState(() {
        _loading = false;
        _result = result;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _equipmentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Upload Document"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _equipmentController,
              decoration: const InputDecoration(
                labelText: "Equipment ID (Optional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loading ? null : _pickAndUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text("Pick PDF & Upload"),
            ),
            const SizedBox(height: 25),
            if (_loading) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text("Uploading $_fileName ..."),
            ],
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),
            if (_result != null)
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Upload Successful ✅",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text("File: $_fileName"),
                      Text("Status: ${_result!['status']}"),
                      Text("Pages: ${_result!['pageCount']}"),
                      Text("Chunks: ${_result!['chunkCount']}"),
                      Text("Document ID: ${_result!['docId']}"),
                      const SizedBox(height: 10),
                      const Text(
                        "Equipment Tags",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: List<String>.from(
                          _result!['equipmentTags'] ?? [],
                        )
                            .map((e) => Chip(label: Text(e)))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}