import 'package:sqlite3/sqlite3.dart';

import '../../models/documento_almacenado.dart';
import 'base_datos_local.dart';

/// Resultado de intentar registrar un documento.
class ResultadoRegistro {
  /// El documento quedó guardado.
  final bool registrado;

  /// Ya existía un documento con el mismo tipo y código; no se guardó nada.
  final bool duplicado;

  /// El documento guardado (con su `id`) o, si era duplicado, el que ya existía.
  final DocumentoAlmacenado documento;

  const ResultadoRegistro._(this.registrado, this.duplicado, this.documento);

  const ResultadoRegistro.registrado(DocumentoAlmacenado d)
    : this._(true, false, d);
  const ResultadoRegistro.duplicado(DocumentoAlmacenado existente)
    : this._(false, true, existente);
}

/// Operaciones sobre la tabla `documentos`. Toda consulta SQL de la aplicación
/// vive aquí; la interfaz no la toca.
class RepositorioDocumentos {
  final BaseDatosLocal _bd;

  RepositorioDocumentos(this._bd);

  static String _normalizarTipo(String t) =>
      t.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
  static String _normalizarCodigo(String c) => c.trim();

  /// Guarda el documento si no hay otro con el mismo `tipo_documento` y
  /// `codigo`. Nunca borra ni sobrescribe un registro existente. Al guardar, el
  /// documento queda como NO publicado y sin fecha de publicación.
  ResultadoRegistro registrar(DocumentoAlmacenado d) {
    final tipo = _normalizarTipo(d.tipoDocumento);
    final codigo = _normalizarCodigo(d.codigo);

    final existente = _buscar(tipo, codigo);
    if (existente != null) return ResultadoRegistro.duplicado(existente);

    try {
      _bd.conexion.execute(
        'INSERT INTO documentos '
        '(tipo_documento, nombre_completo, codigo, fecha_documento, articulo_primero, ruta_pdf, publicado, fecha_publicacion) '
        'VALUES (?, ?, ?, ?, ?, ?, 0, NULL)',
        [
          tipo,
          d.nombreCompleto.trim(),
          codigo,
          d.fechaDocumento,
          d.articuloPrimero.trim(),
          d.rutaPdf,
        ],
      );
    } on SqliteException catch (e) {
      // El índice único es la defensa final si dos registros llegaran a la vez.
      final ya = _buscar(tipo, codigo);
      if (ya != null) return ResultadoRegistro.duplicado(ya);
      throw StateError(
        'No se pudo guardar el documento en la base de datos: ${e.message}',
      );
    }
    return ResultadoRegistro.registrado(porId(_bd.conexion.lastInsertRowId)!);
  }

  DocumentoAlmacenado? porId(int id) {
    final r = _bd.conexion.select('SELECT * FROM documentos WHERE id = ?', [
      id,
    ]);
    return r.isEmpty ? null : _desdeFila(r.first);
  }

  /// Busca por código. Si hay varios tipos con el mismo código (p. ej. 144 de
  /// Gerencia Municipal y 144 de una Subgerencia), indique [tipoDocumento].
  DocumentoAlmacenado? porCodigo(String codigo, {String? tipoDocumento}) {
    final r = tipoDocumento == null
        ? _bd.conexion.select(
            'SELECT * FROM documentos WHERE codigo = ? ORDER BY id LIMIT 1',
            [_normalizarCodigo(codigo)],
          )
        : _bd.conexion.select(
            'SELECT * FROM documentos WHERE tipo_documento = ? AND codigo = ?',
            [_normalizarTipo(tipoDocumento), _normalizarCodigo(codigo)],
          );
    return r.isEmpty ? null : _desdeFila(r.first);
  }

  bool existe(String tipoDocumento, String codigo) =>
      _buscar(_normalizarTipo(tipoDocumento), _normalizarCodigo(codigo)) !=
      null;

  /// Reemplaza los datos confirmados de un documento ya registrado (nombre,
  /// código, fecha, artículo y ruta). No toca publicación ni fecha de registro.
  /// Lanza [StateError] si otro registro ya usa el mismo tipo y código.
  void actualizarDatosConfirmados(int id, DocumentoAlmacenado d) {
    final tipo = _normalizarTipo(d.tipoDocumento);
    final codigo = _normalizarCodigo(d.codigo);
    final otro = _buscar(tipo, codigo);
    if (otro != null && otro.id != id) {
      throw StateError(
        'Ya existe otro documento registrado con el mismo tipo y código.',
      );
    }
    try {
      _bd.conexion.execute(
        'UPDATE documentos SET tipo_documento = ?, nombre_completo = ?, codigo = ?, '
        'fecha_documento = ?, articulo_primero = ?, ruta_pdf = ? WHERE id = ?',
        [
          tipo,
          d.nombreCompleto.trim(),
          codigo,
          d.fechaDocumento,
          d.articuloPrimero.trim(),
          d.rutaPdf,
          id,
        ],
      );
    } on SqliteException catch (e) {
      throw StateError(
        'No se pudo actualizar el documento en la base de datos: ${e.message}',
      );
    }
  }

  DocumentoAlmacenado? _buscar(String tipo, String codigo) {
    final r = _bd.conexion.select(
      'SELECT * FROM documentos WHERE tipo_documento = ? AND codigo = ?',
      [tipo, codigo],
    );
    return r.isEmpty ? null : _desdeFila(r.first);
  }

  static DocumentoAlmacenado _desdeFila(Row f) => DocumentoAlmacenado(
    id: f['id'] as int,
    tipoDocumento: f['tipo_documento'] as String,
    nombreCompleto: f['nombre_completo'] as String,
    codigo: f['codigo'] as String,
    fechaDocumento: f['fecha_documento'] as String,
    articuloPrimero: f['articulo_primero'] as String,
    rutaPdf: f['ruta_pdf'] as String,
    publicado: (f['publicado'] as int) == 1,
    fechaPublicacion: f['fecha_publicacion'] == null
        ? null
        : DateTime.parse(f['fecha_publicacion'] as String),
    fechaRegistro: DateTime.parse(f['fecha_registro'] as String),
  );
}
