import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// ─── Data ─────────────────────────────────────────────────────────────────────

class _ProviderInfo {
  final String id;
  final String label;
  final String icon;
  final Color color;
  final String keyHint;
  final String keyHelper;
  final Map<String, String> models;

  const _ProviderInfo({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    required this.keyHint,
    required this.keyHelper,
    required this.models,
  });
}

final _providers = <_ProviderInfo>[
  _ProviderInfo(
    id: 'openrouter',
    label: 'OpenRouter',
    icon: '⚡',
    color: Color(0xFFFF6B35),
    keyHint: 'OpenRouter API Key (sk-or-...)',
    keyHelper: 'Получить на openrouter.ai',
    models: {
      'openrouter/auto': '⚡ Auto Router — лучшая модель автоматически',
      'deepseek/deepseek-r1:free': '🧠 DeepSeek R1 — рассуждение (Free)',
      'deepseek/deepseek-chat': '💬 DeepSeek V3 — чат (Premium)',
      'openai/gpt-4o': '🤖 GPT-4o',
      'openai/gpt-4o-mini': '🤖 GPT-4o Mini',
      'anthropic/claude-3.5-sonnet': '🎭 Claude 3.5 Sonnet',
      'anthropic/claude-3-haiku': '🎭 Claude 3 Haiku (быстрый)',
      'meta-llama/llama-3.3-70b-instruct:free': '🦙 Llama 3.3 70B (Free)',
      'qwen/qwen-2.5-72b-instruct:free': '🐉 Qwen 2.5 72B (Free)',
    },
  ),
  _ProviderInfo(
    id: 'gemini',
    label: 'Google Gemini',
    icon: '♊',
    color: Color(0xFF4285F4),
    keyHint: 'Gemini API Key (AIza...)',
    keyHelper: 'Получить на aistudio.google.com',
    models: {
      'gemini-2.5-flash': '♊ Gemini 2.5 Flash — быстрый и умный',
      'gemini-2.5-pro': '♊ Gemini 2.5 Pro — максимальные возможности',
      'gemini-2.0-flash': '♊ Gemini 2.0 Flash',
      'gemini-1.5-pro': '♊ Gemini 1.5 Pro — длинный контекст',
      'gemini-1.5-flash': '♊ Gemini 1.5 Flash (лёгкий)',
    },
  ),
];

// ─── State ────────────────────────────────────────────────────────────────────

class _SettingsScreenState extends State<SettingsScreen> {
  final _openrouterKeyCtrl = TextEditingController();
  final _geminiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController(
      text: 'https://vega-chats-production.up.railway.app');

  String _selectedProviderId = 'openrouter';
  String _selectedModel = 'openrouter/auto';
  String _selectedLocale = 'ru_RU';
  bool _developerMode = false;

  _ProviderInfo get _selectedProvider =>
      _providers.firstWhere((p) => p.id == _selectedProviderId,
          orElse: () => _providers.first);

  bool _isValidModel(String model) =>
      _selectedProvider.models.containsKey(model);

  String get _defaultModel => _selectedProvider.models.keys.first;

  // For the chat screen — final model id and provider to backend
  String get _modelForBackend => _selectedModel;
  String get _provider => _selectedProviderId;

