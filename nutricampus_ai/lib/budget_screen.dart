import 'package:flutter/material.dart';
import 'api_service.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _successMsg;

  // Configuración de presupuesto
  final _dailyCtrl = TextEditingController();
  final _weeklyCtrl = TextEditingController();
  String _nivelPresupuesto = 'medio';
  String _tipoMenu = 'balanceado';

  // Estadísticas
  Map<String, dynamic>? _stats;

  final _formKey = GlobalKey<FormState>();

  static const _niveles = [
    ('bajo', 'Bajo', 'Menos de \$100/día', Icons.savings_outlined),
    ('medio', 'Medio', '\$100–\$180/día', Icons.account_balance_wallet_outlined),
    ('alto', 'Alto', 'Más de \$180/día', Icons.star_outline_rounded),
  ];

  static const _tiposMenu = [
    ('economico', 'Económico', 'Prioriza opciones de bajo costo'),
    ('balanceado', 'Balanceado', 'Equilibra calidad y precio'),
    ('premium', 'Premium', 'Enfocado en calidad nutricional'),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final results = await Future.wait([
      ApiService.getBudget(),
      ApiService.getBudgetStats(dias: 7),
    ]);

    final budgetRes = results[0];
    final statsRes = results[1];

    if (!mounted) return;
    setState(() {
      _loading = false;

      if (budgetRes['success'] == true && budgetRes['data'] is Map) {
        final data = budgetRes['data'] as Map<String, dynamic>;
        final diario = data['presupuesto_diario'];
        final semanal = data['presupuesto_semanal'];
        if (diario != null) {
          _dailyCtrl.text = (diario as num).toStringAsFixed(0);
        }
        if (semanal != null) {
          _weeklyCtrl.text = (semanal as num).toStringAsFixed(0);
        }
        _nivelPresupuesto = (data['nivel_presupuesto'] as String?) ?? 'medio';
        _tipoMenu = (data['tipo_menu_preferido'] as String?) ?? 'balanceado';
      } else if (budgetRes['errorType'] != ApiErrorType.notFound) {
        _error = budgetRes['error'] as String?;
      }

      if (statsRes['success'] == true && statsRes['data'] is Map) {
        _stats = statsRes['data'] as Map<String, dynamic>;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _successMsg = null;
      _error = null;
    });

    final diario = double.tryParse(_dailyCtrl.text.trim());
    final semanal = double.tryParse(_weeklyCtrl.text.trim());

    final result = await ApiService.updateBudget(
      presupuestoDiario: diario,
      presupuestoSemanal: semanal,
      nivelPresupuesto: _nivelPresupuesto,
      tipoMenuPreferido: _tipoMenu,
    );

    if (!mounted) return;
    setState(() {
      _saving = false;
      if (result['success'] == true) {
        _successMsg = '¡Presupuesto actualizado correctamente!';
        _loadData();
      } else {
        _error = result['error'] as String? ?? 'Error al guardar';
      }
    });
  }

  @override
  void dispose() {
    _dailyCtrl.dispose();
    _weeklyCtrl.dispose();
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
        title: const Text(
          'Presupuesto Alimentario',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: cs.primary),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Estadísticas de la semana
                      if (_stats != null) _StatsCard(stats: _stats!),

                      const SizedBox(height: 16),

                      // Presupuesto diario/semanal
                      _SectionCard(
                        title: 'Montos de Presupuesto',
                        icon: Icons.account_balance_wallet_rounded,
                        color: cs.primary,
                        child: Column(
                          children: [
                            _AmountField(
                              controller: _dailyCtrl,
                              label: 'Presupuesto diario (MXN)',
                              hint: 'Ej. 120',
                              onChanged: (val) {
                                final d = double.tryParse(val);
                                if (d != null) {
                                  _weeklyCtrl.text =
                                      (d * 7).toStringAsFixed(0);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            _AmountField(
                              controller: _weeklyCtrl,
                              label: 'Presupuesto semanal (MXN)',
                              hint: 'Ej. 840',
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Nivel de presupuesto
                      _SectionCard(
                        title: 'Nivel de Presupuesto',
                        icon: Icons.tune_rounded,
                        color: Colors.teal,
                        child: Column(
                          children: _niveles.map((n) {
                            final (value, label, desc, icon) = n;
                            final selected = _nivelPresupuesto == value;
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 8),
                              child: _SelectTile(
                                selected: selected,
                                icon: icon,
                                label: label,
                                description: desc,
                                color: cs.primary,
                                onTap: () => setState(
                                    () => _nivelPresupuesto = value),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Tipo de menú preferido
                      _SectionCard(
                        title: 'Tipo de Menú Preferido',
                        icon: Icons.restaurant_menu_rounded,
                        color: Colors.orange,
                        child: Column(
                          children: _tiposMenu.map((t) {
                            final (value, label, desc) = t;
                            final selected = _tipoMenu == value;
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 8),
                              child: _SelectTile(
                                selected: selected,
                                icon: _tipoIcon(value),
                                label: label,
                                description: desc,
                                color: Colors.orange.shade700,
                                onTap: () =>
                                    setState(() => _tipoMenu = value),
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Mensajes
                      if (_successMsg != null)
                        _Banner(
                            text: _successMsg!,
                            color: Colors.green.shade50,
                            borderColor: Colors.green.shade200,
                            textColor: Colors.green.shade800),
                      if (_error != null)
                        _Banner(
                            text: _error!,
                            color: Colors.red.shade50,
                            borderColor: Colors.red.shade200,
                            textColor: Colors.red.shade800),

                      const SizedBox(height: 8),

                      // Botón guardar
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_rounded),
                          label: Text(_saving
                              ? 'Guardando...'
                              : 'Guardar Presupuesto'),
                          style: FilledButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  IconData _tipoIcon(String tipo) {
    switch (tipo) {
      case 'economico':
        return Icons.savings_rounded;
      case 'premium':
        return Icons.star_rounded;
      default:
        return Icons.balance_rounded;
    }
  }
}

// ── Tarjeta de estadísticas ───────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;

  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final promedio = (stats['costo_promedio_diario'] as num?)?.toDouble() ?? 0;
    final total = (stats['costo_total_periodo'] as num?)?.toDouble() ?? 0;
    final dentro = (stats['dias_dentro_presupuesto'] as num?)?.toInt() ?? 0;
    final fuera = (stats['dias_fuera_presupuesto'] as num?)?.toInt() ?? 0;
    final ahorro = (stats['ahorro_estimado'] as num?)?.toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.primary.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Esta semana',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatItem(
                label: 'Gasto total',
                value: '\$${total.toStringAsFixed(0)} MXN',
                color: Colors.white,
              ),
              _StatItem(
                label: 'Promedio/día',
                value: '\$${promedio.toStringAsFixed(0)} MXN',
                color: Colors.white,
              ),
              _StatItem(
                label: 'Dentro ppto',
                value: '$dentro días',
                color: dentro > fuera ? Colors.greenAccent : Colors.orangeAccent,
              ),
            ],
          ),
          if (ahorro != null && ahorro != 0) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.white24, height: 1),
            const SizedBox(height: 10),
            Text(
              ahorro > 0
                  ? '✅ Ahorro estimado esta semana: \$${ahorro.toStringAsFixed(0)} MXN'
                  : '⚠️ Excediste tu presupuesto por: \$${(-ahorro).toStringAsFixed(0)} MXN',
              style: TextStyle(
                color: ahorro > 0 ? Colors.greenAccent : Colors.orangeAccent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white60, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ],
    );
  }
}

// ── Sección card ──────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
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
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ── Campo de monto ────────────────────────────────────────────────

class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _AmountField({
    required this.controller,
    required this.label,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: '\$  ',
        suffixText: 'MXN',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        filled: true,
        fillColor: const Color(0xFFF8F8F8),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null; // opcional
        final n = double.tryParse(v.trim());
        if (n == null || n < 0) return 'Ingresa un monto válido';
        if (n > 99999) return 'Monto demasiado alto';
        return null;
      },
    );
  }
}

// ── Tile de selección ─────────────────────────────────────────────

class _SelectTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _SelectTile({
    required this.selected,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? color : Colors.grey.shade500, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? color
                          : const Color(0xFF1A1A2E),
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Banner de mensaje ─────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final String text;
  final Color color;
  final Color borderColor;
  final Color textColor;

  const _Banner({
    required this.text,
    required this.color,
    required this.borderColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Text(text,
          style: TextStyle(color: textColor, fontSize: 13)),
    );
  }
}
