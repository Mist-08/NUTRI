import 'package:flutter/material.dart';
import 'materias_screen.dart';
import 'api_service.dart';

class EventoAcademico {
  final int? id;
  final String tipoEvento;
  final DateTime fecha;
  final TimeOfDay horaInicio;
  final TimeOfDay? horaFin;
  final String descripcion;

  EventoAcademico({
    this.id,
    required this.tipoEvento,
    required this.fecha,
    required this.horaInicio,
    this.horaFin,
    required this.descripcion,
  });

  factory EventoAcademico.fromJson(Map<String, dynamic> json) {
    return EventoAcademico(
      id: json['id_evento'],
      tipoEvento: json['tipo_evento'],
      fecha: DateTime.parse(json['fecha']),
      horaInicio: _parseTime(json['hora_inicio']),
      horaFin: json['hora_fin'] != null ? _parseTime(json['hora_fin']) : null,
      descripcion: json['descripcion'] ?? '',
    );
  }

  static TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }
}

class HorarioScreen extends StatefulWidget {
  final List<Materia> materias;

  const HorarioScreen({super.key, required this.materias});

  @override
  State<HorarioScreen> createState() => _HorarioScreenState();
}

class _HorarioScreenState extends State<HorarioScreen> {
  DateTime _selectedDay = DateTime.now();
  DateTime _weekStart = _getWeekStart(DateTime.now());
  List<EventoAcademico> _eventos = [];

  /// `true` cuando el usuario tocó explícitamente un día del calendario
  /// semanal o cuando el día visible coincide con HOY. Solo entonces
  /// preseleccionamos la fecha en el modal de evento.
  bool _userPickedDay = false;

  /// Vista actual: 'week' (calendario semanal) o 'all' (lista cronológica).
  String _viewMode = 'week';

  @override
  void initState() {
    super.initState();
    _loadEventos();
  }

  Future<void> _loadEventos() async {
    final result = await ApiService.getEventos();
    if (result['success']) {
      final List data = result['data'];
      setState(() {
        _eventos = data.map((e) => EventoAcademico.fromJson(e)).toList();
      });
    }
  }

