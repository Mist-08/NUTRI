import 'package:flutter/material.dart';
import 'materias_screen.dart'; // Importa el modelo Materia y hexToColor

// ── Modelo Evento ───────────────────────────────────────────────
class EventoAcademico {
  final int? id;
  final String tipoEvento; // 'Examen' | 'Entrega'
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
}

// ── Pantalla de Horario ─────────────────────────────────────────
class HorarioScreen extends StatefulWidget {
  final List<Materia> materias;

  const HorarioScreen({super.key, required this.materias});

  @override
  State<HorarioScreen> createState() => _HorarioScreenState();
}

class _HorarioScreenState extends State<HorarioScreen> {
  DateTime _selectedDay = DateTime.now();
  DateTime _weekStart = _getWeekStart(DateTime.now());
  final List<EventoAcademico> _eventos = [];

  static DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  List<DateTime> get _weekDays =>
      List.generate(5, (i) => _weekStart.add(Duration(days: i)));

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
    if (weekday > 5) return [];
    return widget.materias.where((m) {
      switch (weekday) {
        case 1: return m.lunes;
        case 2: return m.martes;
        case 3: return m.miercoles;
        case 4: return m.jueves;
        case 5: return m.viernes;
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
    final formKey = GlobalKey<FormState>();
    final descController = TextEditingController();
    String tipo = 'Examen';
    DateTime fecha = _selectedDay;
    TimeOfDay horaInicio = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay? horaFin;
    bool sinHoraFin = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) => Padding(
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

                // Tipo
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
                              Icon(icons[t],
                                  color: isSelected ? Colors.white : c),
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

                // Descripción
                TextFormField(
                  controller: descController,
                  decoration: InputDecoration(
                    labelText: 'Descripción',
                    hintText: 'Ej: Examen parcial de Redes',
                    prefixIcon: const Icon(Icons.edit_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Ingresa una descripción' : null,
                ),
                const SizedBox(height: 12),

                // Fecha
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: fecha,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 30)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) setModal(() => fecha = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_outlined,
                          color: Colors.green),
                      const SizedBox(width: 12),
                      Text('${fecha.day}/${fecha.month}/${fecha.year}',
                          style: const TextStyle(fontSize: 16)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),

                // Horas
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
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('Inicio',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
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
                              color:
                                  sinHoraFin ? Colors.grey : Colors.green,
                              size: 18),
                          const SizedBox(width: 8),
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('Fin',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
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
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
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
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => _eventos.add(EventoAcademico(
                        tipoEvento: tipo,
                        fecha: fecha,
                        horaInicio: horaInicio,
                        horaFin: sinHoraFin ? null : horaFin,
                        descripcion: descController.text.trim(),
                      )));
                      Navigator.pop(context);
                      // TODO: POST /eventos
                    },
                    child: const Text('Guardar Evento',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const dayNames = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie'];
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
          // ── Selector semanal ───────────────────────────────
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
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
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
                    children: List.generate(5, (i) {
                      final day = _weekDays[i];
                      final isSelected = day.day == _selectedDay.day &&
                          day.month == _selectedDay.month;
                      final isToday = day.day == DateTime.now().day &&
                          day.month == DateTime.now().month;
                      final hasMateria =
                          _materiasDelDia(day).isNotEmpty;
                      final hasEvento = _eventosDelDia(day).isNotEmpty;

                      return GestureDetector(
                        onTap: () => setState(() => _selectedDay = day),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 54,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: isToday && !isSelected
                                ? Border.all(color: Colors.white54)
                                : null,
                          ),
                          child: Column(children: [
                            Text(dayNames[i],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected
                                      ? Colors.green
                                      : Colors.white70,
                                  fontWeight: FontWeight.w600,
                                )),
                            const SizedBox(height: 4),
                            Text('${day.day}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.green
                                      : Colors.white,
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
                                      color: isSelected
                                          ? Colors.green
                                          : Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                if (hasEvento)
                                  Container(
                                    width: 5, height: 5,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.red
                                          : Colors.red.shade200,
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

          // ── Contenido del día ──────────────────────────────
          Expanded(
            child: isWeekend
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.weekend_outlined,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('¡Es fin de semana!',
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey.shade500)),
                      ],
                    ),
                  )
                : (materiasHoy.isEmpty && eventosHoy.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.event_available_outlined,
                                size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('Sin actividades este día',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
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
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05),
              blurRadius: 6, offset: const Offset(0, 2))
        ],
      ),
      child: Row(children: [
        Container(
          width: 6, height: 72,
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
          width: 42, height: 42,
          decoration: BoxDecoration(
              color: color.withOpacity(0.15), shape: BoxShape.circle),
          child: Center(
            child: Text(m.nombre[0].toUpperCase(),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: color)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(m.nombre,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 3),
            Row(children: [
              Icon(Icons.access_time,
                  size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                '${_formatTime(m.horaInicio)} - ${_formatTime(m.horaFin)}',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
              if (m.aula != null) ...[
                const SizedBox(width: 10),
                Icon(Icons.room_outlined,
                    size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(m.aula!,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600)),
              ],
            ]),
          ]),
        ),
        const SizedBox(width: 12),
      ]),
    );
  }

  Widget _eventoCard(EventoAcademico e) {
    final color = e.tipoEvento == 'Examen'
        ? Colors.red.shade600
        : Colors.orange.shade600;
    final icon = e.tipoEvento == 'Examen'
        ? Icons.assignment_outlined
        : Icons.upload_file_outlined;

    return Dismissible(
      key: Key('${e.descripcion}_${e.fecha}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      onDismissed: (_) {
        setState(() => _eventos.remove(e));
        // TODO: DELETE /eventos/{id}
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05),
                blurRadius: 6, offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Container(
            width: 6, height: 72,
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
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(e.descripcion,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(e.tipoEvento,
                      style: TextStyle(
                          fontSize: 10,
                          color: color,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Icon(Icons.access_time,
                    size: 12, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text(
                  e.horaFin != null
                      ? '${_formatTime(e.horaInicio)} - ${_formatTime(e.horaFin!)}'
                      : _formatTime(e.horaInicio),
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 12),
        ]),
      ),
    );
  }
}
