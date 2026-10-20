enum EstadoCampo { detectado, requiereRevision }

class CampoExtraido {
  String valor;
  EstadoCampo estado;
  String nota;
  bool editadoManualmente;

  CampoExtraido({
    this.valor = '',
    this.estado = EstadoCampo.requiereRevision,
    this.nota = '',
    this.editadoManualmente = false,
  });

  String get estadoLabel => switch (estado) {
        EstadoCampo.detectado => 'DETECTADO',
        EstadoCampo.requiereRevision => 'REQUIERE REVISIÓN',
      };

  bool get requiereRevision => estado == EstadoCampo.requiereRevision;
}

/// Resultado de la extracción automática de los cuatro datos de una resolución.
/// Es independiente del OCR bruto, que se conserva sin modificar en [Documento].
class DatosResolucion {
  final CampoExtraido nombreCompleto;
  final CampoExtraido codigo;
  final CampoExtraido fecha;
  final CampoExtraido articuloPrimeroPrincipal;

  /// Texto íntegro del Artículo Primero (incluye el bloque de detalle). Solo uso interno.
  final String articuloPrimeroCompleto;

  const DatosResolucion({
    required this.nombreCompleto,
    required this.codigo,
    required this.fecha,
    required this.articuloPrimeroPrincipal,
    this.articuloPrimeroCompleto = '',
  });

  List<CampoExtraido> get campos =>
      [nombreCompleto, codigo, fecha, articuloPrimeroPrincipal];

  int get camposPorRevisar => campos.where((c) => c.requiereRevision).length;

  factory DatosResolucion.vacio(String nota) => DatosResolucion(
        nombreCompleto: CampoExtraido(nota: nota),
        codigo: CampoExtraido(nota: nota),
        fecha: CampoExtraido(nota: nota),
        articuloPrimeroPrincipal: CampoExtraido(nota: nota),
      );
}
