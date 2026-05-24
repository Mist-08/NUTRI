import 'package:flutter/material.dart';
import 'api_service.dart';

class NutritionStatsScreen extends StatefulWidget {
  const NutritionStatsScreen({super.key});

  @override
  State<NutritionStatsScreen> createState() => _NutritionStatsScreenState();
}

class _NutritionStatsScreenState extends State<NutritionStatsScreen> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final res = await ApiService.getNutritionStats();
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _stats = res['data'] as Map<String, dynamic>?;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = res['error'] as String? ?? 'Error al cargar estadísticas';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _historial {
    if (_stats == null) return [];
    final list = _stats!['historial'];
    if (list is! List) return [];
    return list.cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: RefreshIndicator(
        color: Colors.green,
        onRefresh: _loadStats,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.green),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(child: _buildErrorState())
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      _buildSummaryCards(),
                      const SizedBox(height: 28),
                      _buildSectionTitle('Calorías esta semana'),
                      const SizedBox(height: 16),
                      _buildCaloriesChart(),
                      const SizedBox(height: 28),
                      _buildSectionTitle('Historial (últimos 14 días)'),
                      const SizedBox(height: 12),
                      _buildHistoryList(),
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

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.green[700],
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.green[800]!, Colors.green[500]!],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.bar_chart_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Estadísticas',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Seguimiento nutricional',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        collapseMode: CollapseMode.parallax,
      ),
    );
  }

  Widget _buildSummaryCards() {
    final menusGenerados     = (_stats!['menus_generados']     as num?)?.toInt()    ?? 0;
    final comidasConsumidas  = (_stats!['comidas_consumidas']  as num?)?.toInt()    ?? 0;
    final comidasTotales     = (_stats!['comidas_totales']     as num?)?.toInt()    ?? 0;
    final tasaCumplimiento   = (_stats!['tasa_cumplimiento']   as num?)?.toDouble() ?? 0.0;
    final promedioCalorias   = (_stats!['promedio_calorias']   as num?)?.toDouble() ?? 0.0;

    final pct = (tasaCumplimiento * 100).round();
    final Color cumplimientoColor = pct >= 80
        ? Colors.green
        : pct >= 50
            ? Colors.orange
            : Colors.red;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatsCard(
                label: 'Menús generados',
                value: '$menusGenerados',
                subtitle: 'últimos 7 días',
                icon: Icons.restaurant_menu_rounded,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatsCard(
                label: 'Consumidas',
                value: '$comidasConsumidas',
                subtitle: comidasTotales > 0
                    ? 'de $comidasTotales comidas'
                    : 'sin comidas aún',
                icon: Icons.check_circle_outline_rounded,
                color: Colors.teal,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatsCard(
                label: 'Cumplimiento',
                value: '$pct%',
                subtitle: pct >= 80
                    ? 'Excelente'
                    : pct >= 50
                        ? 'Regular'
                        : 'Bajo',
                icon: Icons.pie_chart_outline_rounded,
                color: cumplimientoColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatsCard(
                label: 'Prom. calorías',
                value: promedioCalorias > 0
                    ? '${promedioCalorias.round()}'
                    : '—',
                subtitle: 'kcal / día',
                icon: Icons.local_fire_department_rounded,
                color: Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1A1A2E),
        letterSpacing: 0.1,
      ),
    );
  }

  Widget _buildCaloriesChart() {
    // Tomamos los últimos 7 del historial (que viene desc) y los invertimos
    // para mostrarlos en orden cronológico (izq → der = más antiguo → más reciente).
    final raw = _historial.take(7).toList();
    final chartData = raw.reversed.toList();

    if (chartData.isEmpty) {
      return _emptyChartPlaceholder();
    }

    const double maxBarHeight = 90.0;

    final double maxCal = chartData
        .map((m) => (m['calorias_total'] as num?)?.toDouble() ?? 0.0)
        .fold(0.0, (a, b) => a > b ? a : b);
    final double scale = maxCal > 0 ? maxBarHeight / maxCal : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Barras
          SizedBox(
            height: maxBarHeight + 22, // 22 extra para la etiqueta de kcal
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: chartData.map((m) {
                final cal = (m['calorias_total'] as num?)?.toDouble() ?? 0.0;
                final consumed = m['consumido'] as bool? ?? false;
                final tipoDia = m['tipo_dia'] as String? ?? 'normal';
                final barHeight = (cal * scale).clamp(4.0, maxBarHeight);

                final Color barColor;
                if (!consumed) {
                  barColor = Colors.grey[300]!;
                } else if (tipoDia == 'examen') {
                  barColor = Colors.red[400]!;
                } else if (tipoDia == 'entrega') {
                  barColor = Colors.orange[400]!;
                } else if (tipoDia == 'alta_carga') {
                  barColor = Colors.blue[400]!;
                } else {
                  barColor = Colors.green[400]!;
                }

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (cal > 0)
                          Center(
                            child: Text(
                              '${cal.round()}',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const SizedBox(height: 2),
                        Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 14),
          // Etiquetas de día
          Row(
            children: chartData.map((m) {
              final fechaStr = m['fecha'] as String? ?? '';
              final dayLabel = _dayLabel(fechaStr);
              return Expanded(
                child: Center(
                  child: Text(
                    dayLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          // Leyenda
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: const [
              _LegendDot(color: Color(0xFF66BB6A), label: 'Consumido'),
              _LegendDot(color: Color(0xFFEF5350), label: 'Examen'),
              _LegendDot(color: Color(0xFFFFA726), label: 'Entrega'),
              _LegendDot(color: Color(0xFFBDBDBD), label: 'No consumido'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyChartPlaceholder() {
    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_rounded, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 8),
          Text(
            'Aún no hay datos de calorías',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    if (_historial.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(Icons.history_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(
              'Sin menús en los últimos 14 días',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Ve a Recomendación para generar tu primer menú',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: _historial.map((m) => _HistoryTile(menu: m)).toList(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text(
              'No pudimos cargar las estadísticas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadStats,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dayLabel(String fechaStr) {
    if (fechaStr.length < 10) return '?';
    try {
      final dt = DateTime.parse(fechaStr);
      const days = ['Do', 'Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sa'];
      return days[dt.weekday % 7];
    } catch (_) {
      return '?';
    }
  }
}

// ── Widgets auxiliares ──────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _StatsCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> menu;

  const _HistoryTile({required this.menu});

  static const _tipoDiaLabel = {
    'examen':      'Día de examen',
    'entrega':     'Entrega / tarea',
    'alta_carga':  'Alta carga',
    'descanso':    'Descanso',
    'normal':      'Día normal',
  };

  static const _tipoDiaColor = {
    'examen':      Color(0xFFE53935),
    'entrega':     Color(0xFFFB8C00),
    'alta_carga':  Color(0xFF1E88E5),
    'descanso':    Color(0xFF00897B),
    'normal':      Color(0xFF43A047),
  };

  String _formatFecha(String fechaStr) {
    if (fechaStr.length < 10) return fechaStr;
    try {
      final dt = DateTime.parse(fechaStr);
      const meses = [
        '', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun',
        'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic',
      ];
      const dias = ['Do', 'Lu', 'Ma', 'Mi', 'Ju', 'Vi', 'Sa'];
      return '${dias[dt.weekday % 7]} ${dt.day} ${meses[dt.month]}';
    } catch (_) {
      return fechaStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipoDia  = menu['tipo_dia']  as String? ?? 'normal';
    final consumido = menu['consumido'] as bool?   ?? false;
    final cal       = (menu['calorias_total']    as num?)?.toDouble() ?? 0.0;
    final fechaStr  = menu['fecha']    as String? ?? '';
    final mensaje   = menu['mensaje']  as String? ?? '';

    final color = _tipoDiaColor[tipoDia] ?? const Color(0xFF43A047);
    final label = _tipoDiaLabel[tipoDia] ?? tipoDia;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (consumido ? color : Colors.grey)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            consumido
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: consumido ? color : Colors.grey[400],
            size: 24,
          ),
        ),
        title: Text(
          _formatFecha(fechaStr),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: Color(0xFF1A1A2E),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (cal > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${cal.round()} kcal',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
            if (mensaje.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                mensaje,
                style:
                    TextStyle(fontSize: 11, color: Colors.grey[500]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: consumido
            ? Icon(Icons.check_rounded, color: color, size: 18)
            : Text(
                'Sin\nconsumir',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[400],
                  height: 1.3,
                ),
              ),
      ),
    );
  }
}
