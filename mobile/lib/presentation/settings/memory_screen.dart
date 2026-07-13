import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../core/api_client.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({super.key});

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  bool _isLoading = true;
  bool _isUpdating = false;
  
  Map<String, dynamic> _profile = {};
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('base_url') ?? 'https://vega-chats-production.up.railway.app';
      final client = ApiClient(baseUrl: baseUrl);
      final prof = await client.getUserProfile();
      setState(() {
        _profile = prof;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки памяти: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _updateBioManual() async {
    final text = _bioController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isUpdating = true);
    FocusScope.of(context).unfocus();

    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('base_url') ?? 'https://vega-chats-production.up.railway.app';
      final client = ApiClient(baseUrl: baseUrl);
      
      final updated = await client.updateProfileManual(text);
      
      setState(() {
        _profile = updated;
        _isUpdating = false;
        _bioController.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Профиль памяти успешно обновлен!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => _isUpdating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка обновления памяти: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _clearMemory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VegaTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Сброс памяти ИИ', style: TextStyle(color: VegaTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: const Text(
          'Вы действительно хотите очистить всю накопленную память о вас? ИИ забудет ваше имя, увлечения и все факты.',
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

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final prefs = await SharedPreferences.getInstance();
        final baseUrl = prefs.getString('base_url') ?? 'https://vega-chats-production.up.railway.app';
        final client = ApiClient(baseUrl: baseUrl);
        final emptyProfile = await client.deleteUserProfile();
        setState(() {
          _profile = emptyProfile;
          _isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Память ИИ полностью сброшена'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка сброса: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final facts = List<String>.from(_profile['facts'] ?? []);
    final userName = _profile['user_name'] ?? 'Пользователь';
    final aboutUser = _profile['about_user'] ?? 'Обычный пользователь Vega Chat';

    return Scaffold(
      backgroundColor: VegaTheme.dark,
      appBar: AppBar(
        backgroundColor: VegaTheme.dark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: VegaTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Память ИИ',
          style: TextStyle(
            color: VegaTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: VegaTheme.accent))
          : Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ── User Header Card ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: VegaTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: VegaTheme.border, width: 0.5),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [VegaTheme.accent, VegaTheme.accentBlue],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userName,
                                  style: const TextStyle(
                                    color: VegaTheme.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  aboutUser,
                                  style: const TextStyle(
                                    color: VegaTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Manual Input Section ──────────────────────────
                    const Text(
                      'Рассказать о себе',
                      style: TextStyle(color: VegaTheme.accent, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: VegaTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: VegaTheme.border, width: 0.5),
                      ),
                      child: TextField(
                        controller: _bioController,
                        maxLines: 4,
                        style: const TextStyle(color: VegaTheme.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Пример: Меня зовут Иван, я увлекаюсь астрономией, люблю играть на гитаре и пью черный кофе без сахара...',
                          hintStyle: TextStyle(color: VegaTheme.textSecondary, fontSize: 13),
                          contentPadding: EdgeInsets.all(16),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _bioController.text.trim().isEmpty || _isUpdating ? null : _updateBioManual,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: VegaTheme.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: VegaTheme.border,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _isUpdating
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Обновить память', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 28),

                    // ── AI Profile Facts ──────────────────────────────
                    const Text(
                      'Интересные факты о вас',
                      style: TextStyle(color: VegaTheme.accentBlue, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (facts.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: VegaTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: VegaTheme.border, width: 0.5),
                        ),
                        child: const Center(
                          child: Text(
                            'ИИ еще ничего не запомнил о вас. Начните общаться, либо напишите о себе выше!',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: VegaTheme.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: facts.length,
                        itemBuilder: (context, idx) {
                          final fact = facts[idx];
                          // Try parsing as key-value if model structured it with colon (e.g. "Хобби: программирование")
                          final colonIdx = fact.indexOf(':');
                          final hasCategory = colonIdx != -1 && colonIdx < 30; // threshold for category word length
                          
                          final category = hasCategory ? fact.substring(0, colonIdx).trim() : 'Интерес / Факт';
                          final details = hasCategory ? fact.substring(colonIdx + 1).trim() : fact;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: VegaTheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: VegaTheme.border, width: 0.5),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  category,
                                  style: const TextStyle(
                                    color: VegaTheme.accent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  details,
                                  style: const TextStyle(
                                    color: VegaTheme.textPrimary,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    
                    const SizedBox(height: 32),

                    // ── Danger Zone ───────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.3), width: 0.8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Опасная зона',
                            style: TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Сброс сотрет все накопленные данные. Это действие необратимо.',
                            style: TextStyle(color: VegaTheme.textSecondary, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _clearMemory,
                            icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                            label: const Text('Сбросить всю память ИИ'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ],
            ),
    );
  }
}
