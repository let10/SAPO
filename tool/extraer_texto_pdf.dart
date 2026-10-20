// Utilidad de diagnóstico: vuelca el texto nativo de cada página de un PDF.
//   dart run tool/extraer_texto_pdf.dart <entrada.pdf> <salida.txt>
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final pdf = await PdfDocument.openFile(args[0]);
  final sb = StringBuffer();
  for (final pagina in pdf.pages) {
    final t = await pagina.loadText();
    sb.writeln('=== PÁGINA ${pagina.pageNumber} / ${pdf.pages.length} ===');
    sb.writeln(t?.fullText ?? '');
  }
  await File(args[1]).writeAsString(sb.toString());
  stdout.writeln('${pdf.pages.length} páginas -> ${args[1]}');
  await pdf.dispose();
  exit(0);
}
