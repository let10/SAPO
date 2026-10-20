import 'package:flutter/material.dart';
import '../screens/pantalla_principal.dart';
import '../services/base_datos/repositorio_documentos.dart';

class App extends StatelessWidget {
  /// Base de datos local ya abierta, o `null` si no se pudo abrir (ver [errorBaseDatos]).
  final RepositorioDocumentos? repositorio;
  final String? errorBaseDatos;

  const App({super.key, this.repositorio, this.errorBaseDatos});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Procesador Documental MDP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A4B8C),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Segoe UI',
      ),
      home: PantallaPrincipal(repositorio: repositorio, errorBaseDatos: errorBaseDatos),
    );
  }
}
