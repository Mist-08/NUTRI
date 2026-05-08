import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _baseUrl = 'http://localhost:8000';
  static String? _cachedToken;

  // Llama esto en main.dart antes de runApp para cargar el token guardado
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString('token');
  }

  static Future<void> setToken(String token) async {
    _cachedToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
  }

  static Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString('token');
    return _cachedToken;
  }

  static Future<void> clearToken() async {
    _cachedToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  static Future<Map<String, String>> get _authHeaders async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> register({
    required String nombre,
    required String correo,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: _headers,
        body: jsonEncode({
          'nombre': nombre,
          'correo': correo,
          'password': password,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': data['detail'] ?? 'Error al registrarse'};
      }
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar al servidor'};
    }
  }

  static Future<Map<String, dynamic>> login({
    required String correo,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/login'),
        headers: _headers,
        body: jsonEncode({
          'correo': correo,
          'password': password,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        await setToken(data['access_token']);
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': data['detail'] ?? 'Correo o contraseña incorrectos'};
      }
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar al servidor'};
    }
  }

  static Future<Map<String, dynamic>> savePerfil({
    required int edad,
    required double peso,
    required double altura,
    required String sexo,
    required String nivelActividad,
    required String objetivo,
    String? alergias,
    String? dieta,
    int? caloriasDiarias,
    String? condicionesMedicas,
  }) async {
    try {
      final headers = await _authHeaders;
      final response = await http.post(
        Uri.parse('$_baseUrl/usuarios/perfil'),
        headers: headers,
        body: jsonEncode({
          'edad': edad,
          'peso': peso,
          'altura': altura,
          'sexo': sexo,
          'nivel_actividad': nivelActividad,
          'objetivo': objetivo,
          'alergias': alergias,
          'dieta': dieta,
          'calorias_diarias': caloriasDiarias,
          'condiciones_medicas': condicionesMedicas,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': data['detail'] ?? 'Error al guardar perfil'};
      }
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar al servidor'};
    }
  }

  static Future<Map<String, dynamic>> getMaterias() async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/materias'),
        headers: headers,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': data['detail'] ?? 'Error'};
      }
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar al servidor'};
    }
  }

  static Future<Map<String, dynamic>> saveMateria({
    required String nombre,
    String? aula,
    String? profesor,
    required String color,
    required bool lunes,
    required bool martes,
    required bool miercoles,
    required bool jueves,
    required bool viernes,
    required String horaInicio,
    required String horaFin,
  }) async {
    try {
      final headers = await _authHeaders;
      final response = await http.post(
        Uri.parse('$_baseUrl/materias'),
        headers: headers,
        body: jsonEncode({
          'nombre': nombre,
          'aula': aula,
          'profesor': profesor,
          'color': color,
          'lunes': lunes,
          'martes': martes,
          'miercoles': miercoles,
          'jueves': jueves,
          'viernes': viernes,
          'hora_inicio': horaInicio,
          'hora_fin': horaFin,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': data['detail'] ?? 'Error'};
      }
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar al servidor'};
    }
  }

  static Future<Map<String, dynamic>> getEventos() async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/eventos'),
        headers: headers,
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': data['detail'] ?? 'Error'};
      }
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar al servidor'};
    }
  }

  static Future<Map<String, dynamic>> saveEvento({
    required String tipoEvento,
    required String fecha,
    required String horaInicio,
    String? horaFin,
    String? descripcion,
  }) async {
    try {
      final headers = await _authHeaders;
      final response = await http.post(
        Uri.parse('$_baseUrl/eventos'),
        headers: headers,
        body: jsonEncode({
          'tipo_evento': tipoEvento,
          'fecha': fecha,
          'hora_inicio': horaInicio,
          'hora_fin': horaFin,
          'descripcion': descripcion,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else {
        return {'success': false, 'error': data['detail'] ?? 'Error'};
      }
    } catch (e) {
      return {'success': false, 'error': 'No se pudo conectar al servidor'};
    }
  }
}
