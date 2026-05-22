import 'package:flutter/material.dart';
import 'api_service.dart';

// ── Paleta (consistente con nutritional_profile_screen) ───────────
const _primaryGreen = Color(0xFF2E7D32);
const _softGreen    = Color(0xFFE8F5E9);
const _bgColor      = Color(0xFFF8FAF9);
const _darkText     = Color(0xFF1A1A2E);

// ── Configuración visual por tipo de día ─────────────────────────

const _tipoDiaConfig = {
  'examen': {
    'emoji':    '🧪',
    'label':    'Día de Examen',
    'color':    Color(0xFFB71C1C),
    'gradient': [Color(0xFFB71C1C), Color(0xFFE53935)],
    'bg':       Color(0xFFFFEBEE),
  },
  'entrega': {
    'emoji':    '📋',
    'label':    'Día de Entrega',
    'color':    Color(0xFFE65100),
    'gradient': [Color(0xFFE65100), Color(0xFFFB8C00)],
    'bg':       Color(0xFFFFF3E0),
  },
  'alta_carga': {
    'emoji':    '⚡',
    'label':    'Alta Carga Académica',
    'color':    Color(0xFF1565C0),
    'gradient': [Color(0xFF1565C0), Color(0xFF1E88E5)],
    'bg':       Color(0xFFE3F2FD),
  },
  'descanso': {
    'emoji':    '🌿',
    'label':    'Día de Descanso',
    'color':    Color(0xFF2E7D32),
    'gradient': [Color(0xFF2E7D32), Color(0xFF66BB6A)],
    'bg':       Color(0xFFE8F5E9),
  },
  'normal': {
    'emoji':    '📚',
    'label':    'Día Académico',
    'color':    Color(0xFF2E7D32),
    'gradient': [Color(0xFF2E7D32), Color(0xFF43A047)],
    'bg':       Color(0xFFE8F5E9),
  },
};

Map<String, dynamic> _configForTipo(String? tipo) =>
    _tipoDiaConfig[tipo ?? 'normal'] as Map<String, dynamic>? ??
    _tipoDiaConfig['normal'] as Map<String, dynamic>;

// ── Íconos y colores por comida ───────────────────────────────────

const _mealMeta = {
  'desayuno': {'label': 'Desayuno', 'icon': Icons.wb_sunny_rounded,       'color': Color(0xFFFF8F00)},
  'almuerzo': {'label': 'Almuerzo', 'icon': Icons.restaurant_rounded,      'color': Color(0xFF1565C0)},
  'cena':     {'label': 'Cena',     'icon': Icons.nightlight_round,        'color': Color(0xFF6A1B9A)},
  'snacks':   {'label': 'Snacks',   'icon': Icons.emoji_food_beverage_rounded, 'color': Color(0xFF2E7D32)},
};

// ══════════════════════════════════════════════════════════════════
//  PANTALLA PRINCIPAL
// ══════════════════════════════════════════════════════════════════

class RecommendationScreen extends StatefulWidget {
  const RecommendationScreen({super.key});

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  Map<String, dynamic>? _menu;
  bool _isLoading    = true;
  bool _isGenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  // ── Carga / generación ─────────────────────────────────────────