  final _locales = const {
    'auto': '🌐 Системный язык',
    'ru_RU': '🇷🇺 Русский',
    'en_US': '🇺🇸 English',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final providerId = prefs.getString('provider') ?? 'openrouter';
    final model = prefs.getString('model_for_backend') ?? 'openrouter/auto';
    final locale = prefs.getString('speech_locale') ?? 'ru_RU';
    final baseUrl = prefs.getString('base_url') ??
        'https://vega-chats-production.up.railway.app';

    // Resolve provider from saved data (backward compat with old 'model' key)
    String resolvedProvider = providerId;
    String resolvedModel = model;
    // If old format had 'gemini:' prefix
    final oldModel = prefs.getString('model') ?? '';
    if (oldModel.startsWith('gemini:') && resolvedProvider == 'openrouter') {
      resolvedProvider = 'gemini';
      resolvedModel = oldModel.substring(7);
    }

    final providerInfo = _providers.firstWhere((p) => p.id == resolvedProvider,
        orElse: () => _providers.first);

    setState(() {
      _openrouterKeyCtrl.text = prefs.getString('api_key') ?? '';
      _geminiKeyCtrl.text = prefs.getString('gemini_api_key') ?? '';
      _baseUrlCtrl.text = baseUrl;
      _developerMode =
          baseUrl != 'https://vega-chats-production.up.railway.app';
      _selectedProviderId = providerInfo.id;
      _selectedModel = providerInfo.models.containsKey(resolvedModel)
          ? resolvedModel
          : providerInfo.models.keys.first;
      _selectedLocale = _locales.containsKey(locale) ? locale : 'ru_RU';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', _openrouterKeyCtrl.text);
    await prefs.setString('gemini_api_key', _geminiKeyCtrl.text);
    await prefs.setString('base_url', _baseUrlCtrl.text);
    await prefs.setString('speech_locale', _selectedLocale);
    await prefs.setString('provider', _provider);
    await prefs.setString('model_for_backend', _modelForBackend);
    // Legacy key kept in sync
    await prefs.setString('model', _selectedModel);
  }

  void _selectProvider(String id) {
    final provider = _providers.firstWhere((p) => p.id == id);
    setState(() {
      _selectedProviderId = id;
      _selectedModel = provider.models.keys.first;
    });
    _saveSettings();
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        title: const Text(
          'Настройки',
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

            // ── 1. Provider selector ──────────────────────────────────────
            _buildSectionHeader('Провайдер ИИ'),
            const SizedBox(height: 12),
            _buildProviderSelector(),
            const SizedBox(height: 24),

            // ── 2. Model selector (depends on provider) ───────────────────
            _buildSectionHeader('Модель'),
            const SizedBox(height: 12),
            _buildCard([
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      color: _selectedProvider.color, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    'Активная модель — ${_selectedProvider.label}',
                    style: const TextStyle(
                        color: VegaTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _isValidModel(_selectedModel)
                      ? _selectedModel
                      : _defaultModel,
                  isExpanded: true,
                  dropdownColor: VegaTheme.surface,
                  style: const TextStyle(
                      color: VegaTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  items: _selectedProvider.models.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _selectedModel = v);
                    _saveSettings();
                  },
                ),
              ),
              const SizedBox(height: 4),
            ]),
            const SizedBox(height: 24),

            // ── 3. API Keys ───────────────────────────────────────────────
            _buildSectionHeader('API-ключи'),
            const SizedBox(height: 12),
            _buildCard([
              _buildKeyField(
                controller: _openrouterKeyCtrl,
                label: 'OpenRouter API Key',
                helper: 'Получить на openrouter.ai',
                icon: Icons.key_rounded,
                color: const Color(0xFFFF6B35),
              ),
              const Divider(height: 28, color: VegaTheme.border),
              _buildKeyField(
                controller: _geminiKeyCtrl,
                label: 'Google Gemini API Key',
                helper: 'Получить на aistudio.google.com',
                icon: Icons.diamond_rounded,
                color: const Color(0xFF4285F4),
              ),
            ]),
            const SizedBox(height: 24),

            // ── 4. Voice ──────────────────────────────────────────────────
            _buildSectionHeader('Голос и речь'),
            const SizedBox(height: 12),
            _buildCard([
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.translate_rounded,
                      color: VegaTheme.accent, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Язык распознавания речи',
                    style:
                        TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLocale,
                  isExpanded: true,
                  dropdownColor: VegaTheme.surface,
                  style: const TextStyle(
                      color: VegaTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  items: _locales.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedLocale = v ?? _selectedLocale);
                    _saveSettings();
                  },
                ),
              ),
              const SizedBox(height: 4),
            ]),
            const SizedBox(height: 24),

            // ── 5. Developer ──────────────────────────────────────────────
            _buildSectionHeader('Для разработчиков'),
            const SizedBox(height: 12),
            _buildCard([
              SwitchListTile(
                title: const Text(
                  'Настройки разработчика',
                  style:
                      TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                ),
                subtitle: const Text(
                  'Переопределение адреса сервера для отладки',
                  style: TextStyle(
                      color: VegaTheme.textSecondary, fontSize: 12),
                ),
                value: _developerMode,
                activeColor: VegaTheme.accent,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) {
                  setState(() {
                    _developerMode = v;
                    if (!_developerMode) {
                      _baseUrlCtrl.text =
                          'https://vega-chats-production.up.railway.app';
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
                    controller: _baseUrlCtrl,
                    style: const TextStyle(
                        color: VegaTheme.textPrimary, fontSize: 14),
                    decoration: InputDecoration(
                      labelText: 'Адрес сервера (URL)',
                      labelStyle: const TextStyle(
                          color: VegaTheme.textSecondary, fontSize: 13),
                      prefixIcon: const Icon(Icons.dns_rounded,
                          color: VegaTheme.accent, size: 20),
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
                        borderSide:
                            const BorderSide(color: VegaTheme.accent),
                      ),
                    ),
                    onChanged: (_) => _saveSettings(),
                  ),
                ),
                crossFadeState: _developerMode
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 250),
              ),
            ]),
            const SizedBox(height: 32),

            Center(
              child: Text(
                'Vega Chat v1.2.0 • Сделано с ❤️',
                style: TextStyle(
                    color: VegaTheme.textSecondary.withOpacity(0.6),
                    fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Provider selector ────────────────────────────────────────────────────

  Widget _buildProviderSelector() {
    return Row(
      children: _providers.map((p) {
        final isSelected = p.id == _selectedProviderId;
        return Expanded(
          child: GestureDetector(
            onTap: () => _selectProvider(p.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                  right: p == _providers.last ? 0 : 10),
              padding:
                  const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? p.color.withOpacity(0.15)
                    : VegaTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? p.color : VegaTheme.border,
                  width: isSelected ? 1.5 : 0.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: p.color.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ]
                    : [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.icon, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(
                    p.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          isSelected ? p.color : VegaTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 24,
                      height: 3,
                      decoration: BoxDecoration(
                        color: p.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Widget _buildKeyField({
    required TextEditingController controller,
    required String label,
    required String helper,
    required IconData icon,
    required Color color,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, color: color, size: 20),
        border: UnderlineInputBorder(
            borderSide: BorderSide(color: VegaTheme.border)),
        enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: VegaTheme.border)),
        focusedBorder:
            UnderlineInputBorder(borderSide: BorderSide(color: color)),
        helperText: helper,
        helperStyle:
            const TextStyle(color: VegaTheme.textSecondary, fontSize: 11),
      ),
      obscureText: true,
      onChanged: (_) => _saveSettings(),
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
    _openrouterKeyCtrl.dispose();
    _geminiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }
}
