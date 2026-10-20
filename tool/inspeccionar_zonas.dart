// Diagnóstico visual: para cada PDF localiza las zonas del número (manuscrito)
// y del sello de la fecha, separa la tinta por color, segmenta los dígitos y
// guarda un PNG con: recorte en color, tinta separada y los parches 28x28 que
// vería la red.
//   dart run tool/inspeccionar_zonas.dart <carpeta_salida> <pdf> [<pdf> ...]
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:procesador_documental_mdp/services/extraccion/ocr_focalizado.dart';
import 'package:procesador_documental_mdp/services/ia/segmentador_componentes.dart';
import 'package:procesador_documental_mdp/services/ia/separador_tinta.dart';
import 'package:procesador_documental_mdp/services/renderizador_pagina.dart';

img.Image _deColor(ImagenColor c) => img.Image.fromBytes(width: c.ancho, height: c.alto, bytes: c.rgb.buffer, numChannels: 3);

img.Image _deGris(ImagenGris g) => img.Image.fromBytes(width: g.ancho, height: g.alto, bytes: g.pixeles.buffer, numChannels: 1);

img.Image _montajeParches(List<DigitoSegmentado> ds) {
  const aumento = 4;
  final lienzo = img.Image(width: (ds.isEmpty ? 1 : ds.length) * (28 * aumento + 6), height: 28 * aumento, numChannels: 3);
  img.fill(lienzo, color: img.ColorRgb8(200, 60, 60));
  for (var i = 0; i < ds.length; i++) {
    final x0 = i * (28 * aumento + 6);
    for (var y = 0; y < 28; y++) {
      for (var x = 0; x < 28; x++) {
        final v = (255 - ds[i].patch[y * 28 + x] * 255).round().clamp(0, 255);
        for (var dy = 0; dy < aumento; dy++) {
          for (var dx = 0; dx < aumento; dx++) {
            lienzo.setPixelRgb(x0 + x * aumento + dx, y * aumento + dy, v, v, v);
          }
        }
      }
    }
  }
  return lienzo;
}

img.Image _apilar(List<img.Image> partes) {
  var ancho = 0, alto = 0;
  for (final p in partes) {
    if (p.width > ancho) ancho = p.width;
    alto += p.height + 8;
  }
  final lienzo = img.Image(width: ancho, height: alto, numChannels: 3);
  img.fill(lienzo, color: img.ColorRgb8(255, 255, 255));
  var y = 0;
  for (final p in partes) {
    img.compositeImage(lienzo, p.numChannels == 3 ? p : p.convert(numChannels: 3), dstX: 0, dstY: y);
    y += p.height + 8;
  }
  return lienzo;
}

Future<void> _guardar(Directory carpeta, String nombre, img.Image imagen) async {
  await File('${carpeta.path}${Platform.pathSeparator}$nombre.png').writeAsBytes(Uint8List.fromList(img.encodePng(imagen)));
}

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final salida = Directory(args[0])..createSync(recursive: true);
  final foc = OcrFocalizado();
  final render = RenderizadorPagina();
  var n = 0;
  for (final ruta in args.skip(1)) {
    n++;
    final pdf = await PdfDocument.openFile(ruta);
    final pagina = pdf.pages.first;
    final zonas = await foc.localizarZonas(pagina);
    final partes = <img.Image>[];
    final etiqueta = StringBuffer('${ruta.split(Platform.pathSeparator).last}\n  número: ${zonas.numero}  sello: ${zonas.sello}');

    if (zonas.numero != null) {
      final color = await render.renderizarColor(pagina, region: zonas.numero!, escala: 8.0);
      final tinta = SeparadorTinta.tintaAzul(color);
      final ds = SegmentadorComponentes.segmentar(tinta);
      etiqueta.write('  → dígitos número: ${ds.length}');
      partes
        ..add(_deColor(color))
        ..add(_deGris(tinta))
        ..add(_montajeParches(ds));
      await _guardar(salida, '${n.toString().padLeft(2, '0')}_numero_color', _deColor(color));
      await _guardar(salida, '${n.toString().padLeft(2, '0')}_numero_tinta', _deGris(tinta));
      await _guardar(salida, '${n.toString().padLeft(2, '0')}_numero_digitos', _montajeParches(ds));
    }
    if (zonas.sello != null) {
      final color = await render.renderizarColor(pagina, region: zonas.sello!, escala: 8.0);
      final tinta = SeparadorTinta.tintaOscura(color);
      final ds = SegmentadorComponentes.segmentar(tinta);
      etiqueta.write('  → manchas sello: ${ds.length}');
      partes
        ..add(_deColor(color))
        ..add(_deGris(tinta))
        ..add(_montajeParches(ds.take(10).toList()));
      await _guardar(salida, '${n.toString().padLeft(2, '0')}_sello_color', _deColor(color));
      await _guardar(salida, '${n.toString().padLeft(2, '0')}_sello_tinta', _deGris(tinta));
      await _guardar(salida, '${n.toString().padLeft(2, '0')}_sello_digitos', _montajeParches(ds.take(2).toList()));
    }
    stdout.writeln(etiqueta);
    if (partes.isNotEmpty) {
      final archivo = File('${salida.path}${Platform.pathSeparator}zona_${n.toString().padLeft(2, '0')}.png');
      await archivo.writeAsBytes(Uint8List.fromList(img.encodePng(_apilar(partes))));
    }
    await pdf.dispose();
  }
  exit(0);
}
