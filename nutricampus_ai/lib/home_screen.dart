import 'package:flutter/material.dart';
import 'api_service.dart';
import 'materias_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _nombre;
  Map<String, dynamic>? _perfil;
  List<Materia> _materias = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiService.getMe(),
        ApiService.getPerfil(),
        ApiService.getMaterias(),
      ]);

      final meRes = results[0];
      final perfilRes = results[1];
      final materiasRes = results[2];

      setState(() {
        if (meRes['success'] == true) {
          _nombre = meRes['data']['nombre'];
        }
        if (perfilRes['success'] == true) {
          _perfil = perfilRes['data'];
        }
        if (materiasRes['success'] == true) {
          final list = materiasRes['data'] as List;
          _materias = list.map((m) => Materia.fromJson(m)).toList();
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar datos';
        _loading = false;
      });
    }
  }

  double? get _imc {
    if (_perfil == null) return null;
    final peso = (_perfil!['peso'] as num?)?.toDouble();
    final altura = (_perfil!['altura'] as num?)?.toDouble();
    if (peso == null || altura == null || altura == 0) return null;
    return peso / (altura * altura);
  }

  String _imcCategoria(double imc) {
    if (imc < 18.5) return 'Bajo peso';
    if (imc < 25.0) return 'Normal';
    if (imc < 30.0) return 'Sobrepeso';
    return 'Obesidad';
  }

  Color _imcColor(double imc) {
    if (imc < 18.5) return Colors.blue;
    if (imc < 25.0) return Colors.green;
    if (imc < 30.0) return Colors.orange;
    return Colors.red;
  }

  void _navigateToHorario() {
    if (_materias.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero agrega materias para ver el horario'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pushNamed(context, '/materias');
      return;
    }
    Navigator.pushNamed(context, '/horario', arguments: _materias);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que quieres salir?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await ApiService.clearToken();
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FA),
        body: Center(
          child: CircularProgressIndicator(color: Colors.green),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: RefreshIndicator(
        color: Colors.green,
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    if (_perfil != null) ...[
                      _buildStatsRow(),
                      const SizedBox(height: 28),
                    ],
                    _buildSectionTitle('Secciones'),
                    const SizedBox(height: 16),
                    _buildNavGrid(),
                    if (_materias.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      _buildSectionTitle('Mis materias'),
                      const SizedBox(height: 12),
                      _buildMateriasList(),
                    ],
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
    final hora = TimeOfDay.now().hour;
    String saludo;
    if (hora < 12) {
      saludo = 'Buenos días';
    } else if (hora < 19) {
      saludo = 'Buenas tardes';
    } else {
      saludo = 'Buenas noches';
    }

    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      elevation: 0,
      backgroundColor: Colors.green[700],
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white),
          tooltip: 'Cerrar sesión',
          onPressed: _logout,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green[800]!,
                Colors.green[500]!,
              ],
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
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.eco_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            saludo,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Text(
                            _nombre ?? 'Estudiante',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _perfil == null
                        ? 'Completa tu perfil nutricional para empezar'
                        : 'Tu objetivo: ${_perfil!['objetivo'] ?? '—'}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        title: const Text(
          'NutriCampus AI',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        collapseMode: CollapseMode.parallax,
      ),
    );
  }

  Widget _buildStatsRow() {
    final imc = _imc;
    final calorias = _perfil!['calorias_diarias'];
    final peso = (_perfil!['peso'] as num?)?.toDouble();

    return Row(
      children: [
        if (imc != null)
          Expanded(
            child: _StatCard(
              label: 'IMC',
              value: imc.toStringAsFixed(1),
              subtitle: _imcCategoria(imc),
              icon: Icons.monitor_weight_rounded,
              color: _imcColor(imc),
            ),
          ),
        if (imc != null && (calorias != null || peso != null))
          const SizedBox(width: 12),
        if (calorias != null)
          Expanded(
            child: _StatCard(
              label: 'Calorías',
              value: '$calorias',
              subtitle: 'kcal / día',
              icon: Icons.local_fire_department_rounded,
              color: Colors.orange,
            ),
          ),
        if (calorias == null && peso != null)
          Expanded(
            child: _StatCard(
              label: 'Peso',
              value: '${peso.toStringAsFixed(1)} kg',
              subtitle: _perfil!['nivel_actividad'] ?? '',
              icon: Icons.fitness_center_rounded,
              color: Colors.teal,
            ),
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

  Widget _buildNavGrid() {
    final cards = [
      _NavCard(
        title: 'Perfil Nutricional',
        subtitle: _perfil == null ? 'Configura tus datos' : 'Ver y editar',
        icon: Icons.person_rounded,
        gradient: [const Color(0xFF2E7D32), const Color(0xFF66BB6A)],
        badge: _perfil == null ? '!' : null,
        onTap: () => Navigator.pushNamed(
          context,
          _perfil == null ? '/perfil' : '/perfil_editar',
        ).then((_) => _loadData()),
      ),
      _NavCard(
        title: 'Mis Materias',
        subtitle: _materias.isEmpty
            ? 'Agrega materias'
            : '${_materias.length} materia${_materias.length == 1 ? '' : 's'}',
        icon: Icons.menu_book_rounded,
        gradient: [const Color(0xFF0277BD), const Color(0xFF29B6F6)],
        onTap: () => Navigator.pushNamed(context, '/materias')
            .then((_) => _loadData()),
      ),
      _NavCard(
        title: 'Horario',
        subtitle: _materias.isEmpty ? 'Requiere materias' : 'Ver semana',
        icon: Icons.calendar_month_rounded,
        gradient: [const Color(0xFFE65100), const Color(0xFFFFA726)],
        onTap: _navigateToHorario,
      ),
    ];

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: cards[2],
        ),
      ],
    );
  }

  Widget _buildMateriasList() {
    final preview = _materias.take(3).toList();
    return Column(
      children: [
        ...preview.map((m) => _MateriaPreviewTile(materia: m)),
        if (_materias.length > 3)
          TextButton(
            onPressed: () =>
                Navigator.pushNamed(context, '/materias').then((_) => _loadData()),
            child: Text(
              'Ver todas (${_materias.length})',
              style: const TextStyle(color: Colors.green),
            ),
          ),
      ],
    );
  }
}

// ── Widgets auxiliares ──────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _StatCard({
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
            color: color.withOpacity(0.12),
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
              color: color.withOpacity(0.1),
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
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[500],
                  ),
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

class _NavCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  final String? badge;

  const _NavCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 28),
                ),
                if (badge != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          badge!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withOpacity(0.7),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _MateriaPreviewTile extends StatelessWidget {
  final Materia materia;

  const _MateriaPreviewTile({required this.materia});

  String _diasAbreviados() {
    final dias = <String>[];
    if (materia.lunes) dias.add('L');
    if (materia.martes) dias.add('M');
    if (materia.miercoles) dias.add('X');
    if (materia.jueves) dias.add('J');
    if (materia.viernes) dias.add('V');
    return dias.join(' · ');
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Color _parseColor() {
    try {
      final hex = materia.color.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _parseColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  materia.nombre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_diasAbreviados()} · ${_fmt(materia.horaInicio)} – ${_fmt(materia.horaFin)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (materia.aula != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                materia.aula!,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
