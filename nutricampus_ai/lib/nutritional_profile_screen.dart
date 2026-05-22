import 'package:flutter/material.dart';
import 'api_service.dart';

// ── Paleta pastel ─────────────────────────────────────────────────
const _primaryGreen = Color(0xFF2E7D32);
const _softGreen = Color(0xFFE8F5E9);
const _pastelPeach = Color(0xFFFFE0B2);
const _pastelBlue = Color(0xFFBBDEFB);
const _pastelPink = Color(0xFFF8BBD0);
const _pastelPurple = Color(0xFFE1BEE7);
const _pastelYellow = Color(0xFFFFF9C4);
const _bgColor = Color(0xFFF8FAF9);
const _darkText = Color(0xFF1A1A2E);

// ── Opciones globales ─────────────────────────────────────────────

const List<Map<String, dynamic>> _genders = [
  {'value': 'Masculino', 'icon': Icons.male, 'color': _pastelBlue},
  {'value': 'Femenino', 'icon': Icons.female, 'color': _pastelPink},
  {'value': 'Prefiero no decir', 'icon': Icons.person_outline, 'color': _pastelPurple},
];

const List<Map<String, dynamic>> _goals = [
  {'value': 'Mantener', 'icon': Icons.balance, 'color': _pastelBlue, 'desc': 'Mantener mi peso actual'},
  {'value': 'Bajar peso', 'icon': Icons.trending_down, 'color': _pastelPink, 'desc': 'Reducir mi peso de forma saludable'},
  {'value': 'Subir masa', 'icon': Icons.fitness_center, 'color': _pastelPeach, 'desc': 'Ganar masa muscular'},
  {'value': 'Mejorar rendimiento', 'icon': Icons.bolt, 'color': _pastelPurple, 'desc': 'Optimizar mi energía y desempeño'},
];

const List<Map<String, dynamic>> _activityLevels = [
  {'value': 'Bajo', 'icon': Icons.weekend, 'color': _pastelBlue, 'desc': 'Poco o nada de ejercicio'},
  {'value': 'Moderado', 'icon': Icons.directions_walk, 'color': _pastelYellow, 'desc': '3-5 días por semana'},
  {'value': 'Alto', 'icon': Icons.directions_run, 'color': _pastelPeach, 'desc': '6-7 días por semana'},
  {'value': 'Muy alto', 'icon': Icons.local_fire_department, 'color': _pastelPink, 'desc': '2 veces al día'},
];

const List<Map<String, dynamic>> _diets = [
  {'value': 'Sin restricciones', 'icon': Icons.restaurant, 'color': _pastelBlue},
  {'value': 'Vegetariana', 'icon': Icons.eco, 'color': _softGreen},
  {'value': 'Vegana', 'icon': Icons.spa, 'color': _softGreen},
  {'value': 'Sin gluten', 'icon': Icons.no_food, 'color': _pastelPeach},
  {'value': 'Sin lactosa', 'icon': Icons.no_drinks, 'color': _pastelPink},
];

const List<String> _alergiasComunes = [
  'Maní', 'Mariscos', 'Huevo', 'Lácteos', 'Frutos secos',
  'Gluten', 'Soya', 'Pescado', 'Mostaza', 'Sésamo',
];

const List<String> _condicionesComunes = [
  'Diabetes', 'Hipertensión', 'Colesterol alto', 'Anemia',
  'Hipotiroidismo', 'Hipertiroidismo', 'Síndrome de intestino irritable',
  'Enfermedad celíaca', 'Reflujo gastroesofágico', 'Gastritis',
];

/// Convierte un string CSV ("Maní, Kiwi") a lista de items.
/// Devuelve lista vacía si el string es null o vacío.
List<String> _csvToList(String? csv) {
  if (csv == null || csv.trim().isEmpty) return const [];
  return csv
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Convierte una lista de items a string CSV ("Maní, Kiwi").
/// Devuelve null si la lista está vacía.
String? _listToCsv(List<String> items) {
  if (items.isEmpty) return null;
  return items.join(', ');
}

const _meses = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

// ── Helpers ──────────────────────────────────────────────────────

/// Calcula la edad (años cumplidos) a partir de la fecha de nacimiento.
int _calcularEdad(DateTime nacimiento) {
  final hoy = DateTime.now();
  int edad = hoy.year - nacimiento.year;
  if (hoy.month < nacimiento.month ||
      (hoy.month == nacimiento.month && hoy.day < nacimiento.day)) {
    edad--;
  }
  return edad;
}

String _formatFecha(DateTime d) {
  return '${d.day} de ${_meses[d.month - 1]} de ${d.year}';
}

String _formatFechaCorta(DateTime d) {
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String _fechaToIso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseFechaIso(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return DateTime.parse(s);
  } catch (_) {
    return null;
  }
}

double? _calcBmi(double? peso, double? altura) {
  if (peso == null || altura == null || altura == 0) return null;
  final m = altura / 100;
  return peso / (m * m);
}

String _bmiCategoria(double bmi) {
  if (bmi < 18.5) return 'Bajo peso';
  if (bmi < 25.0) return 'Normal';
  if (bmi < 30.0) return 'Sobrepeso';
  return 'Obesidad';
}

Color _bmiColor(double bmi) {
  if (bmi < 18.5) return Colors.blue;
  if (bmi < 25.0) return _primaryGreen;
  if (bmi < 30.0) return Colors.orange;
  return Colors.red;
}

int _calcularCalorias({
  required int? edad, required double? peso, required double? altura,
  required String? sexo, required String? actividad, String? objetivo,
}) {
  if (edad == null || peso == null || altura == null ||
      sexo == null || actividad == null) {
    return 0;
  }

  // Paso 1: TMB (Mifflin-St Jeor)
  double tmb = (sexo == 'Masculino')
      ? 10 * peso + 6.25 * altura - 5 * edad + 5
      : 10 * peso + 6.25 * altura - 5 * edad - 161;

  // Paso 2: TDEE (TMB × factor de actividad)
  const factores = {'Bajo': 1.2, 'Moderado': 1.55, 'Alto': 1.725, 'Muy alto': 1.9};
  final tdee = tmb * (factores[actividad] ?? 1.2);

  // Paso 3: ajustar según objetivo (déficit/superávit calórico)
  const ajustes = {
    'Mantener':             1.00,
    'Bajar peso':           0.85,  // déficit ~15 %
    'Subir masa':           1.10,  // superávit ~10 %
    'Mejorar rendimiento':  1.05,  // ligero superávit
  };
  final ajuste = ajustes[objetivo] ?? 1.00;

  return (tdee * ajuste).round();
}

// ── Date picker con scroll por año ────────────────────────────────

/// Muestra un date picker custom con scroll horizontal de años para
/// elegir fecha de nacimiento rápidamente. Devuelve la fecha elegida
/// o null si se canceló.
Future<DateTime?> _showBirthDatePicker(
  BuildContext context, {
  DateTime? initialDate,
}) {
  final now = DateTime.now();
  final maxDate = DateTime(now.year - 10, now.month, now.day); // mínimo 10 años
  final minDate = DateTime(now.year - 100, 1, 1); // máximo 100 años
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _BirthDatePickerSheet(
      initialDate: initialDate ?? DateTime(now.year - 20, now.month, now.day),
      minDate: minDate,
      maxDate: maxDate,
    ),
  );
}

