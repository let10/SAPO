// Arma el conjunto de entrenamiento del dominio real: recorta, de cada
// resolución verificada a mano, los dígitos del número (escritura a mano en
// tinta azul) y los del sello de la fecha, y les pone la etiqueta que dice la
// verdad (Excel verificado). Solo LEE los PDFs; los resultados quedan en
// tool/datos_entrenamiento/ (que no se versiona).
//
//   dart run tool/construir_dataset_dominio.dart <carpeta_pdfs> <verdad.json> <carpeta_salida>
//
// Formato de cada muestra en los .bin: 1 byte de etiqueta (0-9), 2 bytes
// (little-endian) con el índice del documento, y 784 bytes del parche 28×28.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:procesador_documental_mdp/services/extraccion/ocr_focalizado.dart';
import 'package:procesador_documental_mdp/services/ia/segmentador_componentes.dart';
import 'package:procesador_documental_mdp/services/ia/separador_tinta.dart';
import 'package:procesador_documental_mdp/services/renderizador_pagina.dart';

class _Fila {
  final String codigo, fecha;
  _Fila(this.codigo, this.fecha);
  String get numero => codigo.split('-').first;
  String get siglas => codigo.split('-').skip(2).join('-');
  String get dia => fecha.split('/').first;
  String get anio => fecha.split('/').last;
}

void _escribir(BytesBuilder b, int etiqueta, int doc, DigitoSegmentado d) {
  b.addByte(etiqueta);
  b.addByte(doc & 0xFF);
  b.addByte((doc >> 8) & 0xFF);
  for (final v in d.patch) {
    b.addByte((v * 255).round().clamp(0, 255));
  }
}

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final carpeta = Directory(args[0]);
  final verdad = (jsonDecode(File(args[1]).readAsStringSync()) as List)
      .map((e) => _Fila(e['Codigo'] as String, e['Fecha'] as String))
      .toList();
  final salida = Directory(args[2])..createSync(recursive: true);

  final numero = BytesBuilder(), dia = BytesBuilder(), anio = BytesBuilder();
  final foc = OcrFocalizado();
  final render = RenderizadorPagina();
  final nombres = <String>[];
  var muestrasNumero = 0, muestrasDia = 0, muestrasAnio = 0;

  final pdfs = carpeta.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.pdf')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in pdfs) {
    final nombre = f.uri.pathSegments.last;
    final m = RegExp(r'N°\s*(\d+)-(?:\d{4}-)?(.+)\.pdf$', caseSensitive: false).firstMatch(nombre);
    if (m == null) continue;
    final fila = verdad.where((r) => r.numero == m.group(1)!.padLeft(3, '0') && r.siglas == m.group(2)).toList();
    if (fila.isEmpty) {
      stdout.writeln('SIN FILA DE VERDAD: $nombre');
      continue;
    }
    final v = fila.first;
    final idDoc = nombres.length;
    nombres.add(nombre);

    final pdf = await PdfDocument.openFile(f.path);
    final pagina = pdf.pages.first;
    final zonas = await foc.localizarZonas(pagina);
    final resumen = StringBuffer(v.codigo.padRight(30));

    if (zonas.numero == null) {
      resumen.write(' num:sin-zona');
    } else {
      final tinta = SeparadorTinta.tintaAzul(await render.renderizarColor(pagina, region: zonas.numero!, escala: 8.0));
      final ds = SegmentadorComponentes.segmentar(tinta, cantidadEsperada: 3);
      String? etiqueta;
      if (ds.length == v.numero.length) etiqueta = v.numero;
      if (ds.isEmpty) {
        resumen.write(' num:impreso');
      } else if (etiqueta == null) {
        resumen.write(' num:DESCUADRE(${ds.length} manchas, "${v.numero}")');
      } else {
        for (var i = 0; i < ds.length; i++) {
          _escribir(numero, int.parse(etiqueta[i]), idDoc, ds[i]);
          muestrasNumero++;
        }
        resumen.write(' num:ok($etiqueta)');
      }
    }

    if (zonas.sello == null) {
      resumen.write(' sello:sin-zona');
    } else {
      final tinta = SeparadorTinta.tintaOscura(await render.renderizarColor(pagina, region: zonas.sello!, escala: 8.0));
      final ds = SegmentadorComponentes.segmentar(tinta);
      // Un sello tiene unas 9-10 manchas (día, mes, año); si hay muchas más es
      // una fecha mecanografiada, que no es el dominio de esta red.
      if (ds.length < 3 || ds.length > 11) {
        resumen.write(' sello:NO-ES-SELLO(${ds.length} manchas)');
      } else {
        _escribir(dia, int.parse(v.dia[0]), idDoc, ds[0]);
        _escribir(dia, int.parse(v.dia[1]), idDoc, ds[1]);
        muestrasDia += 2;
        if (ds.length >= 8) {
          final ultimos = ds.sublist(ds.length - 4);
          for (var i = 0; i < 4; i++) {
            _escribir(anio, int.parse(v.anio[i]), idDoc, ultimos[i]);
            muestrasAnio++;
          }
        }
        resumen.write(' sello:ok(${ds.length} manchas, día ${v.dia})');
      }
    }
    stdout.writeln(resumen);
    await pdf.dispose();
  }

  File('${salida.path}/dominio_numero.bin').writeAsBytesSync(numero.toBytes());
  File('${salida.path}/dominio_sello_dia.bin').writeAsBytesSync(dia.toBytes());
  File('${salida.path}/dominio_sello_anio.bin').writeAsBytesSync(anio.toBytes());
  File('${salida.path}/dominio_documentos.json').writeAsStringSync(jsonEncode(nombres));
  stdout.writeln('\nMuestras: número=$muestrasNumero  día(sello)=$muestrasDia  año(sello)=$muestrasAnio  documentos=${nombres.length}');
  exit(0);
}
