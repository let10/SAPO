import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../models/campos_resolucion.dart';
import '../models/documento.dart';
import 'extraccion/extractor_resolucion.dart';
import 'extraccion/ocr_focalizado.dart';
import 'ia/redes_dominio.dart';
import 'ocr_service.dart';
import 'renderizador_pagina.dart';

/// Procesa un PDF página por página: intenta texto nativo y, si no es
/// suficiente, cae a OCR con Tesseract sobre una imagen renderizada de la página.
/// Luego extrae los campos de la resolución (el OCR bruto no se modifica).
class ProcesadorPdf {
  static const int _umbralCaracteresNativos = 30;
  static const double _escalaRenderOCR = 3.0; // ~216 DPI, adecuado para OCR
  static const double _fraccionEncabezado = 0.24;

  final OcrService _ocr = OcrService();
  final RenderizadorPagina _renderizador = RenderizadorPagina();
  final ExtractorResolucion _extractor;

  /// [redes]: redes neuronales propias (número manuscrito y sello de la fecha),
  /// ya cargadas. Son opcionales; si es `null`, el procesamiento funciona
  /// igual, simplemente sin esas lecturas adicionales.
  ProcesadorPdf({RedesDominio? redes})
      : _extractor = ExtractorResolucion(focalizado: OcrFocalizado(redes: redes));

  Future<void> procesarDocumento(
    Documento documento,
    void Function() notificarCambio,
  ) async {
    documento.estado = EstadoDocumento.procesando;
    documento.errorMensaje = '';
    documento.etapa = 'Abriendo el PDF…';
    documento.paginas.clear();
    documento.datos = null;
    documento.datosConfirmados = false;
    notificarCambio();

    PdfDocument? pdf;
    try {
      pdf = await PdfDocument.openFile(documento.ruta);

      final totalPaginas = pdf.pages.length;
      documento.totalPaginas = totalPaginas;

      final buffer = StringBuffer();
      int paginasNativas = 0;
      int paginasOCR = 0;

      for (int i = 0; i < totalPaginas; i++) {
        final pagina = pdf.pages[i];
        final numeroPagina = i + 1;
        documento.etapa = 'Leyendo página $numeroPagina de $totalPaginas…';
        notificarCambio();

        String textoPagina = '';
        bool usoOCR = false;

        try {
          final textoNativo = await pagina.loadText();
          final texto = textoNativo?.fullText ?? '';
          final soloCaracteres = texto.replaceAll(RegExp(r'\s'), '');

          if (soloCaracteres.length >= _umbralCaracteresNativos) {
            textoPagina = texto.trim();
          } else {
            usoOCR = true;
            textoPagina = await _ocrDePagina(pagina, numeroPagina);
          }
        } catch (_) {
          // Si falla la extracción nativa, intentar con OCR como respaldo.
          usoOCR = true;
          try {
            textoPagina = await _ocrDePagina(pagina, numeroPagina);
          } catch (e) {
            textoPagina = '[No se pudo procesar la página $numeroPagina: $e]';
          }
        }

        if (usoOCR) {
          paginasOCR++;
        } else {
          paginasNativas++;
        }

        documento.paginas.add(PaginaTexto(texto: textoPagina, usoOcr: usoOCR));
        buffer.writeln('--- Página $numeroPagina (${usoOCR ? "OCR" : "texto nativo"}) ---');
        buffer.writeln(textoPagina);
        buffer.writeln();

        documento.paginasNativas = paginasNativas;
        documento.paginasOCR = paginasOCR;
        notificarCambio();
      }

      documento.textoCompleto = buffer.toString().trim();

      try {
        documento.datos = await _extractor.extraer(
          pdf,
          documento.paginas,
          progreso: (mensaje) {
            documento.etapa = mensaje;
            notificarCambio();
          },
        );
      } catch (e) {
        documento.datos = DatosResolucion.vacio('No se pudieron extraer los campos automáticamente: $e');
      }

      documento.estado = EstadoDocumento.completado;
    } catch (e) {
      documento.estado = EstadoDocumento.error;
      documento.errorMensaje = e.toString();
    } finally {
      await pdf?.dispose();
    }

    documento.etapa = '';
    notificarCambio();
  }

  Future<String> _ocrDePagina(PdfPage pagina, int numeroPagina) async {
    final imagen = await _renderizador.renderizarAPng(
      pagina,
      escala: _escalaRenderOCR,
      preproceso: Preproceso.color,
      etiqueta: 'ocr',
      // Se borra la tinta azul (sellos y firmas) del cuerpo de la página; en la
      // primera página se respeta el encabezado, donde va el número manuscrito
      // en azul que las redes y el consolidador leen aparte.
      quitarAzulDesde: numeroPagina == 1 ? _fraccionEncabezado : 0,
    );
    try {
      final r = await _ocr.reconocer(imagen.ruta, dpi: imagen.dpi);
      return r.texto;
    } finally {
      await imagen.eliminar();
    }
  }
}
