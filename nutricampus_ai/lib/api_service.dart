import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Tipos de error que distinguimos a nivel de UI.
enum ApiErrorType { timeout, network, unauthorized, notFound, server, unknown }

class ApiService {
  static const String _baseUrl = 'http://localhost:8000';
  static const Duration _timeout = Duration(seconds: 15);
  static String? _cachedToken;

  // ── Token ────────────────────────────────────────────────────

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

  // ── Helper central ────────────────────────────────────────────

  static Future<Map<String, dynamic>> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    bool auth = true,
    Set<int> successCodes = const {200, 201},
  }) async {
    try {
      final url = Uri.parse('$_baseUrl$path');
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (auth) {
        final token = await getToken();
        if (token == null || token.isEmpty) {
          return {
            'success': false,
            'error': 'Sesión no iniciada',
            'errorType': ApiErrorType.unauthorized,
          };
        }
        headers['Authorization'] = 'Bearer $token';
      }

      final encodedBody = body != null ? jsonEncode(body) : null;

      late http.Response response;
      switch (method) {
        case 'GET':
          response = await http.get(url, headers: headers).timeout(_timeout);
          break;
        case 'POST':
          response = await http
              .post(url, headers: headers, body: encodedBody)
              .timeout(_timeout);
          break;
        case 'PUT':
          response = await http
              .put(url, headers: headers, body: encodedBody)
              .timeout(_timeout);
          break;
        case 'DELETE':
          response =
              await http.delete(url, headers: headers).timeout(_timeout);
          break;
        default:
          throw ArgumentError('Método HTTP no soportado: $method');
      }

      if (successCodes.contains(response.statusCode)) {
        if (response.statusCode == 204 || response.body.isEmpty) {
          return {'success': true, 'statusCode': response.statusCode};
        }
        return {
          'success': true,
          'data': _safeDecode(response.body),
          'statusCode': response.statusCode,
        };
      }

      final decoded = _safeDecode(response.body);
      final detail = (decoded is Map && decoded['detail'] is String)
          ? decoded['detail'] as String
          : null;

      switch (response.statusCode) {
        case 401:
          return {
            'success': false,
            'error': detail ?? 'Sesión expirada, inicia sesión de nuevo',
            'errorType': ApiErrorType.unauthorized,
            'statusCode': 401,
          };
        case 404:
          return {
            'success': false,
            'error': detail ?? 'Recurso no encontrado',
            'errorType': ApiErrorType.notFound,
            'statusCode': 404,
            'notFound': true,
          };
        case 400:
        case 422:
          return {
            'success': false,
            'error': detail ?? 'Datos inválidos',
            'errorType': ApiErrorType.server,
            'statusCode': response.statusCode,
          };
        default:
          return {
            'success': false,
            'error': detail ??
                'Error del servidor (${response.statusCode}). Inténtalo de nuevo.',
            'errorType': ApiErrorType.server,
            'statusCode': response.statusCode,
          };
      }
    } on TimeoutException {
      return {
        'success': false,
        'error': 'El servidor tardó demasiado en responder',
        'errorType': ApiErrorType.timeout,
      };
    } on SocketException {
      return {
        'success': false,
        'error': 'Sin conexión. Revisa tu internet o si el servidor está activo',
        'errorType': ApiErrorType.network,
      };
    } on FormatException {
      return {
        'success': false,
        'error': 'Respuesta del servidor con formato inválido',
        'errorType': ApiErrorType.unknown,
      };
    } on Exception {
      // Catches ClientException (Flutter web), HttpException, and other
      // Exception subclasses not already handled above.
      return {
        'success': false,
        'error': 'Error de conexión. Verifica que el servidor esté activo.',
        'errorType': ApiErrorType.network,
      };
    } catch (_) {
      return {
        'success': false,
        'error': 'Ocurrió un error inesperado',
        'errorType': ApiErrorType.unknown,
      };
    }
  }

  static dynamic _safeDecode(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  // ── Autenticación ────────────────────────────────────────────

  static Future<Map<String, dynamic>> register({
    required String nombre,
    required String correo,
    required String password,
  }) {
    return _request(
      method: 'POST',
      path: '/auth/register',
      auth: false,
      body: {'nombre': nombre, 'correo': correo, 'password': password},
      successCodes: {201},
    );
  }

  static Future<Map<String, dynamic>> login({
    required String correo,
    required String password,
  }) async {
    final result = await _request(
      method: 'POST',
      path: '/auth/login',
      auth: false,
      body: {'correo': correo, 'password': password},
      successCodes: {200},
    );
    if (result['success'] == true && result['data'] is Map) {
      final token = result['data']['access_token'];
      if (token is String) await setToken(token);
    }
    return result;
  }

  // ── Usuario ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getMe() =>
      _request(method: 'GET', path: '/usuarios/me');

  // ── Perfil Nutricional ────────────────────────────────────────

  static Future<Map<String, dynamic>> getPerfil() =>
      _request(method: 'GET', path: '/usuarios/perfil');

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
    String? fechaNacimiento, // formato "YYYY-MM-DD" o null
  }) {
    return _request(
      method: 'POST',
      path: '/usuarios/perfil',
      body: {
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
        'fecha_nacimiento': fechaNacimiento,
      },
      successCodes: {201},
    );
  }

  // ── Materias ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getMaterias() =>
      _request(method: 'GET', path: '/materias');

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
  }) {
    return _request(
      method: 'POST',
      path: '/materias',
      body: {
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
      },
      successCodes: {201},
    );
  }

  static Future<Map<String, dynamic>> updateMateria({
    required int id,
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
  }) {
    return _request(
      method: 'PUT',
      path: '/materias/$id',
      body: {
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
      },
      successCodes: {200},
    );
  }

  static Future<Map<String, dynamic>> deleteMateria(int id) => _request(
        method: 'DELETE',
        path: '/materias/$id',
        successCodes: {204},
      );

  // ── Eventos ───────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getEventos() =>
      _request(method: 'GET', path: '/eventos');

  static Future<Map<String, dynamic>> saveEvento({
    required String tipoEvento,
    required String fecha,
    required String horaInicio,
    String? horaFin,
    String? descripcion,
  }) {
    return _request(
      method: 'POST',
      path: '/eventos',
      body: {
        'tipo_evento': tipoEvento,
        'fecha': fecha,
        'hora_inicio': horaInicio,
        'hora_fin': horaFin,
        'descripcion': descripcion,
      },
      successCodes: {201},
    );
  }

  static Future<Map<String, dynamic>> deleteEvento(int id) => _request(
        method: 'DELETE',
        path: '/eventos/$id',
        successCodes: {204},
      );

  // ── Recomendaciones ───────────────────────────────────────────

  /// Devuelve el menú del día. Si no existe lo genera automáticamente.
  static Future<Map<String, dynamic>> getMenuHoy({String? fecha}) => _request(
        method: 'GET',
        path: '/recommendations/today${fecha != null ? '?fecha=$fecha' : ''}',
      );

  /// Fuerza la generación de un menú nuevo (reemplaza el existente).
  static Future<Map<String, dynamic>> generateMenu({String? fecha}) => _request(
        method: 'POST',
        path: '/recommendations/generate',
        body: fecha != null ? {'fecha': fecha} : {},
        successCodes: {200, 201},
      );

  // ── Gestión de menús ──────────────────────────────────────────

  /// Historial de menús de los últimos [dias] días.
  static Future<Map<String, dynamic>> getHistorialMenus({int dias = 14}) => _request(
        method: 'GET',
        path: '/menus/history?dias=$dias',
      );

  /// Marca o desmarca un menú como consumido.
  static Future<Map<String, dynamic>> markConsumed(int idMenu, {bool consumido = true}) =>
      _request(
        method: 'POST',
        path: '/menus/$idMenu/consumed',
        body: {'consumido': consumido},
      );

  /// Elimina un menú del historial.
  static Future<Map<String, dynamic>> deleteMenu(int idMenu) => _request(
        method: 'DELETE',
        path: '/menus/$idMenu',
        successCodes: {204},
      );

  // ── Estadísticas ──────────────────────────────────────────────

  /// Estadísticas nutricionales de los últimos 7 días.
  static Future<Map<String, dynamic>> getNutritionStats() =>
      _request(method: 'GET', path: '/nutrition/stats');

  // ── Presupuesto ───────────────────────────────────────────────

  /// Obtiene la configuración de presupuesto del usuario.
  static Future<Map<String, dynamic>> getBudget() =>
      _request(method: 'GET', path: '/nutrition/budget');

  /// Actualiza el presupuesto del usuario.
  static Future<Map<String, dynamic>> updateBudget({
    double? presupuestoDiario,
    double? presupuestoSemanal,
    String? nivelPresupuesto,
    String? tipoMenuPreferido,
  }) =>
      _request(
        method: 'PUT',
        path: '/nutrition/budget',
        body: {
          'presupuesto_diario': presupuestoDiario,
          'presupuesto_semanal': presupuestoSemanal,
          'nivel_presupuesto': nivelPresupuesto,
          'tipo_menu_preferido': tipoMenuPreferido,
        },
      );

  /// Estadísticas de gasto alimentario de los últimos N días.
  static Future<Map<String, dynamic>> getBudgetStats({int dias = 7}) =>
      _request(method: 'GET', path: '/nutrition/budget-stats?dias=$dias');

  // ── Chatbot ───────────────────────────────────────────────────

  /// Envía un mensaje al chatbot y recibe una respuesta personalizada.
  static Future<Map<String, dynamic>> sendChatMessage(String message) =>
      _request(
        method: 'POST',
        path: '/chatbot/message',
        body: {'message': message},
      );

  /// Obtiene sugerencias de preguntas contextuales para el chatbot.
  static Future<Map<String, dynamic>> getChatSuggestions() =>
      _request(method: 'GET', path: '/chatbot/suggestions');

  /// Obtiene el contexto del usuario tal como lo ve el chatbot.
  static Future<Map<String, dynamic>> getChatContext() =>
      _request(method: 'GET', path: '/chatbot/context');
}
