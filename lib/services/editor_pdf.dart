import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// Edita el PDF directamente en su ubicación (elimina o gira páginas). La
/// escritura es atómica: primero se genera un archivo auxiliar y luego reemplaza
/// al original, así un fallo a mitad de camino no lo deja corrupto.
class EditorPdf {
  /// Elimina la página [numeroPagina] (1 = primera) y devuelve cuántas quedan.
  /// Se niega a dejar el PDF sin páginas.
  Future<int> eliminarPagina(String ruta, int numeroPagina) {
    return _reescribir(ruta, (paginas) {
      final total = paginas.length;
      if (total <= 1) {
        throw StateError('No se puede eliminar la única página del documento.');
      }
      _validarNumero(numeroPagina, total);
      return [
        for (var i = 0; i < total; i++)
          if (i != numeroPagina - 1) paginas[i],
      ];
    });
  }

  /// Gira 90° la página [numeroPagina].
  Future<void> rotarPagina(String ruta, int numeroPagina, {required bool horario}) async {
    await _reescribir(ruta, (paginas) {
      _validarNumero(numeroPagina, paginas.length);
      final giro = horario ? PdfPageRotation.clockwise90 : PdfPageRotation.clockwise270;
      return [
        for (var i = 0; i < paginas.length; i++) i == numeroPagina - 1 ? paginas[i].rotatedBy(giro) : paginas[i],
      ];
    });
  }

  void _validarNumero(int numeroPagina, int total) {
    if (numeroPagina < 1 || numeroPagina > total) {
      throw RangeError('La página $numeroPagina no existe (el documento tiene $total).');
    }
  }

  /// Reconstruye el PDF con las páginas que devuelve [construir]. Quitar o girar
  /// páginas "en sitio" no está soportado: se arma un documento nuevo.
  Future<int> _reescribir(String ruta, List<PdfPage> Function(List<PdfPage> paginas) construir) async {
    final bytes = await File(ruta).readAsBytes();
    final pdf = await PdfDocument.openData(bytes, sourceName: 'edicion:$ruta');
    try {
      final paginas = construir(pdf.pages);
      final nuevo = await PdfDocument.createNew(sourceName: 'edicion-nueva:$ruta');
      final Uint8List resultado;
      try {
        nuevo.pages = paginas;
        resultado = await nuevo.encodePdf();
      } finally {
        await nuevo.dispose();
      }

      final temporal = File('$ruta.nuevo');
      try {
        await temporal.writeAsBytes(resultado, flush: true);
        await temporal.rename(ruta);
      } catch (_) {
        if (await temporal.exists()) await temporal.delete();
        rethrow;
      }
      return paginas.length;
    } finally {
      await pdf.dispose();
    }
  }
}
