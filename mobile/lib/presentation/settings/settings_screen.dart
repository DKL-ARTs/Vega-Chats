import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController(text: 'http://127.0.0.1:8765');
  String _selectedModel = 'openrouter/auto';

  final _models = [
    'openrouter/auto',
    'openai/gpt-4o',
    'openai/gpt-4o-mini',
    'anthropic/claude-sonnet-4',
    'deepseek/deepseek-chat',
    'google/gemini-2.0-flash',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: VegaTheme.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('API Configuration', style: TextStyle(color: VegaTheme.accent, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            style: TextStyle(color: VegaTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'OpenRouter API Key',
              labelStyle: TextStyle(color: VegaTheme.textSecondary),
              border: OutlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _baseUrlController,
            style: TextStyle(color: VegaTheme.textPrimary),
            decoration: InputDecoration(
              labelText: 'Backend URL',
              labelStyle: TextStyle(color: VegaTheme.textSecondary),
              border: OutlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
            ),
          ),
          const SizedBox(height: 24),
          Text('Default Model', style: TextStyle(color: VegaTheme.accent, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: VegaTheme.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedModel,
                isExpanded: true,
                dropdownColor: VegaTheme.surface,
                style: TextStyle(color: VegaTheme.textPrimary),
                items: _models.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _selectedModel = v ?? _selectedModel),
              ),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Settings saved')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: VegaTheme.accent,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }
}
