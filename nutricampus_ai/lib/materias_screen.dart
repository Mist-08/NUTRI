import 'package:flutter/material.dart';
import 'package:nutricampus_ai/horario_screen.dart';
import 'api_service.dart';

// ── Modelo ──────────────────────────────────────────────────────
class Materia {
  final int? id;
  final String nombre;
  final String? aula;
  final String? profesor;
  final String color;
  final bool lunes;
  final bool martes;
  final bool miercoles;
  final bool jueves;
  final bool viernes;
  final TimeOfDay horaInicio;
  final TimeOfDay horaFin;

  Materia({
    this.id,
    required this.nombre,
    this.aula,
    this.profesor,
    required this.color,
    required this.lunes,
    required this.martes,
    required this.miercoles,
    required this.jueves,
    required this.viernes,
    required this.horaInicio,
    required this.horaFin,
  });

  factory Materia.fromJson(Map<String, dynamic> json) {
    return Materia(
      id: json['id_materia'],
      nombre: json['nombre'],
      aula: json['aula'],
      profesor: json['profesor'],
      color: json['color'] ?? '#4CAF50',
      lunes: json['lunes'] ?? false,
      martes: json['martes'] ?? false,
      miercoles: json['miercoles'] ?? false,
      jueves: json['jueves'] ?? false,
      viernes: json['viernes'] ?? false,
      horaInicio: _parseTime(json['hora_inicio']),
      horaFin: _parseTime(json['hora_fin']),
    );
  }

  static TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String get diasTexto {
    final dias = <String>[];
    if (lunes) dias.add('Lun');
    if (martes) dias.add('Mar');
    if (miercoles) dias.add('Mié');
    if (jueves) dias.add('Jue');
    if (viernes) dias.add('Vie');
    return dias.join(', ');
  }
}

// ── Colores disponibles ──────────────────────────────────────────
const List<String> _coloresDisponibles = [
  '#4CAF50',
  '#2196F3',
  '#F44336',
  '#FF9800',
  '#9C27B0',
  '#00BCD4',
  '#E91E63',
  '#795548',
];

Color hexToColor(String hex) {
  return Color(int.parse(hex.replaceFirst('#', '0xFF')));
}

// ── Pantalla Principal ──────────────────────────────────────────
class MateriasScreen extends StatefulWidget {
  const MateriasScreen({super.key});

  @override
  State<MateriasScreen> createState() => _MateriasScreenState();
}

