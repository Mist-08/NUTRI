import 'package:flutter/material.dart';
import 'api_service.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({super.key});

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<String> _suggestions = [];
  bool _loadingSuggestions = true;
  bool _sending = false;
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadSuggestions();
  }

  void _addWelcomeMessage() {
    _messages.add(const _ChatMessage(
      text:
          '¡Hola! Soy el **Asistente NutriCampus**. Puedo ayudarte con tu menú del día, '
          'presupuesto alimentario, snacks para estudiar y consejos de nutrición. '
          '¿En qué te puedo ayudar?',
      isUser: false,
    ));
  }

  /// Carga el historial guardado del usuario. Si no hay nada, muestra el saludo.
  Future<void> _loadHistory() async {
    final result = await ApiService.getChatHistory();
    if (!mounted) return;
    setState(() {
      _loadingHistory = false;
      _messages.clear();
      final data = result['data'];
      final lista = (data is Map) ? data['mensajes'] : null;
      if (lista is List && lista.isNotEmpty) {
        for (final m in lista) {
          if (m is Map) {
            _messages.add(_ChatMessage(
              text: (m['texto'] ?? '').toString(),
              isUser: m['rol'] == 'user',
            ));
          }
        }
      } else {
        _addWelcomeMessage();
      }
    });
    _scrollToBottom();
  }

  /// Borra la conversación tras confirmar con el usuario.
  Future<void> _clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar conversación'),
        content: const Text(
          '¿Seguro que quieres borrar toda la conversación? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final result = await ApiService.clearChatHistory();
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _messages.clear();
        _addWelcomeMessage();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo limpiar la conversación')),
      );
    }
  }

  Future<void> _loadSuggestions() async {
    final result = await ApiService.getChatSuggestions();
    if (!mounted) return;
    setState(() {
      _loadingSuggestions = false;
      if (result['success'] == true && result['data'] is Map) {
        final data = result['data'] as Map;
        final list = data['suggestions'];
        if (list is List) {
          _suggestions = list.cast<String>();
        }
      }
      if (_suggestions.isEmpty) {
        _suggestions = [
          '¿Qué debo comer hoy?',
          '¿Qué puedo comer con poco presupuesto?',
          'Dame snacks para estudiar',
          '¿Cuántas calorías he consumido?',
        ];
      }
    });
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    _controller.clear();
    setState(() {
      _sending = true;
      _messages.add(_ChatMessage(text: trimmed, isUser: true));
    });
    _scrollToBottom();

    final result = await ApiService.sendChatMessage(trimmed);

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result['success'] == true && result['data'] is Map) {
        final data = result['data'] as Map<String, dynamic>;
        final reply = data['reply'] as String? ?? 'Sin respuesta';
        final contextCard = data['context_card'];
        final relatedMenu = data['related_menu'];

        _messages.add(_ChatMessage(
          text: reply,
          isUser: false,
          contextCard: contextCard is Map<String, dynamic> ? contextCard : null,
          relatedMenu: relatedMenu is Map<String, dynamic> ? relatedMenu : null,
        ));

        // Actualizar sugerencias si vienen en la respuesta
        final newSuggestions = data['suggestions'];
        if (newSuggestions is List && newSuggestions.isNotEmpty) {
          _suggestions = newSuggestions.cast<String>();
        }
      } else {
        _messages.add(_ChatMessage(
          text: result['error'] as String? ??
              'Ocurrió un error. Intenta de nuevo.',
          isUser: false,
          isError: true,
        ));
      }
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: cs.primary.withOpacity(0.15),
              child: Icon(Icons.smart_toy_rounded, color: cs.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Asistente NutriCampus',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  'En línea',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Color(0xFF6B7280)),
            tooltip: 'Limpiar conversación',
            onPressed: _messages.isEmpty ? null : _clearHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Mensajes
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (_sending && i == _messages.length) {
                  return _TypingIndicator(color: cs.primary);
                }
                return _MessageBubble(message: _messages[i]);
              },
            ),
          ),

          // Chips de sugerencias
          if (_suggestions.isNotEmpty && !_loadingSuggestions)
            _SuggestionsBar(
              suggestions: _suggestions,
              onTap: _sendMessage,
            ),

          // Campo de texto
          _InputBar(
            controller: _controller,
            sending: _sending,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

// ── Modelo de mensaje ─────────────────────────────────────────────

class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isError;
  final Map<String, dynamic>? contextCard;
  final Map<String, dynamic>? relatedMenu;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    this.contextCard,
    this.relatedMenu,
  });
}