class _BirthDatePickerSheet extends StatefulWidget {
  final DateTime initialDate;
  final DateTime minDate;
  final DateTime maxDate;

  const _BirthDatePickerSheet({
    required this.initialDate,
    required this.minDate,
    required this.maxDate,
  });

  @override
  State<_BirthDatePickerSheet> createState() => _BirthDatePickerSheetState();
}

class _BirthDatePickerSheetState extends State<_BirthDatePickerSheet> {
  late int _selectedYear;
  late int _selectedMonth;
  late int _selectedDay;
  late ScrollController _yearController;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialDate.year;
    _selectedMonth = widget.initialDate.month;
    _selectedDay = widget.initialDate.day;
    // Posicionar el scroll en el año actual
    final yearIndex = _selectedYear - widget.minDate.year;
    _yearController = ScrollController(
      initialScrollOffset: (yearIndex * 64.0) - 100, // 64px por chip aprox
    );
  }

  @override
  void dispose() {
    _yearController.dispose();
    super.dispose();
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  void _clampDay() {
    final max = _daysInMonth(_selectedYear, _selectedMonth);
    if (_selectedDay > max) _selectedDay = max;
  }

  DateTime get _currentDate => DateTime(_selectedYear, _selectedMonth, _selectedDay);

  bool get _isValid {
    final d = _currentDate;
    return d.isAfter(widget.minDate.subtract(const Duration(days: 1))) &&
        d.isBefore(widget.maxDate.add(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final years = List.generate(
      widget.maxDate.year - widget.minDate.year + 1,
      (i) => widget.maxDate.year - i, // años recientes primero (más cerca de hoy)
    );
    final daysInMonth = _daysInMonth(_selectedYear, _selectedMonth);
    final edad = _calcularEdad(_currentDate);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Tu fecha de nacimiento',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText)),
            ),
          ),
          // Vista previa de la fecha + edad
          Container(
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_softGreen, _pastelBlue.withValues(alpha: 0.4)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.cake, color: _primaryGreen, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatFecha(_currentDate),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _darkText),
                      ),
                      const SizedBox(height: 2),
                      Text('Tienes $edad años',
                          style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold, color: _primaryGreen,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── AÑO (scroll horizontal) ───────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Año',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView.builder(
              controller: _yearController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: years.length,
              itemBuilder: (_, i) {
                final year = years[i];
                final isSelected = year == _selectedYear;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedYear = year;
                    _clampDay();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? _primaryGreen : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        '$year',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : _darkText,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── MES (chips horizontales) ──────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                Text('Mes',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 12,
              itemBuilder: (_, i) {
                final month = i + 1;
                final isSelected = month == _selectedMonth;
                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedMonth = month;
                    _clampDay();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isSelected ? _primaryGreen : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? _primaryGreen : Colors.grey.shade300,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _meses[i].substring(0, 3),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : _darkText,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── DÍA (grid) ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                Text('Día',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(daysInMonth, (i) {
                final day = i + 1;
                final isSelected = day == _selectedDay;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDay = day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: isSelected ? _primaryGreen : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? _primaryGreen : Colors.grey.shade300,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : _darkText,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Botones ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                      side: BorderSide(color: Colors.grey.shade400),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isValid ? () => Navigator.pop(context, _currentDate) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(top: false, child: const SizedBox.shrink()),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// WIDGET PRINCIPAL — switch entre wizard y edición
// ═════════════════════════════════════════════════════════════════

class NutritionalProfileScreen extends StatelessWidget {
  final bool isEditing;

  const NutritionalProfileScreen({super.key, this.isEditing = false});

  @override
  Widget build(BuildContext context) {
    return isEditing ? const _EditProfileView() : const _ProfileWizard();
  }
}

// ═════════════════════════════════════════════════════════════════
// WIZARD (primera vez)
// ═════════════════════════════════════════════════════════════════

class _ProfileWizard extends StatefulWidget {
  const _ProfileWizard();

  @override
  State<_ProfileWizard> createState() => _ProfileWizardState();
}

class _ProfileWizardState extends State<_ProfileWizard> {
  static const _totalSteps = 5;
  int _currentStep = 0;

  final _weightController = TextEditingController();
  final _heightController = TextEditingController();

  // Listas de chips seleccionados (predefinidos + personalizados)
  List<String> _alergias = [];
  List<String> _condiciones = [];

  DateTime? _fechaNacimiento;
  String? _selectedGender;
  String? _selectedGoal;
  String? _selectedActivity;
  String? _selectedDiet;
  bool _isLoading = false;

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  int? get _edad => _fechaNacimiento != null ? _calcularEdad(_fechaNacimiento!) : null;

  double? get _bmi => _calcBmi(
        double.tryParse(_weightController.text),
        double.tryParse(_heightController.text),
      );

  int get _calorias => _calcularCalorias(
        edad: _edad,
        peso: double.tryParse(_weightController.text),
        altura: double.tryParse(_heightController.text),
        sexo: _selectedGender,
        actividad: _selectedActivity,
        objetivo: _selectedGoal,
      );

  bool _canAdvance() {
    switch (_currentStep) {
      case 0:
        return _selectedGender != null && _fechaNacimiento != null;
      case 1:
        final w = double.tryParse(_weightController.text);
        final h = double.tryParse(_heightController.text);
        return w != null && w >= 20 && w <= 300 && h != null && h >= 100 && h <= 250;
      case 2: return _selectedGoal != null;
      case 3: return _selectedActivity != null;
      case 4: return _selectedDiet != null;
      default: return false;
    }
  }

  String _stepErrorMessage() {
    switch (_currentStep) {
      case 0: return 'Completa tu género y fecha de nacimiento';
      case 1: return 'Ingresa un peso (20-300 kg) y una altura (100-250 cm)';
      case 2: return 'Selecciona un objetivo';
      case 3: return 'Selecciona tu nivel de actividad';
      case 4: return 'Selecciona tu tipo de dieta';
      default: return '';
    }
  }

  void _nextStep() {
    if (!_canAdvance()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_stepErrorMessage()),
        backgroundColor: Colors.orange[800],
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _handleSave();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  Future<void> _pickBirthDate() async {
    final picked = await _showBirthDatePicker(context, initialDate: _fechaNacimiento);
    if (picked != null) {
      setState(() => _fechaNacimiento = picked);
    }
  }

  void _handleSave() async {
    setState(() => _isLoading = true);

    final result = await ApiService.savePerfil(
      edad: _edad!,
      peso: double.parse(_weightController.text),
      altura: double.parse(_heightController.text),
      sexo: _selectedGender!,
      nivelActividad: _selectedActivity!,
      objetivo: _selectedGoal!,
      alergias: _listToCsv(_alergias),
      dieta: _selectedDiet,
      caloriasDiarias: _calorias,
      condicionesMedicas: _listToCsv(_condiciones),
      fechaNacimiento: _fechaToIso(_fechaNacimiento!),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['errorType'] == ApiErrorType.unauthorized) {
      await ApiService.clearToken();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Perfil guardado correctamente'),
        backgroundColor: _primaryGreen,
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['error'] as String? ?? 'No se pudo guardar el perfil'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildProgressBar(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_currentStep),
                  child: _buildCurrentStep(),
                ),
              ),
            ),
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          if (_currentStep > 0)
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: _primaryGreen),
              onPressed: _previousStep,
            )
          else
            const SizedBox(width: 48),
          const Expanded(
            child: Text(
              'Tu Perfil Nutricional',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryGreen),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Paso ${_currentStep + 1} de $_totalSteps',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600)),
              Text('${(((_currentStep + 1) / _totalSteps) * 100).round()}%',
                  style: const TextStyle(fontSize: 12, color: _primaryGreen, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (_currentStep + 1) / _totalSteps),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(_primaryGreen),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0: return _stepBasicInfo();
      case 1: return _stepBody();
      case 2: return _stepGoal();
      case 3: return _stepActivity();
      case 4: return _stepDiet();
      default: return const SizedBox();
    }
  }

  Widget _stepBasicInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('¡Hola! Cuéntanos sobre ti', '👋'),
          _stepSubtitle('Empecemos con lo básico'),
          const SizedBox(height: 24),
          _sectionLabel('¿Con qué género te identificas?'),
          const SizedBox(height: 12),
          Column(
            children: _genders.map((g) => _selectableTile(
                  icon: g['icon'],
                  label: g['value'],
                  color: g['color'],
                  isSelected: _selectedGender == g['value'],
                  onTap: () => setState(() => _selectedGender = g['value']),
                )).toList(),
          ),
          const SizedBox(height: 20),
          _sectionLabel('¿Cuándo naciste?'),
          const SizedBox(height: 12),
          // Card-button que abre el date picker
          GestureDetector(
            onTap: _pickBirthDate,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _fechaNacimiento != null ? _primaryGreen : Colors.grey.shade300,
                  width: _fechaNacimiento != null ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _fechaNacimiento != null ? _softGreen : Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cake_outlined,
                      color: _fechaNacimiento != null ? _primaryGreen : Colors.grey,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_fechaNacimiento == null) ...[
                          const Text(
                            'Toca para seleccionar',
                            style: TextStyle(fontSize: 15, color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Calcularemos tu edad automáticamente',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ] else ...[
                          Text(
                            _formatFecha(_fechaNacimiento!),
                            style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold, color: _darkText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tienes ${_edad!} años',
                            style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: _primaryGreen,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('Tus medidas', '📏'),
          _stepSubtitle('Calcularemos tu IMC y necesidades calóricas'),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _measurementCard(
                  controller: _weightController,
                  label: 'Peso', suffix: 'kg',
                  icon: Icons.fitness_center, decimal: true, color: _pastelPeach,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _measurementCard(
                  controller: _heightController,
                  label: 'Altura', suffix: 'cm',
                  icon: Icons.height, decimal: false, color: _pastelBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_bmi != null) _BmiResultCard(bmi: _bmi!),
        ],
      ),
    );
  }

  Widget _stepGoal() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('¿Cuál es tu meta?', '🎯'),
          _stepSubtitle('Tu objetivo determina tus recomendaciones'),
          const SizedBox(height: 24),
          ..._goals.map((g) => _bigOptionCard(
                icon: g['icon'], label: g['value'], description: g['desc'],
                color: g['color'], isSelected: _selectedGoal == g['value'],
                onTap: () => setState(() => _selectedGoal = g['value']),
              )),
        ],
      ),
    );
  }

  Widget _stepActivity() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('¿Qué tan activo eres?', '🏃‍♂️'),
          _stepSubtitle('Esto nos ayuda a calcular tus calorías'),
          const SizedBox(height: 24),
          ..._activityLevels.map((a) => _bigOptionCard(
                icon: a['icon'], label: a['value'], description: a['desc'],
                color: a['color'], isSelected: _selectedActivity == a['value'],
                onTap: () => setState(() => _selectedActivity = a['value']),
              )),
          if (_calorias > 0) ...[
            const SizedBox(height: 16),
            _CaloriesPreviewCard(calorias: _calorias, objetivo: _selectedGoal),
          ],
        ],
      ),
    );
  }

  Widget _stepDiet() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepTitle('Dieta y salud', '🥗'),
          _stepSubtitle('Último paso, ya casi terminas'),
          const SizedBox(height: 24),
          _sectionLabel('¿Sigues algún tipo de dieta?'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: _diets.map((d) => _dietChip(
                  icon: d['icon'], label: d['value'], color: d['color'],
                  isSelected: _selectedDiet == d['value'],
                  onTap: () => setState(() => _selectedDiet = d['value']),
                )).toList(),
          ),
          const SizedBox(height: 24),
          _sectionLabel('Alergias (opcional)'),
          const SizedBox(height: 4),
          Text(
            'Toca las que apliquen, o agrega tus propias',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          _MultiSelectChips(
            predefined: _alergiasComunes,
            selected: _alergias,
            accentColor: Colors.amber.shade700,
            customHint: 'Ej: kiwi, fresa...',
            onChanged: (list) => setState(() => _alergias = list),
          ),
          const SizedBox(height: 24),
          _sectionLabel('Condiciones médicas (opcional)'),
          const SizedBox(height: 4),
          Text(
            'Toca las que apliquen, o agrega las tuyas',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          _MultiSelectChips(
            predefined: _condicionesComunes,
            selected: _condiciones,
            accentColor: Colors.red.shade400,
            customHint: 'Ej: asma, migraña...',
            onChanged: (list) => setState(() => _condiciones = list),
          ),
        ],
      ),
    );
  }

  // ── Componentes ─────────────────────────────────────────────

  Widget _stepTitle(String text, String emoji) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _darkText)),
        ),
      ],
    );
  }

  Widget _stepSubtitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 38),
      child: Text(text, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _darkText));
  }

  Widget _selectableTile({
    required IconData icon, required String label, required Color color,
    required bool isSelected, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? _primaryGreen : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 3))]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : color, shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _darkText, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _darkText)),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: _primaryGreen, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _bigOptionCard({
    required IconData icon, required String label, required String description,
    required Color color, required bool isSelected, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _primaryGreen : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : color, shape: BoxShape.circle,
              ),
              child: Icon(icon, color: _darkText, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _darkText)),
                  const SizedBox(height: 2),
                  Text(description, style: TextStyle(fontSize: 12.5, color: Colors.grey[700])),
                ],
              ),
            ),
            if (isSelected) const Icon(Icons.check_circle, color: _primaryGreen, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _dietChip({
    required IconData icon, required String label, required Color color,
    required bool isSelected, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isSelected ? _primaryGreen : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: _darkText),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _darkText)),
            if (isSelected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check, color: _primaryGreen, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  Widget _measurementCard({
    required TextEditingController controller, required String label, required String suffix,
    required IconData icon, required bool decimal, required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 18, color: _darkText),
              ),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _primaryGreen),
            decoration: InputDecoration(
              isDense: true, border: InputBorder.none, suffixText: suffix,
              suffixStyle: TextStyle(fontSize: 14, color: Colors.grey[600], fontWeight: FontWeight.w500),
              hintText: '0', hintStyle: TextStyle(color: Colors.grey.shade300),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    final isLast = _currentStep == _totalSteps - 1;
    final canAdvance = _canAdvance();

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _previousStep,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryGreen,
                    side: const BorderSide(color: _primaryGreen),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Atrás', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isLoading ? null : (canAdvance ? _nextStep : null),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen, foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(isLast ? 'Guardar Perfil' : 'Siguiente',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 6),
                          Icon(isLast ? Icons.check_rounded : Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// VISTA DE EDICIÓN (perfil existente)
// ═════════════════════════════════════════════════════════════════

class _EditProfileView extends StatefulWidget {
  const _EditProfileView();

  @override
  State<_EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<_EditProfileView> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  String? _nombre;
  int? _edad;
  DateTime? _fechaNacimiento;
  double? _peso;
  double? _altura;
  String? _sexo;
  String? _objetivo;
  String? _nivelActividad;
  String? _dieta;
  String? _alergias;
  String? _condicionesMedicas;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    final results = await Future.wait([
      ApiService.getMe(),
      ApiService.getPerfil(),
    ]);

    if (!mounted) return;

    final meRes = results[0];
    final perfilRes = results[1];

    if (meRes['errorType'] == ApiErrorType.unauthorized ||
        perfilRes['errorType'] == ApiErrorType.unauthorized) {
      await ApiService.clearToken();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    if (!perfilRes['success']) {
      setState(() {
        _isLoading = false;
        _loadError = perfilRes['error'] as String? ?? 'No se pudo cargar el perfil';
      });
      return;
    }

    final data = perfilRes['data'] as Map<String, dynamic>;
    final fNac = _parseFechaIso(data['fecha_nacimiento'] as String?);
    setState(() {
      _nombre = meRes['success'] ? meRes['data']['nombre'] as String? : null;
      _fechaNacimiento = fNac;
      // Si hay fecha de nacimiento, la edad se calcula desde ella;
      // si no, usamos la edad guardada (modo legacy).
      _edad = fNac != null ? _calcularEdad(fNac) : data['edad'];
      _peso = (data['peso'] as num?)?.toDouble();
      _altura = (data['altura'] as num?)?.toDouble();
      _sexo = data['sexo'];
      _objetivo = data['objetivo'];
      _nivelActividad = data['nivel_actividad'];
      _dieta = data['dieta'];
      _alergias = data['alergias'];
      _condicionesMedicas = data['condiciones_medicas'];
      _isLoading = false;
    });
  }

  double? get _bmi => _calcBmi(_peso, _altura);
  int get _calorias => _calcularCalorias(
        edad: _edad, peso: _peso, altura: _altura,
        sexo: _sexo, actividad: _nivelActividad, objetivo: _objetivo,
      );

  Future<void> _saveProfile() async {
    if (_edad == null || _peso == null || _altura == null ||
        _sexo == null || _objetivo == null || _nivelActividad == null) {
      return;
    }

    setState(() => _isSaving = true);

    final result = await ApiService.savePerfil(
      edad: _edad!,
      peso: _peso!,
      altura: _altura!,
      sexo: _sexo!,
      nivelActividad: _nivelActividad!,
      objetivo: _objetivo!,
      alergias: (_alergias?.trim().isEmpty ?? true) ? null : _alergias!.trim(),
      dieta: _dieta,
      caloriasDiarias: _calorias,
      condicionesMedicas: (_condicionesMedicas?.trim().isEmpty ?? true) ? null : _condicionesMedicas!.trim(),
      fechaNacimiento: _fechaNacimiento != null ? _fechaToIso(_fechaNacimiento!) : null,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['errorType'] == ApiErrorType.unauthorized) {
      await ApiService.clearToken();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      return;
    }

    if (!result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['error'] as String? ?? 'No se pudo guardar'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Modales ──────────────────────────────────────────────────

  Future<void> _editSingleChoice({
    required String title,
    required List<Map<String, dynamic>> options,
    required String? current,
    required void Function(String) onSelected,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _ChoiceSheet(title: title, options: options, current: current),
    );
    if (selected != null && selected != current) {
      setState(() => onSelected(selected));
      await _saveProfile();
      if (mounted) _showSavedSnack();
    }
  }

  Future<void> _editNumber({
    required String title, required String suffix, required IconData icon,
    required String? currentText, required bool decimal,
    required void Function(String) onSaved,
    required bool Function(String) isValid, required String errorMessage,
  }) async {
    final newValue = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _NumberInputSheet(
        title: title, suffix: suffix, icon: icon,
        initialValue: currentText, decimal: decimal,
        isValid: isValid, errorMessage: errorMessage,
      ),
    );
    if (newValue != null) {
      setState(() => onSaved(newValue));
      await _saveProfile();
      if (mounted) _showSavedSnack();
    }
  }

  Future<void> _editBirthDate() async {
    final picked = await _showBirthDatePicker(context, initialDate: _fechaNacimiento);
    if (picked != null) {
      setState(() {
        _fechaNacimiento = picked;
        _edad = _calcularEdad(picked);
      });
      await _saveProfile();
      if (mounted) _showSavedSnack();
    }
  }

  /// Abre el bottom sheet de multiselect para alergias / condiciones.
  /// Recibe el CSV actual, devuelve el nuevo CSV (o null si la lista quedó vacía).
  Future<void> _editMultiSelect({
    required String title,
    required String customHint,
    required IconData icon,
    required Color accentColor,
    required List<String> predefined,
    required String? currentCsv,
    required void Function(String?) onSaved,
  }) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _MultiSelectSheet(
        title: title,
        customHint: customHint,
        icon: icon,
        accentColor: accentColor,
        predefined: predefined,
        initialSelected: _csvToList(currentCsv),
      ),
    );
    if (result != null) {
      setState(() => onSaved(_listToCsv(result)));
      await _saveProfile();
      if (mounted) _showSavedSnack();
    }
  }

  void _showSavedSnack() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text('Perfil actualizado'),
        ],
      ),
      backgroundColor: _primaryGreen,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _primaryGreen)),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: _primaryGreen, foregroundColor: Colors.white,
          title: const Text('Editar Perfil'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off_rounded, size: 72, color: Colors.grey[400]),
                const SizedBox(height: 20),
                Text(_loadError!, textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadAll,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen, foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      body: CustomScrollView(
        slivers: [
          _buildHeader(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  if (_isSaving) _savingIndicator(),
                  if (_fechaNacimiento == null && _edad != null) _legacyAgeWarning(),
                  const SizedBox(height: 8),
                  _sectionHeader('Datos personales'),
                  _genderRow(),
                  _birthDateOrAgeRow(),
                  const SizedBox(height: 16),
                  _sectionHeader('Cuerpo'),
                  _bodyRow(),
                  const SizedBox(height: 16),
                  _sectionHeader('Plan'),
                  _planCards(),
                  const SizedBox(height: 16),
                  _sectionHeader('Dieta y salud'),
                  _dietaCard(),
                  _alergiasCard(),
                  _condicionesCard(),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final initials = (_nombre?.trim().isNotEmpty == true)
        ? _nombre!.trim().split(' ').take(2).map((p) => p[0]).join().toUpperCase()
        : '?';
    final bmi = _bmi;

    return SliverAppBar(
      expandedHeight: 230, pinned: true, elevation: 0,
      backgroundColor: _primaryGreen, foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Text('Mi Perfil', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF1B5E20), _primaryGreen, Color(0xFF66BB6A)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                    ),
                    child: Center(
                      child: Text(initials,
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_nombre ?? 'Estudiante',
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        if (bmi != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.monitor_weight_outlined, size: 14, color: Colors.white),
                                const SizedBox(width: 5),
                                Text('IMC ${bmi.toStringAsFixed(1)} · ${_bmiCategoria(bmi)}',
                                    style: const TextStyle(
                                      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600,
                                    )),
                              ],
                            ),
                          ),
                        if (_calorias > 0) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.local_fire_department, size: 14, color: Colors.white),
                              const SizedBox(width: 4),
                              Text('$_calorias kcal / día',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.w500,
                                  )),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _savingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: _softGreen, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 12, height: 12,
            child: CircularProgressIndicator(color: _primaryGreen, strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Guardando...',
              style: TextStyle(fontSize: 12, color: _primaryGreen, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Banner que aparece cuando el perfil viejo no tiene fecha_nacimiento.
  /// Invita al usuario a agregarla para tener edad siempre al día.
  Widget _legacyAgeWarning() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.amber[800], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Agrega tu fecha de nacimiento para que tu edad se actualice sola cada año.',
              style: TextStyle(fontSize: 12, color: Colors.amber[900], fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: _editBirthDate,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Agregar',
                style: TextStyle(color: Colors.amber[900], fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10, left: 4),
      child: Text(text,
          style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold,
            color: Colors.grey, letterSpacing: 0.5,
          )),
    );
  }

  Widget _genderRow() {
    final genderData = _genders.firstWhere(
      (g) => g['value'] == _sexo,
      orElse: () => {'value': _sexo ?? '—', 'icon': Icons.person_outline, 'color': _pastelPurple},
    );
    return _editCard(
      icon: genderData['icon'], iconColor: genderData['color'],
      label: 'Género', value: _sexo ?? '—',
      onTap: () => _editSingleChoice(
        title: 'Tu género', options: _genders, current: _sexo,
        onSelected: (v) => _sexo = v,
      ),
    );
  }

  /// Si hay fecha_nacimiento → card de fecha (con edad calculada como subtítulo).
  /// Si no → card de edad numérica (modo legacy).
  Widget _birthDateOrAgeRow() {
    if (_fechaNacimiento != null) {
      return _editCard(
        icon: Icons.cake_outlined, iconColor: _pastelPurple,
        label: 'Fecha de nacimiento',
        value: _formatFechaCorta(_fechaNacimiento!),
        subtitle: '${_edad ?? 0} años',
        onTap: _editBirthDate,
      );
    }
    return _editCard(
      icon: Icons.cake_outlined, iconColor: _pastelPurple,
      label: 'Edad', value: _edad != null ? '$_edad años' : '—',
      subtitle: 'Toca para agregar tu fecha de nacimiento',
      onTap: _editBirthDate,
    );
  }

  Widget _bodyRow() {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            icon: Icons.fitness_center, iconColor: _pastelPeach,
            label: 'Peso',
            value: _peso != null ? _peso!.toStringAsFixed(1) : '—',
            unit: 'kg',
            onTap: () => _editNumber(
              title: 'Tu peso', suffix: 'kg', icon: Icons.fitness_center, decimal: true,
              currentText: _peso?.toString(),
              isValid: (s) {
                final n = double.tryParse(s);
                return n != null && n >= 20 && n <= 300;
              },
              errorMessage: 'Ingresa un peso entre 20 y 300',
              onSaved: (s) => _peso = double.parse(s),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
            icon: Icons.height, iconColor: _pastelBlue,
            label: 'Altura',
            value: _altura != null ? _altura!.toStringAsFixed(0) : '—',
            unit: 'cm',
            onTap: () => _editNumber(
              title: 'Tu altura', suffix: 'cm', icon: Icons.height, decimal: false,
              currentText: _altura?.toStringAsFixed(0),
              isValid: (s) {
                final n = double.tryParse(s);
                return n != null && n >= 100 && n <= 250;
              },
              errorMessage: 'Ingresa una altura entre 100 y 250',
              onSaved: (s) => _altura = double.parse(s),
            ),
          ),
        ),
      ],
    );
  }

  Widget _planCards() {
    final goalData = _goals.firstWhere(
      (g) => g['value'] == _objetivo,
      orElse: () => {'value': _objetivo ?? '—', 'icon': Icons.flag_outlined, 'color': _pastelBlue, 'desc': ''},
    );
    final actData = _activityLevels.firstWhere(
      (a) => a['value'] == _nivelActividad,
      orElse: () => {'value': _nivelActividad ?? '—', 'icon': Icons.directions_walk, 'color': _pastelYellow, 'desc': ''},
    );
    return Column(
      children: [
        _editCard(
          icon: goalData['icon'], iconColor: goalData['color'],
          label: 'Objetivo', value: _objetivo ?? '—', subtitle: goalData['desc'],
          onTap: () => _editSingleChoice(
            title: 'Tu objetivo', options: _goals, current: _objetivo,
            onSelected: (v) => _objetivo = v,
          ),
        ),
        _editCard(
          icon: actData['icon'], iconColor: actData['color'],
          label: 'Nivel de actividad', value: _nivelActividad ?? '—',
          subtitle: actData['desc'],
          onTap: () => _editSingleChoice(
            title: 'Tu nivel de actividad', options: _activityLevels, current: _nivelActividad,
            onSelected: (v) => _nivelActividad = v,
          ),
        ),
      ],
    );
  }

  Widget _dietaCard() {
    final dietaData = _diets.firstWhere(
      (d) => d['value'] == _dieta,
      orElse: () => {'value': _dieta ?? 'No definida', 'icon': Icons.restaurant_outlined, 'color': _pastelBlue},
    );
    return _editCard(
      icon: dietaData['icon'], iconColor: dietaData['color'],
      label: 'Tipo de dieta', value: _dieta ?? 'No definida',
      onTap: () => _editSingleChoice(
        title: 'Tu tipo de dieta', options: _diets, current: _dieta,
        onSelected: (v) => _dieta = v,
      ),
    );
  }

  Widget _alergiasCard() {
    return _editCard(
      icon: Icons.warning_amber_outlined, iconColor: Colors.amber.shade100,
      label: 'Alergias',
      value: _alergias?.isNotEmpty == true ? _alergias! : 'Sin alergias',
      subtitle: _alergias?.isNotEmpty == true ? null : 'Toca para agregar',
      onTap: () => _editMultiSelect(
        title: 'Alergias',
        customHint: 'Ej: kiwi, fresa...',
        icon: Icons.warning_amber_outlined,
        accentColor: Colors.amber.shade700,
        predefined: _alergiasComunes,
        currentCsv: _alergias,
        onSaved: (csv) => _alergias = csv,
      ),
    );
  }

  Widget _condicionesCard() {
    return _editCard(
      icon: Icons.medical_information_outlined, iconColor: Colors.red.shade100,
      label: 'Condiciones médicas',
      value: _condicionesMedicas?.isNotEmpty == true ? _condicionesMedicas! : 'Sin condiciones registradas',
      subtitle: _condicionesMedicas?.isNotEmpty == true ? null : 'Toca para agregar',
      onTap: () => _editMultiSelect(
        title: 'Condiciones médicas',
        customHint: 'Ej: asma, migraña...',
        icon: Icons.medical_information_outlined,
        accentColor: Colors.red.shade400,
        predefined: _condicionesComunes,
        currentCsv: _condicionesMedicas,
        onSaved: (csv) => _condicionesMedicas = csv,
      ),
    );
  }

  Widget _editCard({
    required IconData icon, required Color iconColor,
    required String label, required String value, String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: iconColor, shape: BoxShape.circle),
                  child: Icon(icon, color: _darkText, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(value,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _darkText)),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.grey[500])),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard({
    required IconData icon, required Color iconColor,
    required String label, required String value, required String unit,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: _darkText),
              ),
              const SizedBox(height: 10),
              Text(label,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _primaryGreen)),
                  const SizedBox(width: 3),
                  Text(unit,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// BOTTOM SHEETS DE EDICIÓN
// ═════════════════════════════════════════════════════════════════

class _ChoiceSheet extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> options;
  final String? current;

  const _ChoiceSheet({required this.title, required this.options, required this.current});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText)),
          const SizedBox(height: 16),
          ...options.map((opt) {
            final isSelected = opt['value'] == current;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(context, opt['value'] as String),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected ? opt['color'] : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? _primaryGreen : Colors.grey.shade200,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : opt['color'],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(opt['icon'], color: _darkText, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(opt['value'],
                                style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.bold, color: _darkText,
                                )),
                            if (opt['desc'] != null && (opt['desc'] as String).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Text(opt['desc'],
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey[700])),
                              ),
                          ],
                        ),
                      ),
                      if (isSelected) const Icon(Icons.check_circle, color: _primaryGreen, size: 22),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NumberInputSheet extends StatefulWidget {
  final String title;
  final String suffix;
  final IconData icon;
  final String? initialValue;
  final bool decimal;
  final bool Function(String) isValid;
  final String errorMessage;

  const _NumberInputSheet({
    required this.title, required this.suffix, required this.icon,
    required this.initialValue, required this.decimal,
    required this.isValid, required this.errorMessage,
  });

  @override
  State<_NumberInputSheet> createState() => _NumberInputSheetState();
}