class _MateriasScreenState extends State<MateriasScreen> {
  List<Materia> _materias = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMaterias();
  }

  Future<void> _loadMaterias() async {
    setState(() => _isLoading = true);
    final result = await ApiService.getMaterias();
    setState(() => _isLoading = false);

    if (result['success']) {
      final List data = result['data'];
      setState(() {
        _materias = data.map((m) => Materia.fromJson(m)).toList();
      });
    }
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _showMateriaDialog({Materia? materia}) {
    // Guarda el contexto de la pantalla antes de abrir el modal
    final screenContext = context;

    final formKey = GlobalKey<FormState>();
    final nombreController = TextEditingController(text: materia?.nombre ?? '');
    final aulaController = TextEditingController(text: materia?.aula ?? '');
    final profesorController = TextEditingController(text: materia?.profesor ?? '');

    String colorSeleccionado = materia?.color ?? _coloresDisponibles[0];
    bool lunes = materia?.lunes ?? false;
    bool martes = materia?.martes ?? false;
    bool miercoles = materia?.miercoles ?? false;
    bool jueves = materia?.jueves ?? false;
    bool viernes = materia?.viernes ?? false;
    TimeOfDay horaInicio = materia?.horaInicio ?? const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay horaFin = materia?.horaFin ?? const TimeOfDay(hour: 10, minute: 0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        materia == null ? 'Nueva Materia' : 'Editar Materia',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: nombreController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Nombre de la materia *',
                      hintText: 'Ej: Programación Móvil',
                      prefixIcon: const Icon(Icons.book_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa el nombre' : null,
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: aulaController,
                          decoration: InputDecoration(
                            labelText: 'Aula',
                            hintText: 'Ej: A-101',
                            prefixIcon: const Icon(Icons.room_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: profesorController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Profesor',
                            hintText: 'Ej: Dr. López',
                            prefixIcon: const Icon(Icons.person_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text('Color de la materia',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    children: _coloresDisponibles.map((hex) {
                      final isSelected = colorSeleccionado == hex;
                      return GestureDetector(
                        onTap: () => setModalState(() => colorSeleccionado = hex),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: hexToColor(hex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.black : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white, size: 18)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  const Text('Días de la semana *',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _diaChip('L', lunes, colorSeleccionado, () => setModalState(() => lunes = !lunes)),
                      _diaChip('M', martes, colorSeleccionado, () => setModalState(() => martes = !martes)),
                      _diaChip('Mi', miercoles, colorSeleccionado, () => setModalState(() => miercoles = !miercoles)),
                      _diaChip('J', jueves, colorSeleccionado, () => setModalState(() => jueves = !jueves)),
                      _diaChip('V', viernes, colorSeleccionado, () => setModalState(() => viernes = !viernes)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const Text('Horario', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _timePickerButton(
                          label: 'Inicio',
                          time: horaInicio,
                          color: colorSeleccionado,
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: horaInicio);
                            if (picked != null) setModalState(() => horaInicio = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _timePickerButton(
                          label: 'Fin',
                          time: horaFin,
                          color: colorSeleccionado,
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: horaFin);
                            if (picked != null) setModalState(() => horaFin = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hexToColor(colorSeleccionado),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        if (!lunes && !martes && !miercoles && !jueves && !viernes) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Selecciona al menos un día'), backgroundColor: Colors.red),
                          );
                          return;
                        }

                        // Cierra el modal antes de hacer la petición
                        Navigator.pop(context);

                        final result = await ApiService.saveMateria(
                          nombre: nombreController.text.trim(),
                          aula: aulaController.text.trim().isEmpty ? null : aulaController.text.trim(),
                          profesor: profesorController.text.trim().isEmpty ? null : profesorController.text.trim(),
                          color: colorSeleccionado,
                          lunes: lunes,
                          martes: martes,
                          miercoles: miercoles,
                          jueves: jueves,
                          viernes: viernes,
                          horaInicio: '${horaInicio.hour.toString().padLeft(2, '0')}:${horaInicio.minute.toString().padLeft(2, '0')}',
                          horaFin: '${horaFin.hour.toString().padLeft(2, '0')}:${horaFin.minute.toString().padLeft(2, '0')}',
                        );

                        if (result['success']) {
                          await _loadMaterias();
                          if (mounted) {
                            ScaffoldMessenger.of(screenContext).showSnackBar(
                              const SnackBar(content: Text('Materia guardada'), backgroundColor: Colors.green),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(screenContext).showSnackBar(
                              SnackBar(content: Text(result['error']), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: Text(
                        materia == null ? 'Guardar Materia' : 'Actualizar Materia',
                        style: const TextStyle(fontSize: 16),
                      ),
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

  Widget _diaChip(String label, bool selected, String colorHex, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: selected ? hexToColor(colorHex) : Colors.grey.shade100,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? hexToColor(colorHex) : Colors.grey.shade300),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: selected ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _timePickerButton({
    required String label,
    required TimeOfDay time,
    required String color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, color: hexToColor(color), size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
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
        title: const Text('Mis Materias'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_materias.isNotEmpty)
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => HorarioScreen(materias: _materias)),
              ),
              icon: const Icon(Icons.calendar_month, color: Colors.white),
              label: const Text('Ver Horario', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMateriaDialog(),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Agregar Materia'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _materias.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.menu_book_outlined, size: 80, color: Colors.grey.shade200),
                      const SizedBox(height: 20),
                      const Text(
                        'Aún no tienes materias',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Registra tus materias del semestre\npara organizar tu horario',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () => _showMateriaDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Agregar mi primera materia'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _materias.length,
                  itemBuilder: (context, index) {
                    final materia = _materias[index];
                    final color = hexToColor(materia.color);

                    return Dismissible(
                      key: Key('${materia.id}_${materia.nombre}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                      onDismissed: (_) {
                        setState(() => _materias.removeAt(index));
                      },
                      child: GestureDetector(
                        onTap: () => _showMateriaDialog(materia: materia),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(16),
                                    bottomLeft: Radius.circular(16),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    materia.nombre[0].toUpperCase(),
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(materia.nombre,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey.shade500),
                                        const SizedBox(width: 4),
                                        Text(materia.diasTexto,
                                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                        const SizedBox(width: 12),
                                        Icon(Icons.access_time, size: 13, color: Colors.grey.shade500),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${_formatTime(materia.horaInicio)} - ${_formatTime(materia.horaFin)}',
                                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                        ),
                                      ],
                                    ),
                                    if (materia.aula != null || materia.profesor != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(
                                          children: [
                                            if (materia.aula != null) ...[
                                              Icon(Icons.room_outlined, size: 13, color: Colors.grey.shade500),
                                              const SizedBox(width: 4),
                                              Text(materia.aula!,
                                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                              const SizedBox(width: 12),
                                            ],
                                            if (materia.profesor != null) ...[
                                              Icon(Icons.person_outline, size: 13, color: Colors.grey.shade500),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  materia.profesor!,
                                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
