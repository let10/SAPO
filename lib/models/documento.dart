import 'campos_resolucion.dart';

enum EstadoDocumento { pendiente, procesando, completado, error }

/// Texto recuperado de una página, tal como lo devolvió el PDF o Tesseract.
class PaginaTexto {
  final String texto;
  final bool usoOcr;

  const PaginaTexto({required this.texto, required this.usoOcr});
}

class Documento {
  String nombre;
  String ruta;
  EstadoDocumento estado;
  String textoCompleto;
  int totalPaginas;
  int paginasNativas;
  int paginasOCR;
  String errorMensaje;

  /// Texto por página (OCR/nativo bruto, sin normalizar).
  final List<PaginaTexto> paginas = [];

  /// Mensaje breve de la etapa en curso mientras se procesa.
  String etapa;

  /// Campos extraídos automáticamente (editables por el usuario).
  DatosResolucion? datos;
  bool datosConfirmados;

  /// `id` del registro en la base de datos local, si ya se registró; `null` si no.
  int? idRegistro;

  bool get registrado => idRegistro != null;

  int paginasEliminadas = 0;
  int paginasRotadas = 0;

  bool get tieneEdiciones => paginasEliminadas > 0 || paginasRotadas > 0;

  /// Ediciones hechas desde el visor sobre el archivo (solo esta sesión). Ej.: "1 página eliminada, 2 giros".
  String get resumenEdicion => [
        if (paginasEliminadas > 0) '$paginasEliminadas ${paginasEliminadas == 1 ? 'página eliminada' : 'páginas eliminadas'}',
        if (paginasRotadas > 0) '$paginasRotadas ${paginasRotadas == 1 ? 'giro' : 'giros'}',
      ].join(', ');

  Documento({
    required this.nombre,
    required this.ruta,
    this.estado = EstadoDocumento.pendiente,
    this.textoCompleto = '',
    this.totalPaginas = 0,
    this.paginasNativas = 0,
    this.paginasOCR = 0,
    this.errorMensaje = '',
    this.etapa = '',
    this.datos,
    this.datosConfirmados = false,
  });

  String get estadoLabel => switch (estado) {
        EstadoDocumento.pendiente => 'Pendiente',
        EstadoDocumento.procesando => 'Procesando',
        EstadoDocumento.completado => 'Completado',
        EstadoDocumento.error => 'Error',
      };

  bool get sePuedeProcesar =>
      estado == EstadoDocumento.pendiente || estado == EstadoDocumento.error;

  bool get tieneTexto =>
      estado == EstadoDocumento.completado && textoCompleto.isNotEmpty;
}
