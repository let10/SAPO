import 'package:sqlite3/sqlite3.dart';

import '../../models/documento_almacenado.dart';
import '../../utils/texto_utils.dart';
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

  /// Día local `AAAA-MM-DD`. La recepción se fija al insertar y no la escribe el usuario.
  static String _hoyLocalIso() {
    final n = DateTime.now();
    String dos(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${dos(n.month)}-${dos(n.day)}';
  }

  /// Guarda el documento si no hay otro con el mismo `tipo_documento` y
  /// `codigo`. Nunca borra ni sobrescribe un registro existente. Al guardar, el
  /// documento queda publicado (ya se publicó en la web municipal y en gob.pe)
  /// y con la fecha de recepción de hoy. Pasarlo a no publicado es una
  /// corrección posterior, con [marcarPublicado].
  ResultadoRegistro registrar(DocumentoAlmacenado d) {
    final tipo = _normalizarTipo(d.tipoDocumento);
    final codigo = _normalizarCodigo(d.codigo);

    final existente = _buscar(tipo, codigo);
    if (existente != null) return ResultadoRegistro.duplicado(existente);

    try {
      _bd.conexion.execute(
        'INSERT INTO documentos '
        '(tipo_documento, nombre_completo, codigo, fecha_documento, articulo_primero, ruta_pdf, publicado, fecha_recepcion) '
        'VALUES (?, ?, ?, ?, ?, ?, 1, ?)',
        [
          tipo,
          d.nombreCompleto.trim(),
          codigo,
          d.fechaDocumento,
          d.articuloPrimero.trim(),
          d.rutaPdf,
          _hoyLocalIso(),
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

  /// Documentos registrados, del más reciente al más antiguo según la fecha de
  /// recepción. [tipoDocumento] y [publicado] acotan el listado.
  List<DocumentoAlmacenado> listar({String? tipoDocumento, bool? publicado}) =>
      _consultar(tipoDocumento: tipoDocumento, publicado: publicado);

  /// Busca por código o por nombre completo. La comparación ignora mayúsculas
  /// y tildes. Se puede combinar con los mismos filtros de [listar].
  List<DocumentoAlmacenado> buscar(
    String texto, {
    String? tipoDocumento,
    bool? publicado,
  }) => _consultar(tipoDocumento: tipoDocumento, publicado: publicado, texto: texto);

  /// Marca el documento como publicado (`true`) o no publicado (`false`).
  /// No modifica la fecha de recepción. Lanza [StateError] si el id no existe.
  void marcarPublicado(int id, bool publicado) {
    if (porId(id) == null) {
      throw StateError('No hay un documento registrado con id $id.');
    }
    _bd.conexion.execute('UPDATE documentos SET publicado = ? WHERE id = ?', [
      publicado ? 1 : 0,
      id,
    ]);
  }

  /// Reemplaza los datos confirmados de un documento ya registrado (nombre,
  /// código, fecha del documento, artículo y ruta). No toca la publicación ni
  /// la fecha de recepción. Lanza [StateError] si otro registro ya usa el mismo
  /// tipo y código.
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

  List<DocumentoAlmacenado> _consultar({
    String? tipoDocumento,
    bool? publicado,
    String? texto,
  }) {
    final where = <String>[];
    final args = <Object>[];
    if (tipoDocumento != null && tipoDocumento.trim().isNotEmpty) {
      where.add('tipo_documento = ?');
      args.add(_normalizarTipo(tipoDocumento));
    }
    if (publicado != null) {
      where.add('publicado = ?');
      args.add(publicado ? 1 : 0);
    }
    final sql =
        'SELECT * FROM documentos'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
        ' ORDER BY fecha_recepcion DESC, id DESC';
    final filas = _bd.conexion.select(sql, args).map(_desdeFila).toList();
    final consulta = texto == null ? '' : normalizarParaBusqueda(texto).trim();
    if (consulta.isEmpty) return filas;
    return filas.where((d) {
      final codigo = normalizarParaBusqueda(d.codigo);
      final nombre = normalizarParaBusqueda(d.nombreCompleto);
      return codigo.contains(consulta) || nombre.contains(consulta);
    }).toList();
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
    fechaRecepcion: f['fecha_recepcion'] as String,
  );
}
