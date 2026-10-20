import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Abre (y crea si no existe) la base de datos SQLite local de la aplicación y
/// deja lista su estructura. No contiene consultas de negocio: eso es de
/// `RepositorioDocumentos`.
class BaseDatosLocal {
  static const String nombreArchivo = 'procesador_documental_mdp.db';
  static const int _versionEsquema = 1;

  final Database conexion;
  final String ruta;

  BaseDatosLocal._(this.conexion, this.ruta);

  /// Carpeta de datos de la aplicación del usuario de Windows
  /// (`%APPDATA%\procesador_documental_mdp`). Es independiente de `build/` y
  /// sobrevive a recompilar o reinstalar la aplicación.
  static String carpetaDatos() {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return p.join(base, 'procesador_documental_mdp');
  }

  static String rutaPorDefecto() => p.join(carpetaDatos(), nombreArchivo);

  /// Abre la base en [ruta] (por defecto, la de la carpeta de datos de la
  /// aplicación). Crea la carpeta, el archivo y las tablas si todavía no existen.
  static BaseDatosLocal abrir({String? ruta}) {
    final destino = ruta ?? rutaPorDefecto();
    Directory(p.dirname(destino)).createSync(recursive: true);
    final bd = BaseDatosLocal._(sqlite3.open(destino), destino);
    bd._crearEsquema();
    return bd;
  }

  void _crearEsquema() {
    conexion.execute('''
      CREATE TABLE IF NOT EXISTS documentos (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        tipo_documento    TEXT    NOT NULL,
        nombre_completo   TEXT    NOT NULL,
        codigo            TEXT    NOT NULL,
        fecha_documento   TEXT    NOT NULL,
        articulo_primero  TEXT    NOT NULL,
        ruta_pdf          TEXT    NOT NULL,
        publicado         INTEGER NOT NULL DEFAULT 0 CHECK (publicado IN (0, 1)),
        fecha_publicacion TEXT,
        fecha_registro    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
      )
    ''');
    // Un mismo tipo de documento no puede repetir su código.
    conexion.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_documentos_tipo_codigo ON documentos (tipo_documento, codigo)');
    if (conexion.userVersion < _versionEsquema) conexion.userVersion = _versionEsquema;
  }

  void cerrar() => conexion.close();
}
