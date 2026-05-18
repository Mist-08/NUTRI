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

  bool _loading = true;          // primera carga
  bool _refreshing = false;       // pull-to-refresh
  String? _criticalError;         // error que impide mostrar la UI
  String? _warning;               // aviso secundario (algunas llamadas fallaron)

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// Carga todos los datos en paralelo.
  /// Si el token expiró (401), se desloguea automáticamente.
  Future<void> _loadData({bool isRefresh = false}) async {
    setState(() {
      if (isRefresh) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _criticalError = null;
      _warning = null;
    });

    final results = await Future.wait([
      ApiService.getMe(),
      ApiService.getPerfil(),
      ApiService.getMaterias(),
    ]);

    final meRes = results[0];
    final perfilRes = results[1];
    final materiasRes = results[2];

    // Si CUALQUIER respuesta devuelve 401, el token expiró → logout.
    if (_isUnauthorized(meRes) ||
        _isUnauthorized(perfilRes) ||
        _isUnauthorized(materiasRes)) {
      await _forceLogout('Tu sesión expiró. Inicia sesión de nuevo.');
      return;
    }

    // Si getMe falla con error de red/timeout, lo tratamos como crítico:
    // sin nombre de usuario el home no tiene sentido.
    final meIsNetworkError = !meRes['success'] && _isNetworkLike(meRes);
    final materiasIsNetworkError =
        !materiasRes['success'] && _isNetworkLike(materiasRes);

    if (meIsNetworkError && materiasIsNetworkError) {
      setState(() {
        _loading = false;
        _refreshing = false;
        _criticalError = meRes['error'] as String? ??
            'No se pudieron cargar los datos. Verifica tu conexión.';
      });
      return;
    }

    // Recopilamos avisos no críticos (perfil 404 no es aviso, es estado normal).
    final warnings = <String>[];
    if (!meRes['success']) warnings.add('No se pudo cargar tu nombre');
    if (!materiasRes['success']) warnings.add('No se pudieron cargar las materias');
    if (!perfilRes['success'] &&
        perfilRes['errorType'] != ApiErrorType.notFound) {
      warnings.add('No se pudo cargar el perfil nutricional');
    }

    setState(() {
      if (meRes['success'] == true) {
        _nombre = meRes['data']['nombre'];
      }
      if (perfilRes['success'] == true) {
        _perfil = perfilRes['data'];
      } else if (perfilRes['errorType'] == ApiErrorType.notFound) {
        _perfil = null; // perfil aún no creado, NO es error
      }
      if (materiasRes['success'] == true) {
        final list = materiasRes['data'] as List;
        _materias = list.map((m) => Materia.fromJson(m)).toList();
      }
      _loading = false;
      _refreshing = false;
      _warning = warnings.isEmpty ? null : warnings.join(' · ');
    });
  }

  bool _isUnauthorized(Map<String, dynamic> res) =>
      res['errorType'] == ApiErrorType.unauthorized;

  bool _isNetworkLike(Map<String, dynamic> res) {
    final t = res['errorType'];
    return t == ApiErrorType.timeout ||
        t == ApiErrorType.network ||
        t == ApiErrorType.unknown;
  }

  Future<void> _forceLogout(String message) async {
    await ApiService.clearToken();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange[800],
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
  }

  double? get _imc {
    if (_perfil == null) return null;
    final peso = (_perfil!['peso'] as num?)?.toDouble();
    final altura = (_perfil!['altura'] as num?)?.toDouble();
    if (peso == null || altura == null || altura == 0) return null;
    // El perfil guarda altura en cm
    final alturaM = altura / 100;
    return peso / (alturaM * alturaM);
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
      Navigator.pushNamed(context, '/materias').then((_) => _loadData());
      return;
    }
    Navigator.pushNamed(context, '/horario', arguments: _materias)
        .then((_) => _loadData());
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
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
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

    if (_criticalError != null) {
      return _buildErrorScreen();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: RefreshIndicator(
        color: Colors.green,
        onRefresh: () => _loadData(isRefresh: true),
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_warning != null) ...[
                      const SizedBox(height: 16),
                      _buildWarningBanner(),
                    ],
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

  /// Pantalla cuando la carga falló por completo (sin red, backend caído, etc.)
  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        title: const Text('NutriCampus AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 72, color: Colors.grey[400]),
              const SizedBox(height: 20),
              const Text(
                'No pudimos cargar tus datos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _criticalError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _loadData(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 28, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Banner ámbar cuando hay errores parciales pero la UI sigue siendo útil.
  Widget _buildWarningBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.amber[800], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _warning!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber[900],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _loadData(isRefresh: true),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Reintentar',
              style: TextStyle(
                color: Colors.amber[900],
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
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
        // Indicador de refresh en el AppBar
        if (_refreshing)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white),
          tooltip: 'Cerrar sesión',
          onPressed: _logout,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        // Sin `title` aquí — antes se traslapaba con el saludo cuando se expandía.
        // Cuando la barra colapsa, queda solo la franja verde con los iconos a la derecha.
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
                      Expanded(
                        child: Column(
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
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
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
            onPressed: () => Navigator.pushNamed(context, '/materias')
                .then((_) => _loadData()),
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
