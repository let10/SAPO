import 'documento.dart';

/// Un documento administrativo ya registrado en la base de datos local. Es
/// general: sirve para cualquier tipo (resoluciones de todos sus subtipos,
/// decretos de alcaldía, acuerdos de concejo, ordenanzas), porque todos
/// comparten los mismos datos principales.
class DocumentoAlmacenado {
  /// `null` mientras no se ha guardado; lo asigna la base de datos.
  final int? id;

  /// Tipo en mayúsculas, p. ej. `RESOLUCIÓN DE ALCALDÍA`, `DECRETO DE ALCALDÍA`,
  /// `ACUERDO DE CONCEJO MUNICIPAL`, `ORDENANZA MUNICIPAL`.
  final String tipoDocumento;
  final String nombreCompleto;
  final String codigo;

  /// Fecha del documento en formato ISO `AAAA-MM-DD`.
  final String fechaDocumento;
  final String articuloPrimero;
  final String rutaPdf;
  final bool publicado;
  final DateTime? fechaPublicacion;

  /// La asigna la base de datos al insertar; `null` antes de guardar.
  final DateTime? fechaRegistro;

  const DocumentoAlmacenado({
    this.id,
    required this.tipoDocumento,
    required this.nombreCompleto,
    required this.codigo,
    required this.fechaDocumento,
    required this.articuloPrimero,
    required this.rutaPdf,
    this.publicado = false,
    this.fechaPublicacion,
    this.fechaRegistro,
  });

  /// `DD/MM/AAAA`, como se muestra al usuario.
  String get fechaDocumentoParaMostrar {
    final p = fechaDocumento.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : fechaDocumento;
  }

  /// Tipo de documento a partir del nombre completo: lo que va antes del
  /// símbolo de número. `RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T` →
  /// `RESOLUCIÓN DE ALCALDÍA`.
  static String tipoDesdeNombre(String nombreCompleto) {
    final sinNumero = nombreCompleto.replaceFirst(RegExp(r'\s+N\s*[°º.*]*\s*[\d_].*$'), '');
    return sinNumero.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
  }

  /// Convierte `DD/MM/AAAA` en `AAAA-MM-DD`. Lanza [FormatException] si no cumple el formato.
  static String fechaAIso(String ddmmaaaa) {
    final m = RegExp(r'^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$').firstMatch(ddmmaaaa);
    if (m == null) throw FormatException('La fecha "$ddmmaaaa" no tiene el formato DD/MM/AAAA.');
    return '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
  }

  /// Arma el registro con los datos **confirmados** por el usuario (no los del
  /// OCR original) y la ruta **actual** del PDF (ya renombrado, si lo estaba).
  /// Lanza [StateError] si los datos no están confirmados o están incompletos.
  factory DocumentoAlmacenado.desdeDocumentoConfirmado(Documento documento) {
    final datos = documento.datos;
    if (datos == null || !documento.datosConfirmados) {
      throw StateError('Primero hay que confirmar los datos del documento.');
    }
    final nombre = datos.nombreCompleto.valor.trim();
    final codigo = datos.codigo.valor.trim();
    final articulo = datos.articuloPrimeroPrincipal.valor.trim();
    if (nombre.isEmpty || codigo.isEmpty || articulo.isEmpty) {
      throw StateError('Hay datos confirmados vacíos; no se puede registrar el documento.');
    }
    return DocumentoAlmacenado(
      tipoDocumento: tipoDesdeNombre(nombre),
      nombreCompleto: nombre,
      codigo: codigo,
      fechaDocumento: fechaAIso(datos.fecha.valor),
      articuloPrimero: articulo,
      rutaPdf: documento.ruta,
    );
  }
}
