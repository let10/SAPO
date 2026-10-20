// Prueba la edición en sitio (eliminar y girar páginas). Para no tocar ningún
// documento real, el script copia el PDF indicado a una carpeta temporal y edita
// esa copia; el archivo indicado solo se lee. Uso:
//   dart run tool/probar_eliminar_pagina.dart archivo.pdf
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:procesador_documental_mdp/services/editor_pdf.dart';

Future<List<int>> _huellas(String ruta) async {
  final pdf = await PdfDocument.openData(await File(ruta).readAsBytes(), sourceName: 'huella:$ruta');
  try {
    final resultado = <int>[];
    for (final pagina in pdf.pages) {
      final imagen = await pagina.render(
        fullWidth: pagina.width * 0.3,
        fullHeight: pagina.height * 0.3,
        backgroundColor: 0xFFFFFFFF,
      );
      resultado.add(Object.hashAll(imagen!.pixels));
      imagen.dispose();
    }
    return resultado;
  } finally {
    await pdf.dispose();
  }
}

Future<List<double>> _medidas(String ruta, int n) async {
  final d = await PdfDocument.openData(await File(ruta).readAsBytes(), sourceName: 'medidas:$ruta');
  try {
    return [d.pages[n - 1].width, d.pages[n - 1].height];
  } finally {
    await d.dispose();
  }
}

bool _iguales(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final fuente = args.first;
  var fallos = 0;
  void verificar(String descripcion, bool ok) {
    stdout.writeln('${ok ? 'OK    ' : 'FALLO '} $descripcion');
    if (!ok) fallos++;
  }

  final bytesFuente = await File(fuente).readAsBytes();
  final fechaFuente = await File(fuente).lastModified();

  final carpeta = await Directory.systemTemp.createTemp('prueba_edicion_pdf_');
  final objetivo = p.join(carpeta.path, p.basename(fuente));
  await File(fuente).copy(objetivo);
  final editor = EditorPdf();

  final huellasInicio = await _huellas(objetivo);
  stdout.writeln('Archivo de prueba (copia temporal de ${p.basename(fuente)}): ${huellasInicio.length} páginas');

  // Eliminar la página 2 en sitio
  final restantes = await editor.eliminarPagina(objetivo, 2);
  final huellas = await _huellas(objetivo);
  final esperado = [...huellasInicio]..removeAt(1);
  verificar('quedan ${huellasInicio.length - 1} páginas (devolvió $restantes)',
      restantes == huellasInicio.length - 1 && huellas.length == restantes);
  verificar('se eliminó la página 2 y el resto conserva su contenido y orden', _iguales(esperado, huellas));
  verificar('no quedó archivo auxiliar', !await File('$objetivo.nuevo').exists());

  var rango = false;
  try {
    await editor.eliminarPagina(objetivo, 99);
  } on RangeError {
    rango = true;
  }
  verificar('rechaza una página inexistente', rango);

  // Giros
  final antes = await _medidas(objetivo, 1);
  final otraAntes = await _medidas(objetivo, 2);
  await editor.rotarPagina(objetivo, 1, horario: true);
  final despues = await _medidas(objetivo, 1);
  verificar('girar a la derecha intercambia ancho y alto de la página 1',
      (despues[0] - antes[1]).abs() < 1 && (despues[1] - antes[0]).abs() < 1);
  final otraDespues = await _medidas(objetivo, 2);
  verificar('las demás páginas no cambian al girar',
      (otraDespues[0] - otraAntes[0]).abs() < 1 && (await _huellas(objetivo)).length == restantes);
  await editor.rotarPagina(objetivo, 1, horario: false);
  final vuelta = await _medidas(objetivo, 1);
  verificar('girar a la izquierda devuelve la orientación original',
      (vuelta[0] - antes[0]).abs() < 1 && (vuelta[1] - antes[1]).abs() < 1);

  // Última página
  var quedan = restantes;
  while (quedan > 1) {
    quedan = await editor.eliminarPagina(objetivo, 1);
  }
  var unica = false;
  try {
    await editor.eliminarPagina(objetivo, 1);
  } on StateError {
    unica = true;
  }
  verificar('no permite eliminar la única página restante', unica && (await _huellas(objetivo)).length == 1);

  // El archivo fuente (documento real) solo se leyó
  final bytesDespues = await File(fuente).readAsBytes();
  var identico = bytesFuente.length == bytesDespues.length;
  for (var i = 0; identico && i < bytesFuente.length; i++) {
    if (bytesFuente[i] != bytesDespues[i]) identico = false;
  }
  verificar('el archivo fuente (solo lectura) quedó idéntico', identico && fechaFuente == await File(fuente).lastModified());

  await carpeta.delete(recursive: true);
  verificar('la carpeta temporal se borró', !await carpeta.exists());

  stdout.writeln(fallos == 0 ? 'TODO CORRECTO' : '$fallos FALLO(S)');
  exit(fallos == 0 ? 0 : 1);
}