  Future<void> _deleteEvento(EventoAcademico evento) async {
    if (evento.id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar evento'),
        content: Text('¿Seguro que deseas eliminar "${evento.descripcion}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      await _loadEventos();
      return;
    }

    final result = await ApiService.deleteEvento(evento.id!);
    if (result['success']) {
      setState(() => _eventos.remove(evento));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Evento eliminado'), backgroundColor: Colors.green),
        );
      }
    } else {
      await _loadEventos();
    }
  }

  static DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  List<DateTime> get _weekDays =>
      List.generate(7, (i) => _weekStart.add(Duration(days: i)));

  void _previousWeek() =>
      setState(() => _weekStart = _weekStart.subtract(const Duration(days: 7)));
  void _nextWeek() =>
      setState(() => _weekStart = _weekStart.add(const Duration(days: 7)));

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime d) {
    const m = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
    return '${d.day} ${m[d.month - 1]}';
  }

  List<Materia> _materiasDelDia(DateTime day) {
    final weekday = day.weekday;
    return widget.materias.where((m) {
      switch (weekday) {
        case 1: return m.lunes;
        case 2: return m.martes;
        case 3: return m.miercoles;
        case 4: return m.jueves;
        case 5: return m.viernes;
        // Sábado y domingo: las materias regulares no tienen flag para
        // esos días, así que esta lista será vacía. Pero los EVENTOS sí
        // pueden caer en fin de semana (concursos, clases de reposición).
        default: return false;
      }
    }).toList()
      ..sort((a, b) => a.horaInicio.hour.compareTo(b.horaInicio.hour));
  }

  List<EventoAcademico> _eventosDelDia(DateTime day) {
    return _eventos.where((e) =>
        e.fecha.year == day.year &&
        e.fecha.month == day.month &&
        e.fecha.day == day.day).toList()
      ..sort((a, b) => a.horaInicio.hour.compareTo(b.horaInicio.hour));
  }

  void _showAddEventDialog() {
    final screenContext = context;
    final formKey = GlobalKey<FormState>();
    final descController = TextEditingController();
    String tipo = 'Examen';

    // ── Fecha: preseleccionada si el usuario tocó un día ────────
    // Si el usuario eligió un día en el calendario semanal (o si el
    // día visible es HOY de forma natural), preseleccionamos la fecha.
    // Si está viendo una semana futura sin haber tocado nada → null,
    // así no se guarda una fecha que el usuario no eligió.
    final today = DateTime.now();
    final selectedIsToday = _selectedDay.year == today.year &&
        _selectedDay.month == today.month &&
        _selectedDay.day == today.day;
    DateTime? fecha =
        (_userPickedDay || selectedIsToday) ? _selectedDay : null;
    bool fechaTouched = false; // controla cuándo mostrar el error visual

    TimeOfDay horaInicio = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay? horaFin;
    bool sinHoraFin = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) {
          final fechaFaltante = fechaTouched && fecha == null;
          final fechaBorderColor = fechaFaltante
              ? Colors.red
              : (fecha == null ? Colors.grey.shade400 : Colors.green);
          final fechaTextColor =
              fecha == null ? Colors.grey.shade500 : Colors.black87;

          return Padding(
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Agregar Evento',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: ['Examen', 'Entrega'].map((t) {
                      final colors = {
                        'Examen': Colors.red.shade600,
                        'Entrega': Colors.orange.shade600
                      };
                      final icons = {
                        'Examen': Icons.assignment_outlined,
                        'Entrega': Icons.upload_file_outlined
                      };
                      final isSelected = tipo == t;
                      final c = colors[t]!;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setModal(() => tipo = t),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? c : c.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: c, width: isSelected ? 2 : 1),
                              ),
                              child: Column(children: [
                                Icon(icons[t], color: isSelected ? Colors.white : c),
                                const SizedBox(height: 4),
                                Text(t, style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13,
                                  color: isSelected ? Colors.white : c,
                                )),
                              ]),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: descController,
                    decoration: InputDecoration(
                      labelText: 'Descripción',
                      hintText: 'Ej: Examen parcial de Redes',
                      prefixIcon: const Icon(Icons.edit_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Ingresa una descripción' : null,
                  ),
                  const SizedBox(height: 12),

                  // ── Campo de FECHA (obligatorio) ──────────────────
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: fecha ?? DateTime.now(),
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setModal(() {
                          fecha = picked;
                          fechaTouched = true;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: fechaBorderColor,
                          width: fechaFaltante ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today_outlined,
                            color: fechaFaltante
                                ? Colors.red
                                : Colors.green),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            fecha == null
                                ? 'Selecciona una fecha *'
                                : '${fecha!.day}/${fecha!.month}/${fecha!.year}',
                            style: TextStyle(
                              fontSize: 16,
                              color: fechaTextColor,
                              fontWeight: fecha == null
                                  ? FontWeight.normal
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_drop_down,
                            color: Colors.grey.shade500),
                      ]),
                    ),
                  ),
                  if (fechaFaltante)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 12),
                      child: Text(
                        'Debes seleccionar una fecha',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),

                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          final p = await showTimePicker(
                              context: context, initialTime: horaInicio);
                          if (p != null) setModal(() => horaInicio = p);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            const Icon(Icons.access_time,
                                color: Colors.green, size: 18),
                            const SizedBox(width: 8),
                            Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Inicio',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey)),
                                  Text(_formatTime(horaInicio),
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                ]),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: sinHoraFin
                            ? null
                            : () async {
                                final p = await showTimePicker(
                                  context: context,
                                  initialTime: horaFin ??
                                      const TimeOfDay(hour: 11, minute: 0),
                                );
                                if (p != null) setModal(() => horaFin = p);
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: sinHoraFin ? Colors.grey.shade100 : null,
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(children: [
                            Icon(Icons.access_time_filled,
                                color: sinHoraFin
                                    ? Colors.grey
                                    : Colors.green,
                                size: 18),
                            const SizedBox(width: 8),
                            Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Fin',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey)),
                                  Text(
                                    horaFin != null
                                        ? _formatTime(horaFin!)
                                        : '--:--',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: sinHoraFin ? Colors.grey : null,
                                    ),
                                  ),
                                ]),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                  Row(children: [
                    Checkbox(
                      value: sinHoraFin,
                      activeColor: Colors.green,
                      onChanged: (v) => setModal(() {
                        sinHoraFin = v ?? false;
                        if (sinHoraFin) horaFin = null;
                      }),
                    ),
                    const Text('Sin hora de fin',
                        style:
                            TextStyle(fontSize: 13, color: Colors.grey)),
                  ]),
                  const SizedBox(height: 16),

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
                      onPressed: () async {
                        // Validamos el form (descripción)
                        final formOk =
                            formKey.currentState?.validate() ?? false;

                        // Validamos la fecha por separado y marcamos como
                        // "touched" para que se vea el error visualmente.
                        setModal(() => fechaTouched = true);

                        if (!formOk || fecha == null) return;

                        Navigator.pop(context);

                        final result = await ApiService.saveEvento(
                          tipoEvento: tipo,
                          fecha:
                              '${fecha!.year}-${fecha!.month.toString().padLeft(2, '0')}-${fecha!.day.toString().padLeft(2, '0')}',
                          horaInicio: _formatTime(horaInicio),
                          horaFin: sinHoraFin
                              ? null
                              : (horaFin != null
                                  ? _formatTime(horaFin!)
                                  : null),
                          descripcion: descController.text.trim(),
                        );

                        if (result['success']) {
                          await _loadEventos();
                          // ── Saltar a la semana/día del evento guardado ──
                          // Así el usuario ve inmediatamente el evento que
                          // acaba de crear, aunque haya cambiado de fecha
                          // dentro del modal.
                          if (mounted) {
                            setState(() {
                              _selectedDay = fecha!;
                              _weekStart = _getWeekStart(fecha!);
                              _userPickedDay = true;
                            });
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(screenContext)
                                .showSnackBar(
                              const SnackBar(
                                  content: Text('Evento guardado'),
                                  backgroundColor: Colors.green),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(screenContext)
                                .showSnackBar(
                              SnackBar(
                                  content: Text(result['error']),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: const Text('Guardar Evento',
                          style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    final materiasHoy = _materiasDelDia(_selectedDay);
    final eventosHoy = _eventosDelDia(_selectedDay);
    final isWeekend = _selectedDay.weekday > 5;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Horario'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddEventDialog,
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Agregar Evento'),
      ),
      body: Column(
        children: [
          // ── Toggle: Semana / Todos ───────────────────────────
          _buildViewToggle(),
          Expanded(
            child: _viewMode == 'week'
                ? _buildWeekView(dayNames, materiasHoy, eventosHoy, isWeekend)
                : _buildAllEventsView(),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _toggleButton('week', 'Semana', Icons.calendar_view_week),
          ),
          Expanded(
            child: _toggleButton('all', 'Todos', Icons.list_alt_rounded),
          ),
        ],
      ),
    );
  }

  Widget _toggleButton(String mode, String label, IconData icon) {
    final selected = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: selected ? Colors.green : Colors.grey.shade600),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.green : Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekView(
    List<String> dayNames,
    List<Materia> materiasHoy,
    List<EventoAcademico> eventosHoy,
    bool isWeekend,
  ) {
    return Column(
      children: [
          Container(
            color: Colors.green,
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white),
                      onPressed: _previousWeek,
                    ),
                    Text(
                      '${_formatDate(_weekStart)} — ${_formatDate(_weekDays.last)} ${_weekStart.year}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white),
                      onPressed: _nextWeek,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(7, (i) {
                      final day = _weekDays[i];
                      final isSelected = day.day == _selectedDay.day && day.month == _selectedDay.month;
                      final isToday = day.day == DateTime.now().day && day.month == DateTime.now().month;
                      final hasMateria = _materiasDelDia(day).isNotEmpty;
                      final hasEvento = _eventosDelDia(day).isNotEmpty;
                      final isWeekendDay = day.weekday > 5;

                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedDay = day;
                          _userPickedDay = true;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: isToday && !isSelected ? Border.all(color: Colors.white54) : null,
                          ),
                          child: Column(children: [
                            Text(dayNames[i], style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? (isWeekendDay ? Colors.amber.shade800 : Colors.green)
                                  : (isWeekendDay ? Colors.white.withOpacity(0.55) : Colors.white70),
                              fontWeight: FontWeight.w600,
                            )),
                            const SizedBox(height: 4),
                            Text('${day.day}', style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? (isWeekendDay ? Colors.amber.shade800 : Colors.green)
                                  : (isWeekendDay ? Colors.white.withOpacity(0.7) : Colors.white),
                            )),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (hasMateria)
                                  Container(
                                    width: 5, height: 5,
                                    margin: const EdgeInsets.only(right: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.green : Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                if (hasEvento)
                                  Container(
                                    width: 5, height: 5,
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.red : Colors.red.shade200,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                          ]),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: (materiasHoy.isEmpty && eventosHoy.isEmpty)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isWeekend
                              ? Icons.weekend_outlined
                              : Icons.event_available_outlined,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isWeekend
                              ? 'Fin de semana sin actividades'
                              : 'Sin actividades este día',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey.shade500),
                        ),
                        if (isWeekend) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Puedes agregar eventos académicos\ncon el botón de abajo',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade400),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Banner amarillo cuando se está viendo sábado o domingo
                      if (isWeekend) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.amber.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.weekend_outlined,
                                  color: Colors.amber[800], size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _selectedDay.weekday == 6
                                      ? 'Es sábado — actividades de fin de semana'
                                      : 'Es domingo — actividades de fin de semana',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.amber[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (materiasHoy.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('Clases',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.grey)),
                        ),
                        ...materiasHoy.map((m) => _materiaCard(m)),
                      ],
                      if (eventosHoy.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.only(
                              top: materiasHoy.isNotEmpty ? 16 : 0,
                              bottom: 8),
                          child: const Text('Eventos',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.grey)),
                        ),
                        ...eventosHoy.map((e) => _eventoCard(e)),
                      ],
                      const SizedBox(height: 80),
                    ],
                  ),
          ),
        ],
      );
  }

  /// Vista cronológica: todos los eventos ordenados por fecha,
  /// agrupados en "Próximos" y "Pasados".
  Widget _buildAllEventsView() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final eventosOrdenados = [..._eventos]..sort((a, b) {
        final cmp = a.fecha.compareTo(b.fecha);
        if (cmp != 0) return cmp;
        // Mismo día → ordenar por hora de inicio
        final aMin = a.horaInicio.hour * 60 + a.horaInicio.minute;
        final bMin = b.horaInicio.hour * 60 + b.horaInicio.minute;
        return aMin.compareTo(bMin);
      });

    final proximos = eventosOrdenados.where((e) {
      final d = DateTime(e.fecha.year, e.fecha.month, e.fecha.day);
      return !d.isBefore(today);
    }).toList();

    final pasados = eventosOrdenados.where((e) {
      final d = DateTime(e.fecha.year, e.fecha.month, e.fecha.day);
      return d.isBefore(today);
    }).toList().reversed.toList(); // pasados: más reciente primero

    if (_eventos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              'Aún no tienes eventos',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 6),
            Text(
              'Agrega exámenes o entregas con el botón de abajo',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (proximos.isNotEmpty) ...[
          _seccionHeader('Próximos', proximos.length),
          ...proximos.map((e) => _eventoCardConFecha(e, isPast: false)),
        ],
        if (pasados.isNotEmpty) ...[
          const SizedBox(height: 20),
          _seccionHeader('Pasados', pasados.length),
          ...pasados.map((e) => _eventoCardConFecha(e, isPast: true)),
        ],
      ],
    );
  }

  Widget _seccionHeader(String titulo, int cantidad) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4, left: 4),
      child: Row(
        children: [
          Text(
            titulo,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF1A1A2E),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$cantidad',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFechaCompleta(DateTime d) {
    const dias = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const meses = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
    ];
    final hoy = DateTime.now();
    final esHoy = d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;
    final manana = hoy.add(const Duration(days: 1));
    final esManana = d.year == manana.year &&
        d.month == manana.month &&
        d.day == manana.day;
    if (esHoy) return 'Hoy · ${d.day} ${meses[d.month - 1]}';
    if (esManana) return 'Mañana · ${d.day} ${meses[d.month - 1]}';
    return '${dias[d.weekday - 1]} · ${d.day} ${meses[d.month - 1]} ${d.year}';
  }

  /// Variante del evento que también muestra la fecha (para la vista "Todos").
  Widget _eventoCardConFecha(EventoAcademico e, {required bool isPast}) {
    final baseColor =
        e.tipoEvento == 'Examen' ? Colors.red.shade600 : Colors.orange.shade600;
    final icon = e.tipoEvento == 'Examen'
        ? Icons.assignment_outlined
        : Icons.upload_file_outlined;
    final color = isPast ? Colors.grey.shade500 : baseColor;
    final opacity = isPast ? 0.65 : 1.0;

    return GestureDetector(
      onLongPress: () => _deleteEvento(e),
      child: Opacity(
        opacity: opacity,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 88,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.descripcion,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            e.tipoEvento,
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.calendar_today_outlined,
                            size: 11, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _formatFechaCompleta(e.fecha),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 11, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          e.horaFin != null
                              ? '${_formatTime(e.horaInicio)} - ${_formatTime(e.horaFin!)}'
                              : _formatTime(e.horaInicio),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }


  Widget _materiaCard(Materia m) {
    final color = hexToColor(m.color);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 6, height: 72,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
          ),
        ),
        const SizedBox(width: 14),
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
          child: Center(
            child: Text(m.nombre[0].toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: color)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.nombre, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text('${_formatTime(m.horaInicio)} - ${_formatTime(m.horaFin)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              if (m.aula != null) ...[
                const SizedBox(width: 10),
                Icon(Icons.room_outlined, size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(m.aula!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ]),
          ]),
        ),
        const SizedBox(width: 12),
      ]),
    );
  }

  Widget _eventoCard(EventoAcademico e) {
    final color = e.tipoEvento == 'Examen' ? Colors.red.shade600 : Colors.orange.shade600;
    final icon = e.tipoEvento == 'Examen' ? Icons.assignment_outlined : Icons.upload_file_outlined;

    return Dismissible(
      key: Key('evento_${e.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async => false,
      onDismissed: (_) {},
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      child: GestureDetector(
        onLongPress: () => _deleteEvento(e),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.3)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Container(
              width: 6, height: 72,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), bottomLeft: Radius.circular(14)),
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.descripcion, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text(e.tipoEvento,
                        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(
                    e.horaFin != null
                        ? '${_formatTime(e.horaInicio)} - ${_formatTime(e.horaFin!)}'
                        : _formatTime(e.horaInicio),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
          ]),
        ),
      ),
    );
  }
}
