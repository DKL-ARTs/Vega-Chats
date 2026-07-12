import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

// ─── Data ─────────────────────────────────────────────────────────────────────

class _ProviderInfo {
  final String id;
  final String label;
  final String keyHint;
  final String keyHelper;
  final Map<String, String> models;

  const _ProviderInfo({
    required this.id,
    required this.label,
    required this.keyHint,
    required this.keyHelper,
    required this.models,
  });
}

final _providers = <_ProviderInfo>[
  _ProviderInfo(
    id: 'openrouter',
    label: 'OpenRouter',
    keyHint: 'API-ключ OpenRouter',
    keyHelper: 'Получить на openrouter.ai',
    models: {
      'openrouter/auto': 'Auto Router (Автовыбор модели)',
      'deepseek/deepseek-r1:free': 'DeepSeek R1 (С рассуждением)',
      'deepseek/deepseek-chat': 'DeepSeek V3 (Чат-модель)',
      'openai/gpt-4o': 'GPT-4o',
      'openai/gpt-4o-mini': 'GPT-4o Mini',
      'anthropic/claude-3.5-sonnet': 'Claude 3.5 Sonnet',
      'anthropic/claude-3-haiku': 'Claude 3 Haiku (Быстрый)',
      'meta-llama/llama-3.3-70b-instruct:free': 'Llama 3.3 70B',
      'qwen/qwen-2.5-72b-instruct:free': 'Qwen 2.5 72B',
    },
  ),
  _ProviderInfo(
    id: 'gemini',
    label: 'Google Gemini',
    keyHint: 'Gemini API Key',
    keyHelper: 'Получить на aistudio.google.com',
    models: {
      'gemini-2.5-flash': 'Gemini 2.5 Flash',
      'gemini-2.5-pro': 'Gemini 2.5 Pro',
      'gemini-2.0-flash': 'Gemini 2.0 Flash',
      'gemini-1.5-pro': 'Gemini 1.5 Pro',
      'gemini-1.5-flash': 'Gemini 1.5 Flash',
    },
  ),
];

