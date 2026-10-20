// Diagnóstico: guarda una página (o una región) de un PDF como PNG.
//   dart run tool/renderizar_pagina.dart entrada.pdf salida.png [pagina=1] [escala=1.5] [x0 y0 x1 y1 en fracciones]
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:procesador_documental_mdp/services/renderizador_pagina.dart';

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final pdf = await PdfDocument.openFile(args[0]);
  final numero = args.length > 2 ? int.parse(args[2]) : 1;
  final escala = args.length > 3 ? double.parse(args[3]) : 1.5;
  final region = args.length > 7
      ? RegionPagina(double.parse(args[4]), double.parse(args[5]), double.parse(args[6]), double.parse(args[7]))
      : RegionPagina.completa;
  final imagen = await RenderizadorPagina().renderizarAPng(
    pdf.pages[numero - 1],
    region: region,
    escala: escala,
    etiqueta: 'diag',
  );
  await File(imagen.ruta).copy(args[1]);
  await imagen.eliminar();
  await pdf.dispose();
  stdout.writeln('OK ${args[1]}');
  exit(0);
}
