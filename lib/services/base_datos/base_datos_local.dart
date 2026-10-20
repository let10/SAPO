import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Abre (y crea si no existe) la base de datos SQLite local de la aplicación y
/// deja lista su estructura. No contiene consultas de negocio: eso es de
/// `RepositorioDocumentos`.
class BaseDatosLocal {
  static const String nombreArchivo = 'procesador_documental_mdp.db';
  static const int _versionEsquema = 2;

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
        publicado         INTEGER NOT NULL DEFAULT 1 CHECK (publicado IN (0, 1)),
        fecha_publicacion TEXT,
        fecha_recepcion   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d', 'now', 'localtime'))
      )
    ''');
    // Un mismo tipo de documento no puede repetir su código.
    conexion.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_documentos_tipo_codigo ON documentos (tipo_documento, codigo)',
    );
    _asegurarFechaRecepcion();
    if (conexion.userVersion < _versionEsquema) {
      conexion.userVersion = _versionEsquema;
    }
  }

  /// Las bases ya creadas guardaban el alta en `fecha_registro` (fecha y hora).
  /// Esa columna es la fecha de recepción: se renombra y se deja solo el día
  /// `AAAA-MM-DD`. `fecha_publicacion` se conserva y no se usa.
  void _asegurarFechaRecepcion() {
    final columnas = _nombresColumnas();
    if (columnas.contains('fecha_registro') && !columnas.contains('fecha_recepcion')) {
      conexion.execute('ALTER TABLE documentos RENAME COLUMN fecha_registro TO fecha_recepcion');
    }
    conexion.execute('''
      UPDATE documentos
      SET fecha_recepcion = substr(fecha_recepcion, 1, 10)
      WHERE fecha_recepcion IS NOT NULL AND length(fecha_recepcion) > 10
    ''');
  }

  Set<String> _nombresColumnas() {
    final filas = conexion.select('PRAGMA table_info(documentos)');
    return {for (final f in filas) f['name'] as String};
  }

  void cerrar() => conexion.close();
}
