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
  String _selectedLocale = 'ru_RU';
  bool _developerMode = false;

  final Map<String, String> _modelNames = {
    'openrouter/auto': '⚡ Auto Router (Best Choice)',
    'deepseek/deepseek-r1:free': '🧠 DeepSeek R1 (Free Reasoning)',
    'deepseek/deepseek-chat': '💬 DeepSeek V3 (Premium Chat)',
    'google/gemini-2.5-flash': '♊ Gemini 2.5 Flash (Fast)',
    'google/gemini-2.5-pro': '♊ Gemini 2.5 Pro (Powerful)',
    'google/gemini-2.0-flash-exp:free': '♊ Gemini 2.0 Flash Exp (Free)',
    'openai/gpt-4o': '🤖 OpenAI GPT-4o',
    'openai/gpt-4o-mini': '🤖 OpenAI GPT-4o Mini',
    'anthropic/claude-3.5-sonnet': '🎭 Claude 3.5 Sonnet',
    'meta-llama/llama-3.3-70b-instruct:free': '🦙 Llama 3.3 70B (Free)',
    'qwen/qwen-2.5-72b-instruct:free': '🐉 Qwen 2.5 72B (Free)',
  };

  final Map<String, String> _locales = {
    'auto': '🌐 System Default (Auto)',
    'ru_RU': '🇷🇺 Russian (Русский)',
    'en_US': '🇺🇸 English (United States)',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('api_key') ?? '';
    final baseUrl = prefs.getString('base_url') ?? 'https://vega-chats-production.up.railway.app';
    final model = prefs.getString('model') ?? 'openrouter/auto';
    final locale = prefs.getString('speech_locale') ?? 'ru_RU';

    setState(() {
      _apiKeyController.text = apiKey;
      _baseUrlController.text = baseUrl;
      // Auto enable developer mode if custom URL is set
      _developerMode = baseUrl != 'https://vega-chats-production.up.railway.app';
      
      // Ensure model exists in our map
      _selectedModel = _modelNames.containsKey(model) ? model : 'openrouter/auto';
      _selectedLocale = _locales.containsKey(locale) ? locale : 'ru_RU';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', _apiKeyController.text);
    await prefs.setString('base_url', _baseUrlController.text);
    await prefs.setString('model', _selectedModel);
    await prefs.setString('speech_locale', _selectedLocale);
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            color: VegaTheme.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        backgroundColor: VegaTheme.dark,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.opaque,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // Section 1: API Config
            _buildSectionHeader('API Credentials'),
            const SizedBox(height: 12),
            _buildCard([
              TextField(
                controller: _apiKeyController,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'OpenRouter API Key',
                  labelStyle: const TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  prefixIcon: const Icon(Icons.key_rounded, color: VegaTheme.accent, size: 20),
                  border: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.border)),
                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: VegaTheme.accent)),
                ),
                obscureText: true,
                onChanged: (_) => _saveSettings(),
              ),
            ]),
            const SizedBox(height: 24),

            // Section 2: LLM Configuration
            _buildSectionHeader('Model Settings'),
            const SizedBox(height: 12),
            _buildCard([
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: VegaTheme.accent, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Active Assistant Model',
                    style: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedModel,
                  isExpanded: true,
                  dropdownColor: VegaTheme.surface,
                  style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                  items: _modelNames.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setState(() => _selectedModel = v ?? _selectedModel);
                    _saveSettings();
                  },
                ),
              ),
              const SizedBox(height: 8),
            ]),
            const SizedBox(height: 24),

            // Section 3: Speech Settings
            _buildSectionHeader('Voice & Accessibility'),
            const SizedBox(height: 12),
            _buildCard([
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(Icons.translate_rounded, color: VegaTheme.accent, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Voice Recognition Language',
                    style: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLocale,
                  isExpanded: true,
                  dropdownColor: VegaTheme.surface,
                  style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
                  items: _locales.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setState(() => _selectedLocale = v ?? _selectedLocale);
                    _saveSettings();
                  },
                ),
              ),
              const SizedBox(height: 8),
            ]),
            const SizedBox(height: 24),

            // Section 4: Developer Options
            _buildSectionHeader('Developer Area'),
            const SizedBox(height: 12),
            _buildCard([
              SwitchListTile(
                title: const Text(
                  'Custom Developer Settings',
                  style: TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                ),
                subtitle: const Text(
                  'Allows overriding host endpoints for debugging',
                  style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
                ),
                value: _developerMode,
                activeColor: VegaTheme.accent,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) {
                  setState(() {
                    _developerMode = v;
                    if (!_developerMode) {
                      // Reset to default production URL when turned off
                      _baseUrlController.text = 'https://vega-chats-production.up.railway.app';
                      _saveSettings();
                    }
                  });
                },
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                  child: TextField(
                    controller: _baseUrlController,
                    style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Backend Connection URL',
                      labelStyle: const TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                      prefixIcon: const Icon(Icons.dns_rounded, color: VegaTheme.accent, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: VegaTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: VegaTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: VegaTheme.accent),
                      ),
                    ),
                    onChanged: (_) => _saveSettings(),
                  ),
                ),
                crossFadeState: _developerMode ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
              ),
            ]),
            const SizedBox(height: 32),
            
            // Build Info
            Center(
              child: Text(
                'Vega Chat v1.1.0 • Built with ❤️',
                style: TextStyle(color: VegaTheme.textSecondary.withOpacity(0.6), fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: VegaTheme.accent,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: VegaTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VegaTheme.border, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
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