// ── Burbuja de mensaje ────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        bottom: 4,
        left: isUser ? 60 : 0,
        right: isUser ? 0 : 60,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Avatar (solo bot)
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: CircleAvatar(
                radius: 12,
                backgroundColor: cs.primary.withOpacity(0.15),
                child:
                    Icon(Icons.smart_toy_rounded, color: cs.primary, size: 14),
              ),
            ),

          // Burbuja
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: message.isError
                  ? Colors.red.shade50
                  : isUser
                      ? cs.primary
                      : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _MarkdownText(
              text: message.text,
              color: message.isError
                  ? Colors.red.shade700
                  : isUser
                      ? Colors.white
                      : const Color(0xFF1A1A2E),
            ),
          ),

          // Tarjeta contextual (menú del día)
          if (message.relatedMenu != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _MenuCard(menu: message.relatedMenu!),
            ),

          // Tarjeta contextual (presupuesto / examen)
          if (message.contextCard != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _ContextCard(card: message.contextCard!),
            ),
        ],
      ),
    );
  }
}

// ── Texto con bold básico (**)  ───────────────────────────────────

class _MarkdownText extends StatelessWidget {
  final String text;
  final Color color;

  const _MarkdownText({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    // Divide en segmentos normales y **bold**
    final parts = <TextSpan>[];
    final regex = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;

    for (final m in regex.allMatches(text)) {
      if (m.start > last) {
        parts.add(TextSpan(
          text: text.substring(last, m.start),
          style: TextStyle(color: color, fontSize: 13.5, height: 1.45),
        ));
      }
      parts.add(TextSpan(
        text: m.group(1),
        style: TextStyle(
          color: color,
          fontSize: 13.5,
          fontWeight: FontWeight.bold,
          height: 1.45,
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      parts.add(TextSpan(
        text: text.substring(last),
        style: TextStyle(color: color, fontSize: 13.5, height: 1.45),
      ));
    }

    return RichText(text: TextSpan(children: parts));
  }
}

// ── Tarjeta de menú ───────────────────────────────────────────────

class _MenuCard extends StatelessWidget {
  final Map<String, dynamic> menu;

  const _MenuCard({required this.menu});

  @override
  Widget build(BuildContext context) {
    final tipoDia = menu['tipo_dia'] as String? ?? 'normal';
    final calTotal = menu['calorias_total'];
    final costoTotal = menu['costo_total_estimado'];
    final dentroPpto = menu['dentro_presupuesto'];

    final (color, icon, label) = _tipoDiaStyle(tipoDia);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Text(
                'Menú de hoy — $label',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (calTotal != null)
            Text(
              '🔥 ${calTotal.toString()} kcal',
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF555555)),
            ),
          if (costoTotal != null)
            Text(
              '💰 \$${(costoTotal as num).toStringAsFixed(0)} MXN estimado',
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF555555)),
            ),
          if (dentroPpto == true)
            const Text('✅ Dentro de tu presupuesto',
                style: TextStyle(fontSize: 12, color: Colors.green)),
          if (dentroPpto == false)
            const Text('⚠️ Supera tu presupuesto',
                style: TextStyle(fontSize: 12, color: Colors.orange)),
        ],
      ),
    );
  }

  (Color, String, String) _tipoDiaStyle(String tipo) {
    switch (tipo) {
      case 'examen':
        return (Colors.red, '🧪', 'Día de examen');
      case 'entrega':
        return (Colors.orange, '📋', 'Día de entrega');
      case 'alta_carga':
        return (Colors.blue, '⚡', 'Alta carga');
      case 'descanso':
        return (Colors.teal, '🌿', 'Descanso');
      default:
        return (Colors.green, '📚', 'Día normal');
    }
  }
}

