import 'package:flutter/material.dart';
import 'api_service.dart';

class NutritionalProfileScreen extends StatefulWidget {
  final bool isEditing;

  const NutritionalProfileScreen({super.key, this.isEditing = false});

  @override
  State<NutritionalProfileScreen> createState() =>
      _NutritionalProfileScreenState();
}

class _NutritionalProfileScreenState extends State<NutritionalProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _alergiasController = TextEditingController();
  final _condicionesController = TextEditingController();

  String? _selectedGender;
  String? _selectedGoal;
  String? _selectedActivity;
  String? _selectedDiet;
  bool _isLoading = false;

  final List<String> _genders = ['Masculino', 'Femenino', 'Prefiero no decir'];

  final List<String> _goals = [
    'Mantener',
    'Bajar peso',
    'Subir masa',
    'Mejorar rendimiento',
  ];

  final List<String> _diets = [
    'Sin restricciones',
    'Vegetariana',
    'Vegana',
    'Sin gluten',
    'Sin lactosa',
  ];

  final List<Map<String, String>> _activityLevels = [
    {'value': 'Bajo',     'label': 'Bajo',     'desc': 'Poco o nada de ejercicio'},
    {'value': 'Moderado', 'label': 'Moderado', 'desc': '3-5 dias por semana'},
    {'value': 'Alto',     'label': 'Alto',     'desc': '6-7 dias por semana'},
    {'value': 'Muy alto', 'label': 'Muy alto', 'desc': '2 veces al dia'},
  ];

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _alergiasController.dispose();
    _condicionesController.dispose();
    super.dispose();
  }

  String get _bmiResult {
    final weight = double.tryParse(_weightController.text);
    final height = double.tryParse(_heightController.text);
    if (weight == null || height == null || height == 0) return '--';
    final heightM = height / 100;
    final bmi = weight / (heightM * heightM);
    return bmi.toStringAsFixed(1);
  }

  String get _bmiCategory {
    final bmi = double.tryParse(_bmiResult);
    if (bmi == null) return '';
    if (bmi < 18.5) return 'Bajo peso';
    if (bmi < 25.0) return 'Normal';
    if (bmi < 30.0) return 'Sobrepeso';
    return 'Obesidad';
  }

  Color get _bmiColor {
    final bmi = double.tryParse(_bmiResult);
    if (bmi == null) return Colors.grey;
    if (bmi < 18.5) return Colors.blue;
    if (bmi < 25.0) return Colors.green;
    if (bmi < 30.0) return Colors.orange;
    return Colors.red;
  }

  int _calcularCalorias() {
    final age = int.tryParse(_ageController.text);
    final weight = double.tryParse(_weightController.text);
    final height = double.tryParse(_heightController.text);
    if (age == null || weight == null || height == null ||
        _selectedGender == null || _selectedActivity == null) return 0;

    double tmb;
    if (_selectedGender == 'Masculino') {
      tmb = 10 * weight + 6.25 * height - 5 * age + 5;
    } else {
      tmb = 10 * weight + 6.25 * height - 5 * age - 161;
    }

    final factores = {'Bajo': 1.2, 'Moderado': 1.55, 'Alto': 1.725, 'Muy alto': 1.9};
    final factor = factores[_selectedActivity] ?? 1.2;
    return (tmb * factor).round();
  }

  void _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedActivity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selecciona tu nivel de actividad'),
            backgroundColor: Colors.red),
      );
      return;
    }

    final token = await ApiService.getToken();
    print('Token al guardar perfil: $token');

    setState(() => _isLoading = true);

    final result = await ApiService.savePerfil(
      edad: int.parse(_ageController.text),
      peso: double.parse(_weightController.text),
      altura: double.parse(_heightController.text),
      sexo: _selectedGender!,
      nivelActividad: _selectedActivity!,
      objetivo: _selectedGoal!,
      alergias: _alergiasController.text.trim().isEmpty
          ? null
          : _alergiasController.text.trim(),
      dieta: _selectedDiet,
      caloriasDiarias: _calcularCalorias(),
      condicionesMedicas: _condicionesController.text.trim().isEmpty
          ? null
          : _condicionesController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Perfil guardado correctamente'),
            backgroundColor: Colors.green),
      );
      if (widget.isEditing) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error']), backgroundColor: Colors.red),
      );
    }
  }

  Widget _activityCard(Map<String, String> level) {
    final isSelected = _selectedActivity == level['value'];
    return GestureDetector(
      onTap: () => setState(() => _selectedActivity = level['value']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.green : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(level['label']!,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.green : null)),
                  Text(level['desc']!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar Perfil' : 'Perfil Nutricional'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: widget.isEditing,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              if (!widget.isEditing) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Completa tu perfil para recibir recomendaciones personalizadas.',
                          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: InputDecoration(
                  labelText: 'Genero',
                  prefixIcon: const Icon(Icons.wc_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _genders
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedGender = v),
                validator: (v) => v == null ? 'Selecciona un genero' : null,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _ageController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Edad',
                        prefixIcon: const Icon(Icons.cake_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) {
                        final age = int.tryParse(v ?? '');
                        if (age == null || age < 10 || age > 100) return 'Invalida';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _weightController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Peso (kg)',
                        prefixIcon: const Icon(Icons.fitness_center),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) {
                        final w = double.tryParse(v ?? '');
                        if (w == null || w < 20 || w > 300) return 'Invalido';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _heightController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Altura (cm)',
                        prefixIcon: const Icon(Icons.height),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      validator: (v) {
                        final h = double.tryParse(v ?? '');
                        if (h == null || h < 100 || h > 250) return 'Invalida';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (_bmiResult != '--')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: _bmiColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _bmiColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.monitor_weight_outlined, color: _bmiColor),
                      const SizedBox(width: 8),
                      Text('IMC: ', style: TextStyle(color: Colors.grey[700])),
                      Text(_bmiResult,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: _bmiColor)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: _bmiColor,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(_bmiCategory,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _selectedGoal,
                decoration: InputDecoration(
                  labelText: 'Objetivo',
                  prefixIcon: const Icon(Icons.flag_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _goals
                    .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedGoal = v),
                validator: (v) => v == null ? 'Selecciona un objetivo' : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _selectedDiet,
                decoration: InputDecoration(
                  labelText: 'Tipo de dieta',
                  prefixIcon: const Icon(Icons.restaurant_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _diets
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedDiet = v),
                validator: (v) => v == null ? 'Selecciona un tipo de dieta' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _alergiasController,
                decoration: InputDecoration(
                  labelText: 'Alergias (opcional)',
                  hintText: 'Ej: mani, mariscos, huevo',
                  prefixIcon: const Icon(Icons.warning_amber_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _condicionesController,
                decoration: InputDecoration(
                  labelText: 'Condiciones medicas (opcional)',
                  hintText: 'Ej: diabetes, hipertension',
                  prefixIcon: const Icon(Icons.medical_information_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),

              const Text('Nivel de actividad fisica',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              ..._activityLevels.map(_activityCard),

              if (_calcularCalorias() > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_fire_department_outlined, color: Colors.green),
                        const SizedBox(width: 8),
                        Text('Calorias diarias estimadas: ',
                            style: TextStyle(color: Colors.grey[700])),
                        Text('${_calcularCalorias()} kcal',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _handleSave,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : Text(
                          widget.isEditing
                              ? 'Actualizar Perfil'
                              : 'Guardar y Continuar',
                          style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
