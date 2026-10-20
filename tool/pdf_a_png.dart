// Utilidad de diagnóstico: guarda varias páginas de un PDF como PNG numerados.
//   dart run tool/pdf_a_png.dart <entrada.pdf> <carpeta_salida> <paginas: 1,3,5-7 | todas> [escala=1.2]
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:procesador_documental_mdp/services/renderizador_pagina.dart';

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final pdf = await PdfDocument.openFile(args[0]);
  final salida = Directory(args[1])..createSync(recursive: true);
  final escala = args.length > 3 ? double.parse(args[3]) : 1.2;
  final total = pdf.pages.length;
  final paginas = <int>{};
  if (args[2] == 'todas') {
    paginas.addAll(List.generate(total, (i) => i + 1));
  } else {
    for (final parte in args[2].split(',')) {
      final r = parte.split('-');
      final a = int.parse(r.first), b = int.parse(r.last);
      for (var i = a; i <= b && i <= total; i++) {
        paginas.add(i);
      }
    }
  }
  final render = RenderizadorPagina();
  for (final n in paginas) {
    final img = await render.renderizarAPng(pdf.pages[n - 1], escala: escala, etiqueta: 'doc');
    await File(img.ruta).copy('${salida.path}${Platform.pathSeparator}p${n.toString().padLeft(3, '0')}.png');
    await img.eliminar();
  }
  stdout.writeln('$total páginas en el PDF; guardadas ${paginas.length} en ${salida.path}');
  await pdf.dispose();
  exit(0);
}
