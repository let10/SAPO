// Diagnóstico: muestra, en un PNG, los dígitos del conjunto del dominio que la
// red de MNIST (sin afinar) clasifica mal, con su documento, etiqueta y
// predicción.
//   dart run tool/ver_errores_dominio.dart <numero|sello_dia> <salida.png>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:procesador_documental_mdp/services/ia/red_digitos.dart';

void main(List<String> args) {
  final bytes = File('tool/datos_entrenamiento/dominio_${args[0]}.bin').readAsBytesSync();
  final docs = (jsonDecode(File('tool/datos_entrenamiento/dominio_documentos.json').readAsStringSync()) as List).cast<String>();
  final red = RedDigitos.cargarPesos(ByteData.sublistView(File('assets/ia/red_digitos.bin').readAsBytesSync()));

  final errores = <(Float32List, int, int, int, int)>[];
  var total = 0;
  final posicionEnDoc = <int, int>{};
  for (var o = 0; o + 787 <= bytes.length; o += 787) {
    final etiqueta = bytes[o];
    final doc = bytes[o + 1] | (bytes[o + 2] << 8);
    final patch = Float32List(784);
    for (var i = 0; i < 784; i++) {
      patch[i] = bytes[o + 3 + i] / 255.0;
    }
    final pos = posicionEnDoc[doc] = (posicionEnDoc[doc] ?? -1) + 1;
    final pred = red.adelanteConCache(patch).prediccion;
    total++;
    if (pred != etiqueta) errores.add((patch, etiqueta, pred, doc, pos));
  }
  stdout.writeln('${errores.length} errores de $total');
  const aumento = 4, celda = 28 * aumento + 8;
  final columnas = 8;
  final filas = (errores.length / columnas).ceil();
  final lienzo = img.Image(width: columnas * celda, height: filas * (celda + 4), numChannels: 3);
  img.fill(lienzo, color: img.ColorRgb8(235, 235, 235));
  for (var k = 0; k < errores.length; k++) {
    final (patch, etiqueta, pred, doc, pos) = errores[k];
    stdout.writeln('${k.toString().padLeft(2)}: ${docs[doc].replaceFirst('RESOLUCIÓN DE ', '').split('N°').last.trim().padRight(34)} pos ${pos + 1}  etiqueta $etiqueta  red→$pred');
    final x0 = (k % columnas) * celda + 4, y0 = (k ~/ columnas) * (celda + 4) + 4;
    for (var y = 0; y < 28; y++) {
      for (var x = 0; x < 28; x++) {
        final v = (255 - patch[y * 28 + x] * 255).round().clamp(0, 255);
        for (var dy = 0; dy < aumento; dy++) {
          for (var dx = 0; dx < aumento; dx++) {
            lienzo.setPixelRgb(x0 + x * aumento + dx, y0 + y * aumento + dy, v, v, v);
          }
        }
      }
    }
  }
  File(args[1]).writeAsBytesSync(Uint8List.fromList(img.encodePng(lienzo)));
}
