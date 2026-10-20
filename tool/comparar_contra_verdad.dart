// Herramienta de diagnóstico: procesa los PDF ya verificados manualmente en
// escaneos/prueba y compara el resultado contra el Excel de control, para
// medir qué tan bien funciona la extracción real.
//
// Uso:
//   dart run tool/comparar_contra_verdad.dart <carpeta_pdfs> <verdad.json> <salida.json>
//
// <verdad.json> es una lista de objetos {Nombre, Codigo, Fecha, Articulo},
// exportada a mano del Excel de control (ver notas de la sesión para el
// script de extracción desde el .xlsx).
import 'dart:convert';
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:procesador_documental_mdp/models/documento.dart';
import 'package:procesador_documental_mdp/services/ia/redes_dominio.dart';
import 'package:procesador_documental_mdp/services/procesador_pdf.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('Uso: dart run tool/comparar_contra_verdad.dart <carpeta_pdfs> <verdad.json> <salida.json> [--sin-ia]');
    exit(1);
  }
  final carpeta = args[0];
  final verdadJson = args[1];
  final salida = args[2];
  final redes = args.contains('--sin-ia') ? null : RedesDominio.desdeCarpeta('assets/ia');
  stdout.writeln(redes == null ? 'Redes neuronales: NO cargadas' : 'Redes neuronales: cargadas (número y sello)');

  await pdfrxInitialize();
  final verdad = (jsonDecode(await File(verdadJson).readAsString()) as List).cast<Map<String, dynamic>>();
  // Se empareja por número + siglas (algunos archivos omiten el año en el nombre).
  String clave(String codigo) {
    final p = codigo.split('-');
    return '${p.first}|${p.skip(p.length > 1 && RegExp(r'^\d{4}$').hasMatch(p[1]) ? 2 : 1).join('-')}';
  }

  final porCodigo = {for (final v in verdad) clave(v['Codigo'] as String): v};

  final archivos = Directory(carpeta).listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')).toList();
  final resultados = <Map<String, dynamic>>[];

  for (final archivo in archivos) {
    final nombre = archivo.path.split(RegExp(r'[\\/]')).last;
    stdout.writeln('Procesando: $nombre');
    final doc = Documento(nombre: nombre, ruta: archivo.path);
    await ProcesadorPdf(redes: redes).procesarDocumento(doc, () {});

    final m = RegExp(r'N°\s*(\d{2,4}-(?:\d{4}-)?[A-Z-]+)\.pdf').firstMatch(nombre);
    final v = m == null ? null : porCodigo[clave(m.group(1)!)];
    final codigoEsperado = (v?['Codigo'] as String?) ?? '';

    resultados.add({
      'archivo': nombre,
      'codigoEsperado': codigoEsperado,
      'estado': doc.estado.name,
      'nombreObtenido': doc.datos?.nombreCompleto.valor ?? '',
      'nombreEstado': doc.datos?.nombreCompleto.estado.name ?? '',
      'codigoObtenido': doc.datos?.codigo.valor ?? '',
      'codigoEstado': doc.datos?.codigo.estado.name ?? '',
      'fechaObtenida': doc.datos?.fecha.valor ?? '',
      'fechaEstado': doc.datos?.fecha.estado.name ?? '',
      'fechaEsperada': v?['Fecha'] ?? '',
      'articuloObtenido': doc.datos?.articuloPrimeroPrincipal.valor ?? '',
      'articuloEstado': doc.datos?.articuloPrimeroPrincipal.estado.name ?? '',
      'articuloEsperado': v?['Articulo'] ?? '',
      'notaCodigo': doc.datos?.codigo.nota ?? '',
      'notaFecha': doc.datos?.fecha.nota ?? '',
      'notaArticulo': doc.datos?.articuloPrimeroPrincipal.nota ?? '',
    });
  }

  await File(salida).writeAsString(const JsonEncoder.withIndent('  ').convert(resultados));
  stdout.writeln('Comparación de ${resultados.length} documentos guardada en $salida');
  exit(0);
}
