import 'package:flutter/material.dart';

class SettingsModal extends StatefulWidget {
  final String currentServerUrl;
  final Function(String newUrl) onSave;

  const SettingsModal({
    super.key,
    required this.currentServerUrl,
    required this.onSave,
  });

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  late TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.currentServerUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAlignment: CrossAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.settings, color: Color(0xFF6366F1)),
              const SizedBox(width: 10),
              const Text(
                'Socket Server Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Specify the Node.js + Socket.io server backend endpoint:',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Backend Socket URL',
              hintText: 'http://10.0.2.2:3000 or http://localhost:3000',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ActionChip(
                label: const Text('Android (10.0.2.2:3000)'),
                onPressed: () {
                  _urlController.text = 'http://10.0.2.2:3000';
                },
              ),
              const SizedBox(width: 8),
              ActionChip(
                label: const Text('Localhost (3000)'),
                onPressed: () {
                  _urlController.text = 'http://localhost:3000';
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final url = _urlController.text.trim();
                if (url.isNotEmpty) {
                  widget.onSave(url);
                  Navigator.pop(context);
                }
              },
              child: const Text('Save & Reconnect'),
            ),
          ),
        ],
      ),
    );
  }
}
