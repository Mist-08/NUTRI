import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'home_screen.dart';
import 'materias_screen.dart';
import 'horario_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NutriCampus AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login':    (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home':     (context) => const HomeScreen(),
        '/materias': (context) => const MateriasScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/horario') {
          final materias = settings.arguments as List<Materia>;
          return MaterialPageRoute(
            builder: (_) => HorarioScreen(materias: materias),
          );
        }
        return null;
      },
    );
  }
}
