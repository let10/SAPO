// Herramienta de diagnóstico: procesa PDFs con la misma tubería de la aplicación
// (incluida la red neuronal propia, si hay pesos entrenados) e imprime los
// campos extraídos. Uso:
//   dart run tool/probar_pdf.dart [--texto] [--diag] [--sin-ia] archivo1.pdf archivo2.pdf ...
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:procesador_documental_mdp/models/documento.dart';
import 'package:procesador_documental_mdp/services/extraccion/consolidador_encabezado.dart';
import 'package:procesador_documental_mdp/services/extraccion/extractor_resolucion.dart';
import 'package:procesador_documental_mdp/services/ia/redes_dominio.dart';
import 'package:procesador_documental_mdp/services/procesador_pdf.dart';

Future<void> main(List<String> args) async {
  final mostrarTexto = args.contains('--texto');
  final diag = args.contains('--diag');
  final sinIA = args.contains('--sin-ia');
  final rutas = args.where((a) => !a.startsWith('--')).toList();
  await pdfrxInitialize();

  // Carga los pesos directamente de los archivos (sin `rootBundle`, que solo
  // existe dentro de la app Flutter en ejecución).
  final redes = sinIA ? null : RedesDominio.desdeCarpeta('assets/ia');
  stdout.writeln(redes == null
      ? 'Redes neuronales: NO cargadas (${sinIA ? "--sin-ia" : "no se encontraron assets/ia/red_numero.bin y red_sello.bin"})'
      : 'Redes neuronales: cargadas desde assets/ia (número y sello)');

  for (final ruta in rutas) {
    final doc = Documento(nombre: ruta.split(RegExp(r'[\\/]')).last, ruta: ruta);
    final lecturas = <LecturaTexto>[];
    if (diag) ExtractorResolucion.diagnostico = lecturas;
    final cronometro = Stopwatch()..start();
    await ProcesadorPdf(redes: redes).procesarDocumento(doc, () {});
    cronometro.stop();

    stdout.writeln('=' * 100);
    stdout.writeln('ARCHIVO : ${doc.nombre}');
    stdout.writeln(
        'ESTADO  : ${doc.estadoLabel}  | páginas ${doc.totalPaginas} (nativas ${doc.paginasNativas}, OCR ${doc.paginasOCR})  | ${(cronometro.elapsedMilliseconds / 1000).toStringAsFixed(1)} s');
    if (doc.estado == EstadoDocumento.error) {
      stdout.writeln('ERROR   : ${doc.errorMensaje}');
      continue;
    }
    final d = doc.datos;
    if (d == null) {
      stdout.writeln('(sin datos)');
      continue;
    }
    void campo(String etiqueta, String valor, String estado, String nota) {
      stdout.writeln('$etiqueta [$estado] $valor');
      if (nota.isNotEmpty) stdout.writeln('      nota: $nota');
    }

    campo('NOMBRE  ', d.nombreCompleto.valor, d.nombreCompleto.estadoLabel, d.nombreCompleto.nota);
    campo('CÓDIGO  ', d.codigo.valor, d.codigo.estadoLabel, d.codigo.nota);
    campo('FECHA   ', d.fecha.valor, d.fecha.estadoLabel, d.fecha.nota);
    campo('ARTÍCULO', d.articuloPrimeroPrincipal.valor, d.articuloPrimeroPrincipal.estadoLabel,
        d.articuloPrimeroPrincipal.nota);
    if (diag) {
      final completo = d.articuloPrimeroCompleto.replaceAll(RegExp(r'\s+'), ' ');
      final principal = d.articuloPrimeroPrincipal.valor;
      final resto = completo.length > principal.length ? completo.substring(principal.length) : '';
      stdout.writeln('--- DESPUÉS DEL PÁRRAFO PRINCIPAL (${resto.length} car.) ---');
      stdout.writeln(resto.length > 260 ? '${resto.substring(0, 260)}…' : resto);
      stdout.writeln('--- LECTURAS (${lecturas.length}) ---');
      for (final l in lecturas) {
        final t = l.texto.replaceAll(RegExp(r'\s+'), ' ');
        final corto = l.origen == OrigenLectura.ocrFocalizado && l.config.startsWith('barrido')
            ? (t.length > 260 ? '${t.substring(0, 260)}…' : t)
            : (t.length > 160 ? '${t.substring(0, 160)}…' : t);
        final conf = l.probabilidades == null ? '' : ' (confianza ${(l.confianza * 100).toStringAsFixed(0)}%)';
        stdout.writeln('[${l.origen.name}] ${l.config}: $corto$conf');
      }
    }
    if (mostrarTexto) {
      stdout.writeln('--- TEXTO BRUTO ---');
      stdout.writeln(doc.textoCompleto);
    }
  }
  exit(0);
}