// ── Tarjeta contextual (presupuesto / examen) ─────────────────────

class _ContextCard extends StatelessWidget {
  final Map<String, dynamic> card;

  const _ContextCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final tipo = card['tipo'] as String? ?? '';

    if (tipo == 'presupuesto') {
      return _BudgetContextCard(card: card);
    } else if (tipo == 'examen') {
      return _ExamContextCard(card: card);
    }
    return const SizedBox.shrink();
  }
}

class _BudgetContextCard extends StatelessWidget {
  final Map<String, dynamic> card;

  const _BudgetContextCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final pptoDiario = (card['presupuesto_diario'] as num?)?.toDouble();
    final costoSemana = (card['costo_semana'] as num?)?.toDouble();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💰 Resumen de presupuesto',
              style:
                  TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          if (pptoDiario != null)
            Text('Presupuesto diario: \$${pptoDiario.toStringAsFixed(0)} MXN',
                style: const TextStyle(fontSize: 12)),
          if (costoSemana != null && costoSemana > 0)
            Text('Gasto esta semana: \$${costoSemana.toStringAsFixed(0)} MXN',
                style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _ExamContextCard extends StatelessWidget {
  final Map<String, dynamic> card;

  const _ExamContextCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final esHoy = card['hoy'] == true;
    final proximo = card['proximo_examen'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            esHoy ? '🧪 ¡Examen hoy!' : '🧪 Próximo examen',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.red),
          ),
          if (proximo != null)
            Text(
              '${proximo['descripcion']} — ${proximo['fecha']}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}

// ── Typing indicator ──────────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final Color color;

  const _TypingIndicator({required this.color});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4, right: 60),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: widget.color.withOpacity(0.15),
            child: Icon(Icons.smart_toy_rounded,
                color: widget.color, size: 14),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: FadeTransition(
              opacity: _anim,
              child: Row(
                children: [
                  _Dot(color: widget.color, delay: 0),
                  const SizedBox(width: 4),
                  _Dot(color: widget.color, delay: 200),
                  const SizedBox(width: 4),
                  _Dot(color: widget.color, delay: 400),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final int delay;

  const _Dot({required this.color, required this.delay});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ── Barra de sugerencias ──────────────────────────────────────────

class _SuggestionsBar extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTap;

  const _SuggestionsBar(
      {required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 44,
      color: Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (ctx, i) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => ActionChip(
          label: Text(
            suggestions[i],
            style: TextStyle(fontSize: 12, color: cs.primary),
          ),
          backgroundColor: cs.primary.withOpacity(0.08),
          side: BorderSide(color: cs.primary.withOpacity(0.3)),
          onPressed: () => onTap(suggestions[i]),
          padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        ),
      ),
    );
  }
}

// ── Barra de entrada ──────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final ValueChanged<String> onSend;

  const _InputBar(
      {required this.controller,
      required this.sending,
      required this.onSend});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !sending,
              textCapitalization: TextCapitalization.sentences,
              maxLines: null,
              decoration: InputDecoration(
                hintText: 'Escribe tu pregunta...',
                hintStyle:
                    const TextStyle(color: Colors.grey, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              onSubmitted: onSend,
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: sending
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: cs.primary,
                      ),
                    ),
                  )
                : IconButton(
                    icon:
                        Icon(Icons.send_rounded, color: cs.primary),
                    onPressed: () => onSend(controller.text),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.primary.withOpacity(0.1),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
