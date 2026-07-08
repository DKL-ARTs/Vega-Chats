import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController(text: 'https://vega-chats-production.up.railway.app');
  String _selectedModel = 'openrouter/auto';

  final _models = [
    'openrouter/auto',
    'openai/gpt-4o',
    'openai/gpt-4o-mini',
    'anthropic/claude-sonnet-4',
    'deepseek/deepseek-chat',
    'google/gemini-2.0-flash',
    'owl-alpha',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('api_key') ?? '';
      _baseUrlController.text = prefs.getString('base_url') ?? 'https://vega-chat-production.up.railway.app';
      _selectedModel = prefs.getString('model') ?? 'owl-alpha';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', _apiKeyController.text);
    await prefs.setString('base_url', _baseUrlController.text);
    await prefs.setString('model', _selectedModel);
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: VegaTheme.textPrimary)),
        backgroundColor: VegaTheme.dark,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.opaque,
        child: ListView(
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
              onChanged: (_) => _saveSettings(),
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
              onChanged: (_) => _saveSettings(),
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
                  onChanged: (v) {
                    setState(() => _selectedModel = v ?? _selectedModel);
                    _saveSettings();
                  },
                ),
              ),
            ),
          ],
        ),
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
