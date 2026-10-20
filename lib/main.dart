import 'package:flutter/material.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'app/app.dart';
import 'services/base_datos/base_datos_local.dart';
import 'services/base_datos/repositorio_documentos.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxInitialize();

  // La base se abre (y se crea si no existe) al arrancar. Si falla, la app
  // sigue funcionando; solo el registro de documentos avisará del problema.
  RepositorioDocumentos? repositorio;
  String? errorBaseDatos;
  try {
    repositorio = RepositorioDocumentos(BaseDatosLocal.abrir());
  } catch (e) {
    errorBaseDatos = e.toString();
  }
  runApp(App(repositorio: repositorio, errorBaseDatos: errorBaseDatos));
}