// ─── State ────────────────────────────────────────────────────────────────────

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyCtrl = TextEditingController();
  final _baseUrlCtrl = TextEditingController(
      text: 'https://vega-chats-production.up.railway.app');

  String _selectedProviderId = 'openrouter';
  String _selectedModel = 'openrouter/auto';
  String _selectedLocale = 'ru_RU';
  bool _developerMode = false;

  String _openrouterKey = '';
  String _geminiKey = '';

  _ProviderInfo get _selectedProvider =>
      _providers.firstWhere((p) => p.id == _selectedProviderId,
          orElse: () => _providers.first);

  bool _isValidModel(String model) =>
      _selectedProvider.models.containsKey(model);

  String get _defaultModel => _selectedProvider.models.keys.first;

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

    _openrouterKey = prefs.getString('api_key') ?? '';
    _geminiKey = prefs.getString('gemini_api_key') ?? '';

    // Resolve provider from saved data
    String resolvedProvider = providerId;
    String resolvedModel = model;
    final oldModel = prefs.getString('model') ?? '';
    if (oldModel.startsWith('gemini:') && resolvedProvider == 'openrouter') {
      resolvedProvider = 'gemini';
      resolvedModel = oldModel.substring(7);
    }

    final providerInfo = _providers.firstWhere((p) => p.id == resolvedProvider,
        orElse: () => _providers.first);

    setState(() {
      _selectedProviderId = providerInfo.id;
      _apiKeyCtrl.text = _selectedProviderId == 'openrouter' ? _openrouterKey : _geminiKey;
      _baseUrlCtrl.text = baseUrl;
      _developerMode =
          baseUrl != 'https://vega-chats-production.up.railway.app';
      _selectedModel = providerInfo.models.containsKey(resolvedModel)
          ? resolvedModel
          : providerInfo.models.keys.first;
      _selectedLocale = _locales.containsKey(locale) ? locale : 'ru_RU';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', _openrouterKey);
    await prefs.setString('gemini_api_key', _geminiKey);
    await prefs.setString('base_url', _baseUrlCtrl.text);
    await prefs.setString('speech_locale', _selectedLocale);
    await prefs.setString('provider', _provider);
    await prefs.setString('model_for_backend', _modelForBackend);
    await prefs.setString('model', _selectedModel);
  }

  void _selectProvider(String id) {
    final provider = _providers.firstWhere((p) => p.id == id);
    setState(() {
      _selectedProviderId = id;
      _apiKeyCtrl.text = id == 'openrouter' ? _openrouterKey : _geminiKey;
      _selectedModel = provider.models.keys.first;
    });
    _saveSettings();
  }

  void _onApiKeyChanged(String val) {
    if (_selectedProviderId == 'openrouter') {
      _openrouterKey = val;
    } else {
      _geminiKey = val;
    }
    _saveSettings();
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  Future<void> _showMemoryDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: VegaTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.psychology_rounded, color: VegaTheme.accent, size: 24),
              SizedBox(width: 8),
              Text('Память ИИ', style: TextStyle(color: VegaTheme.textPrimary, fontWeight: FontWeight.bold)),
            ],
          ),
          content: FutureBuilder<Map<String, dynamic>>(
            future: () async {
              final prefs = await SharedPreferences.getInstance();
              final baseUrl = prefs.getString('base_url') ?? 'https://vega-chats-production.up.railway.app';
              final client = ApiClient(baseUrl: baseUrl);
              return await client.getUserProfile();
            }(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator(color: VegaTheme.accent)),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'Не удалось загрузить профиль памяти: ${snapshot.error}',
                  style: const TextStyle(color: Colors.redAccent),
                );
              }
              final data = snapshot.data ?? {};
              final name = data['user_name'] ?? 'Пользователь';
              final about = data['about_user'] ?? 'Нет данных';
              final style = data['coding_style_preferences'] ?? 'По умолчанию';
              final tech = List<String>.from(data['preferred_technologies'] ?? []);
              final facts = List<String>.from(data['facts'] ?? []);

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('О пользователе:', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(about, style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14)),
                    const SizedBox(height: 12),
                    const Text('Имя:', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(name, style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14)),
                    const SizedBox(height: 12),
                    const Text('Любимые технологии:', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(tech.isEmpty ? 'Не определены' : tech.join(', '), style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14)),
                    const SizedBox(height: 12),
                    const Text('Предпочтения кода:', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(style, style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14)),
                    const SizedBox(height: 12),
                    const Text('Факты из диалогов:', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 4),
                    if (facts.isEmpty)
                      const Text('Пока нет накопленных фактов.', style: TextStyle(color: VegaTheme.textSecondary, fontStyle: FontStyle.italic, fontSize: 13))
                    else
                      ...facts.map((fact) => Padding(
                            padding: const EdgeInsets.only(bottom: 6.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ', style: TextStyle(color: VegaTheme.accent, fontWeight: FontWeight.bold)),
                                Expanded(child: Text(fact, style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 13))),
                              ],
                            ),
                          )),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Закрыть', style: TextStyle(color: VegaTheme.textSecondary)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showClearMemoryConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Сброс памяти ИИ', style: TextStyle(color: VegaTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text(
          'Вы действительно хотите очистить всю накопленную память о вас? ИИ забудет ваше имя, используемые библиотеки и предпочтения стиля кода.',
          style: TextStyle(color: VegaTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена', style: TextStyle(color: VegaTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Очистить', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Очистка памяти на сервере...'),
            ],
          ),
          backgroundColor: VegaTheme.dark,
        ),
      );

      try {
        final prefs = await SharedPreferences.getInstance();
        final baseUrl = prefs.getString('base_url') ?? 'https://vega-chats-production.up.railway.app';
        final client = ApiClient(baseUrl: baseUrl);
        await client.deleteUserProfile();
        
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Память ИИ успешно сброшена!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка очистки памяти: $e'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  // ─── Logo renderer ────────────────────────────────────────────────────────

  Widget _buildProviderLogo(String providerId, {double size = 20}) {
    if (providerId == 'openrouter') {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFFFF8C00), Color(0xFFFF5252)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.hub_rounded, size: size * 0.6, color: Colors.white),
      );
    } else if (providerId == 'gemini') {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF1A73E8), Color(0xFF8AB4F8), Color(0xFFC58AF9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.auto_awesome, size: size * 0.6, color: Colors.white),
      );
    }
    return Icon(Icons.api_rounded, size: size);
  }

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
            _buildCard([
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.business_rounded, color: VegaTheme.accent, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'Выберите провайдера API',
                    style: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedProviderId,
                  isExpanded: true,
                  dropdownColor: VegaTheme.surface,
                  style: const TextStyle(
                      color: VegaTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  items: _providers.map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Row(
                      children: [
                        _buildProviderLogo(p.id),
                        const SizedBox(width: 12),
                        Text(p.label),
                      ],
                    ),
                  )).toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    _selectProvider(v);
                  },
                ),
              ),
              const SizedBox(height: 4),
            ]),
            const SizedBox(height: 24),

            // ── 2. Model selector (depends on provider) ───────────────────
            _buildSectionHeader('Модель'),
            const SizedBox(height: 12),
            _buildCard([
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildProviderLogo(_selectedProviderId, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    'Активная модель (${_selectedProvider.label})',
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

            // ── 3. API Key (Single context field) ─────────────────────────
            _buildSectionHeader('Авторизация'),
            const SizedBox(height: 12),
            _buildCard([
              TextField(
                controller: _apiKeyCtrl,
                style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'API-ключ ${_selectedProvider.label}',
                  labelStyle:
                      const TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: _buildProviderLogo(_selectedProviderId, size: 16),
                  ),
                  border: UnderlineInputBorder(
                      borderSide: BorderSide(color: VegaTheme.border)),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: VegaTheme.border)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: _selectedProviderId == 'openrouter' ? const Color(0xFFFF6B35) : const Color(0xFF4285F4))),
                  helperText: _selectedProvider.keyHelper,
                  helperStyle:
                      const TextStyle(color: VegaTheme.textSecondary, fontSize: 11),
                ),
                obscureText: true,
                onChanged: _onApiKeyChanged,
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

            // ── Память ИИ ────────────────────────────────────────────────
            _buildSectionHeader('Персонализация и память'),
            const SizedBox(height: 12),
            _buildCard([
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.psychology_rounded, color: VegaTheme.accent, size: 24),
                title: const Text('Память ИИ', style: TextStyle(color: VegaTheme.textPrimary, fontSize: 14)),
                subtitle: const Text('Посмотреть, что о вас помнит Vega Chat', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded, color: VegaTheme.textSecondary),
                onTap: _showMemoryDialog,
              ),
              const Divider(color: VegaTheme.border, height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 24),
                title: const Text('Очистить память ИИ', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                subtitle: const Text('Сбросить все накопленные факты профиля', style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12)),
                trailing: const Icon(Icons.chevron_right_rounded, color: VegaTheme.textSecondary),
                onTap: _showClearMemoryConfirmation,
              ),
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
                'Vega Chat v1.2.1 • Сделано с ❤️',
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
    _apiKeyCtrl.dispose();
    _baseUrlCtrl.dispose();
    super.dispose();
  }
}