class _NumberInputSheetState extends State<_NumberInputSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (!widget.isValid(value)) {
      setState(() => _error = widget.errorMessage);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _darkText)),
          const SizedBox(height: 20),
          TextField(
            controller: _controller, autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: widget.decimal),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _primaryGreen),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              prefixIcon: Icon(widget.icon, color: _primaryGreen),
              suffixText: widget.suffix,
              suffixStyle: TextStyle(fontSize: 16, color: Colors.grey[600], fontWeight: FontWeight.w500),
              filled: true, fillColor: _bgColor,
              contentPadding: const EdgeInsets.symmetric(vertical: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _primaryGreen, width: 2),
              ),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen, foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}


// ═════════════════════════════════════════════════════════════════
// CARDS COMPARTIDOS
// ═════════════════════════════════════════════════════════════════

class _BmiResultCard extends StatelessWidget {
  final double bmi;
  const _BmiResultCard({required this.bmi});

  @override
  Widget build(BuildContext context) {
    final color = _bmiColor(bmi);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(Icons.monitor_weight_outlined, color: color, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tu IMC', style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(bmi.toStringAsFixed(1),
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                      child: Text(_bmiCategoria(bmi),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CaloriesPreviewCard extends StatelessWidget {
  final int calorias;
  final String? objetivo;

  const _CaloriesPreviewCard({required this.calorias, this.objetivo});

  String? get _explanation {
    switch (objetivo) {
      case 'Bajar peso':
        return 'Incluye un déficit del 15 % sobre tu mantenimiento';
      case 'Subir masa':
        return 'Incluye un superávit del 10 % para ganar masa';
      case 'Mejorar rendimiento':
        return 'Ligero superávit del 5 % para optimizar energía';
      case 'Mantener':
        return 'Calorías para mantener tu peso actual';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final explanation = _explanation;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _softGreen,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _primaryGreen.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.local_fire_department, color: Colors.orange, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Calorías diarias recomendadas',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                Text('$calorias kcal',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _primaryGreen)),
                if (explanation != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    explanation,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[600], fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// MULTISELECT CON CHIPS PREDEFINIDOS + "OTRO"
// ═════════════════════════════════════════════════════════════════

/// Widget reutilizable para alergias y condiciones médicas.
/// Muestra chips predefinidos seleccionables + chip "+ Otro" que abre
/// un input para añadir items personalizados.
///
/// El estado se mantiene como `List<String>` con todos los items elegidos
/// (tanto predefinidos como personalizados). El padre serializa a CSV
/// cuando lo guarda.
class _MultiSelectChips extends StatefulWidget {
  /// Items predefinidos que se muestran como chips fijos.
  final List<String> predefined;

  /// Selección actual (mezcla de predefinidos y personalizados).
  final List<String> selected;

  /// Color del chip seleccionado.
  final Color accentColor;

  /// Placeholder del input de "Otro".
  final String customHint;

  final ValueChanged<List<String>> onChanged;

  const _MultiSelectChips({
    required this.predefined,
    required this.selected,
    required this.accentColor,
    required this.customHint,
    required this.onChanged,
  });

  @override
  State<_MultiSelectChips> createState() => _MultiSelectChipsState();
}

class _MultiSelectChipsState extends State<_MultiSelectChips> {
  bool _showInput = false;
  final _inputController = TextEditingController();
  final _inputFocus = FocusNode();

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// Items personalizados = los que están en `selected` pero NO en `predefined`.
  List<String> get _customs => widget.selected
      .where((s) => !widget.predefined.contains(s))
      .toList();

  void _toggle(String item) {
    final list = [...widget.selected];
    if (list.contains(item)) {
      list.remove(item);
    } else {
      list.add(item);
    }
    widget.onChanged(list);
  }

  void _addCustom() {
    final value = _inputController.text.trim();
    if (value.isEmpty) {
      setState(() => _showInput = false);
      return;
    }
    // Evitar duplicados (case-insensitive)
    final alreadyExists = widget.selected
        .any((s) => s.toLowerCase() == value.toLowerCase());
    if (!alreadyExists) {
      widget.onChanged([...widget.selected, value]);
    }
    _inputController.clear();
    setState(() => _showInput = false);
  }

  void _removeCustom(String item) {
    final list = [...widget.selected]..remove(item);
    widget.onChanged(list);
  }

  @override
  Widget build(BuildContext context) {
    final customs = _customs;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Chips predefinidos + "+ Otro" ───────────────────
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...widget.predefined.map((item) {
              final isSelected = widget.selected.contains(item);
              return _ChipPredefined(
                label: item,
                selected: isSelected,
                accentColor: widget.accentColor,
                onTap: () => _toggle(item),
              );
            }),
            // Chip "+ Otro"
            GestureDetector(
              onTap: () {
                setState(() => _showInput = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _inputFocus.requestFocus();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.grey.shade400,
                    width: 1,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 16, color: Colors.grey[700]),
                    const SizedBox(width: 4),
                    Text(
                      'Otro',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // ── Input para personalizado ────────────────────────
        if (_showInput) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: _inputFocus,
                  onSubmitted: (_) => _addCustom(),
                  decoration: InputDecoration(
                    hintText: widget.customHint,
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: widget.accentColor, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addCustom,
                icon: Icon(Icons.check_circle, color: widget.accentColor, size: 32),
                tooltip: 'Agregar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              IconButton(
                onPressed: () {
                  _inputController.clear();
                  setState(() => _showInput = false);
                },
                icon: Icon(Icons.cancel, color: Colors.grey[400], size: 28),
                tooltip: 'Cancelar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],

        // ── Chips personalizados (con botón quitar) ─────────
        if (customs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: customs.map((item) => Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: _darkText,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _removeCustom(item),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
      ],
    );
  }
}

class _ChipPredefined extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _ChipPredefined({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accentColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accentColor : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check_rounded, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _darkText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════
// BOTTOM SHEET DE MULTISELECT (para vista de edición)
// ═════════════════════════════════════════════════════════════════

class _MultiSelectSheet extends StatefulWidget {
  final String title;
  final String customHint;
  final IconData icon;
  final Color accentColor;
  final List<String> predefined;
  final List<String> initialSelected;

  const _MultiSelectSheet({
    required this.title,
    required this.customHint,
    required this.icon,
    required this.accentColor,
    required this.predefined,
    required this.initialSelected,
  });

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = [...widget.initialSelected];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _darkText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: _MultiSelectChips(
                predefined: widget.predefined,
                selected: _selected,
                accentColor: widget.accentColor,
                customHint: widget.customHint,
                onChanged: (newList) => setState(() => _selected = newList),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