  Future<void> _loadMenu({bool force = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = force
        ? await ApiService.generateMenu()
        : await ApiService.getMenuHoy();

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _menu      = result['data'] as Map<String, dynamic>;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error     = result['error'] as String? ?? 'No se pudo cargar la recomendación';
        _isLoading = false;
        _menu      = null;
      });
    }
  }

  Future<void> _toggleConsumed() async {
    if (_menu == null) return;
    final id       = _menu!['id_menu'] as int;
    final consumed = !(_menu!['consumido'] as bool? ?? false);

    setState(() => _isGenerating = true);
    final result = await ApiService.markConsumed(id, consumido: consumed);
    if (!mounted) return;
    setState(() => _isGenerating = false);

    if (result['success'] == true) {
      setState(() => _menu = result['data'] as Map<String, dynamic>);
    } else {
      _showSnack(result['error'] as String? ?? 'Error al actualizar', isError: true);
    }
  }

  Future<void> _regenerate() async {
    setState(() => _isGenerating = true);
    final result = await ApiService.generateMenu();
    if (!mounted) return;
    setState(() => _isGenerating = false);

    if (result['success'] == true) {
      setState(() => _menu = result['data'] as Map<String, dynamic>);
      _showSnack('Menú regenerado exitosamente');
    } else {
      _showSnack(result['error'] as String? ?? 'Error al regenerar', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : _primaryGreen,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _primaryGreen)),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    final tipo      = _menu!['tipo_dia'] as String? ?? 'normal';
    final cfg       = _configForTipo(tipo);
    final consumido = _menu!['consumido'] as bool? ?? false;

    return Scaffold(
      backgroundColor: _bgColor,
      body: RefreshIndicator(
        color: _primaryGreen,
        onRefresh: () => _loadMenu(),
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(cfg, tipo, consumido),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    if (_isGenerating)
                      _buildGeneratingBanner(),
                    _buildContextBanner(cfg, tipo),
                    const SizedBox(height: 12),
                    if (_menu!['alertas'] != null)
                      _buildAlertsList(_menu!['alertas'] as List),
                    if (_menu!['mensaje'] != null)
                      _buildMessageCard(_menu!['mensaje'] as String),
                    const SizedBox(height: 16),
                    _buildMacrosSummary(),
                    const SizedBox(height: 20),
                    _buildMealSection('desayuno'),
                    _buildMealSection('almuerzo'),
                    _buildMealSection('cena'),
                    _buildMealSection('snacks'),
                    const SizedBox(height: 16),
                    _buildActions(consumido),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────

  Widget _buildSliverAppBar(Map<String, dynamic> cfg, String tipo, bool consumido) {
    final contexto  = _menu!['contexto'] as Map<String, dynamic>?;
    final numClases = contexto?['num_clases'] as int? ?? 0;
    final eventos   = (contexto?['eventos'] as List?)?.cast<String>() ?? [];
    final gradient  = cfg['gradient'] as List<Color>;
    final emoji     = cfg['emoji'] as String;
    final label     = cfg['label'] as String;

    return SliverAppBar(
      expandedHeight: 200,
      pinned: true,
      elevation: 0,
      backgroundColor: gradient.first,
      foregroundColor: Colors.white,
      title: const Text(
        'Mi Menú de Hoy',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.bar_chart_rounded, color: Colors.white),
          tooltip: 'Estadísticas',
          onPressed: () =>
              Navigator.pushNamed(context, '/estadisticas_nutricion'),
        ),
        if (consumido)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                label: Text('Consumido', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.white24,
                padding: EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 32)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              numClases > 0
                                  ? '$numClases clase${numClases == 1 ? '' : 's'} hoy'
                                  : 'Sin clases programadas',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (eventos.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: eventos.take(2).map((e) => Chip(
                        label: Text(e, style: const TextStyle(fontSize: 10, color: Colors.white)),
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Banners y cards ────────────────────────────────────────────

  Widget _buildGeneratingBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _softGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(color: _primaryGreen, strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text('Actualizando menú...', style: TextStyle(fontSize: 13, color: _primaryGreen, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildContextBanner(Map<String, dynamic> cfg, String tipo) {
    final bg     = cfg['bg']    as Color;
    final color  = cfg['color'] as Color;
    final contexto = _menu!['contexto'] as Map<String, dynamic>?;
    final horas    = contexto?['horas_clase'] as double? ?? 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(Icons.school_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contexto académico',
                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  horas > 0
                      ? '${horas.toStringAsFixed(1)} h de clases · ${_menu!['calorias_objetivo']} kcal objetivo'
                      : '${_menu!['calorias_objetivo']} kcal objetivo para hoy',
                  style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.9), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsList(List alertas) {
    if (alertas.isEmpty) return const SizedBox.shrink();
    return Column(
      children: alertas.cast<String>().map((alerta) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.tips_and_updates_rounded, color: Colors.amber[800], size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(alerta, style: TextStyle(fontSize: 12.5, color: Colors.amber[900], fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildMessageCard(String mensaje) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.psychology_rounded, color: _primaryGreen, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacrosSummary() {
    final cal   = _menu!['calorias_total']    as int?    ?? 0;
    final prot  = _menu!['proteinas_total']   as double? ?? 0;
    final gras  = _menu!['grasas_total']      as double? ?? 0;
    final carbs = _menu!['carbohidratos_total'] as double? ?? 0;

    return Row(
      children: [
        _MacroChip(label: 'Calorías', value: '$cal kcal',          color: Colors.orange),
        const SizedBox(width: 8),
        _MacroChip(label: 'Proteína', value: '${prot.toStringAsFixed(0)}g', color: Colors.red[700]!),
        const SizedBox(width: 8),
        _MacroChip(label: 'Grasas',   value: '${gras.toStringAsFixed(0)}g', color: Colors.purple[700]!),
        const SizedBox(width: 8),
        _MacroChip(label: 'Carbos',   value: '${carbs.toStringAsFixed(0)}g', color: _primaryGreen),
      ],
    );
  }

  // ── Secciones de comida ────────────────────────────────────────

  Widget _buildMealSection(String key) {
    final meta   = _mealMeta[key]!;
    final label  = meta['label']  as String;
    final icon   = meta['icon']   as IconData;
    final color  = meta['color']  as Color;
    final items  = (_menu![key] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (items.isEmpty) return const SizedBox.shrink();

    final totalCal = items.fold<int>(0, (sum, i) => sum + (i['calorias'] as int? ?? 0));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        children: [
          // Header de la comida
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$totalCal kcal',
                    style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.grey.shade100, height: 1),
          // Lista de alimentos
          ...items.asMap().entries.map((entry) {
            final isLast = entry.key == items.length - 1;
            return _FoodItemTile(food: entry.value, isLast: isLast, accentColor: color);
          }),
        ],
      ),
    );
  }

  // ── Botones de acción ──────────────────────────────────────────

  Widget _buildActions(bool consumido) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isGenerating ? null : _toggleConsumed,
            style: ElevatedButton.styleFrom(
              backgroundColor: consumido ? Colors.green[700] : _primaryGreen,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: Icon(consumido ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded),
            label: Text(
              consumido ? 'Menú consumido ✓' : 'Marcar como consumido',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _isGenerating ? null : _regenerate,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Regenerar menú'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
        ),
      ],
    );
  }

  // ── Error state ────────────────────────────────────────────────

  Widget _buildErrorState() {
    final isNoProfile = _error != null &&
        _error!.toLowerCase().contains('perfil');

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text('Mi Menú de Hoy'),
        backgroundColor: _primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isNoProfile ? Icons.person_outline_rounded : Icons.restaurant_outlined,
                size: 72,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 20),
              Text(
                isNoProfile
                    ? 'Perfil incompleto'
                    : 'No se pudo cargar el menú',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              if (isNoProfile)
                ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, '/perfil'),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Completar Perfil'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _loadMenu(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  WIDGETS AUXILIARES
// ══════════════════════════════════════════════════════════════════

class _MacroChip extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;

  const _MacroChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

class _FoodItemTile extends StatefulWidget {
  final Map<String, dynamic> food;
  final bool isLast;
  final Color accentColor;

  const _FoodItemTile({required this.food, required this.isLast, required this.accentColor});

  @override
  State<_FoodItemTile> createState() => _FoodItemTileState();
}

class _FoodItemTileState extends State<_FoodItemTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final food        = widget.food;
    final nombre      = food['nombre']       as String? ?? '';
    final porcion     = food['porcion']      as String? ?? '';
    final calorias    = food['calorias']     as int?    ?? 0;
    final proteinas   = food['proteinas']    as double? ?? 0;
    final carbos      = food['carbohidratos'] as double? ?? 0;
    final grasas      = food['grasas']       as double? ?? 0;
    final beneficios  = food['beneficios']   as String?;
    final advertencias = food['advertencias'] as String?;
    final descripcion = food['descripcion']  as String?;

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: widget.isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(18))
              : BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4, height: 40,
                      decoration: BoxDecoration(
                        color: widget.accentColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _darkText)),
                          const SizedBox(height: 2),
                          Text(porcion, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$calorias kcal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.accentColor)),
                        const SizedBox(height: 2),
                        Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: Colors.grey[400], size: 18),
                      ],
                    ),
                  ],
                ),
                // Macros siempre visibles como fila compacta
                const SizedBox(height: 6),
                Row(
                  children: [
                    const SizedBox(width: 16),
                    _MiniMacro('P', proteinas,  Colors.red[700]!),
                    const SizedBox(width: 8),
                    _MiniMacro('C', carbos,     _primaryGreen),
                    const SizedBox(width: 8),
                    _MiniMacro('G', grasas,     Colors.purple[700]!),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Expandible: descripción, beneficios, advertencias
        if (_expanded) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: widget.accentColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (descripcion != null) ...[
                  Text(descripcion, style: TextStyle(fontSize: 12.5, color: Colors.grey[700], height: 1.4)),
                  const SizedBox(height: 6),
                ],
                if (beneficios != null)
                  _InfoRow(Icons.star_rounded, beneficios, Colors.green[700]!),
                if (advertencias != null)
                  _InfoRow(Icons.warning_amber_rounded, advertencias, Colors.orange[800]!),
              ],
            ),
          ),
        ],
        if (!widget.isLast)
          Divider(color: Colors.grey.shade100, height: 1, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _MiniMacro extends StatelessWidget {
  final String label;
  final double value;
  final Color  color;

  const _MiniMacro(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: '$label: ', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          TextSpan(
            text: '${value.toStringAsFixed(0)}g',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  final Color    color;

  const _InfoRow(this.icon, this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }
}
