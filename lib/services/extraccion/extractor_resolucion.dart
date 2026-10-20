import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../../models/campos_resolucion.dart';
import '../../models/documento.dart';
import 'catalogo_resoluciones.dart';
import 'consolidador_encabezado.dart';
import 'extractor_articulo_primero.dart';
import 'extractor_encabezado.dart';
import 'ocr_focalizado.dart';
import 'validador_campos.dart';

/// Obtiene los cuatro datos de una resolución a partir del texto ya recuperado
/// del PDF y, solo cuando hace falta, de OCR focalizado sobre el encabezado.
class ExtractorResolucion {
  final OcrFocalizado _focalizado;

  ExtractorResolucion({OcrFocalizado? focalizado}) : _focalizado = focalizado ?? OcrFocalizado();

  static const int _caracteresTopeOtrasPaginas = 300;

  /// Solo para herramientas de diagnóstico: si se asigna, recibe todas las
  /// lecturas usadas en la última extracción.
  static List<LecturaTexto>? diagnostico;

  Future<DatosResolucion> extraer(
    PdfDocument pdf,
    List<PaginaTexto> paginas, {
    void Function(String)? progreso,
  }) async {
    if (paginas.isEmpty) {
      return DatosResolucion.vacio('El documento no tiene páginas con texto.');
    }

    // Texto corrido del documento; las páginas de continuación pierden su membrete
    // repetido para que el contenido de un artículo no quede partido por él.
    final cuerpo = [
      paginas.first.texto,
      for (var i = 1; i < paginas.length; i++) ExtractorEncabezado.quitarMembrete(paginas[i].texto),
    ].join('\n');

    progreso?.call('Localizando el Artículo Primero…');
    final anclaAcuerdo = CatalogoResoluciones.esAcuerdoDeConcejo(
      ExtractorEncabezado.seccionEncabezado(paginas.first.texto),
    );
    final articulo = ExtractorArticuloPrimero.extraer(
      cuerpo,
      anclaAcuerdo: anclaAcuerdo,
    );

    // Lecturas disponibles sin OCR adicional.
    final lecturas = <LecturaTexto>[
      LecturaTexto(
        paginas.first.texto,
        paginas.first.usoOcr ? OrigenLectura.ocrPagina : OrigenLectura.nativo,
        config: 'página 1',
      ),
      for (var i = 1; i < paginas.length; i++)
        LecturaTexto(
          paginas[i].texto.length > _caracteresTopeOtrasPaginas
              ? paginas[i].texto.substring(0, _caracteresTopeOtrasPaginas)
              : paginas[i].texto,
          OrigenLectura.otraPagina,
          config: 'inicio de página ${i + 1}',
        ),
    ];

    progreso?.call('Analizando el encabezado…');
    var encabezado = ConsolidadorEncabezado.consolidar(lecturas, textoCuerpo: cuerpo);

    if (!encabezado.numeroYFechaDetectados && pdf.pages.isNotEmpty) {
      final focalizadas = await _focalizado.leerEncabezado(
        pdf.pages.first,
        progreso: progreso,
        esSuficiente: (extra) => ConsolidadorEncabezado.consolidar(
          [...lecturas, ...extra],
          textoCuerpo: cuerpo,
        ).numeroYFechaDetectados,
      );
      lecturas.addAll(focalizadas);
      encabezado = ConsolidadorEncabezado.consolidar(lecturas, textoCuerpo: cuerpo);
    }

    diagnostico?.addAll(lecturas);
    return ValidadorCampos.construir(encabezado, articulo);
  }
}
