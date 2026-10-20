// Mide el Artículo Primero extraído contra el verificado a mano.
//   dart run tool/medir_articulo.dart <resultado.json>
//
// El texto esperado puede ser más corto que el extraído (la persona lo recorta
// donde quiere para el formulario web) o más largo (si la extracción se cortó),
// y trae `N°` donde el OCR da `N*`. Por eso se informan por separado:
//  - exacto: idéntico tal cual;
//  - exacto tras normalizar `N°`/`MDP-T`;
//  - prefijo: uno es prefijo del otro (diferencia solo de longitud);
//  - corte: el extraído es más corto que el esperado (se perdió texto);
//  - CER: tasa de error de caracteres sobre el tramo común, tolerando que el
//    esperado sea un recorte del extraído.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

String norm(String s) => s
    .replaceAll(RegExp(r'N\s*\.?\s*[*º°?]'), 'N°')
    .replaceAll('/T', '-T')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Distancia de edición entre [a] y el mejor prefijo de [b] (el final de [b]
/// puede quedar sin alinear).
int distanciaConPrefijo(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + c);
    }
    prev = cur;
  }
  return prev.reduce(math.min);
}

void main(List<String> args) {
  final datos = (jsonDecode(File(args[0]).readAsStringSync()) as List).cast<Map<String, dynamic>>();
  var exactos = 0, normalizados = 0, prefijos = 0, cortes = 0, otros = 0;
  var errores = 0, caracteres = 0;
  final detalle = <String>[];
  for (final d in datos) {
    final o = (d['articuloObtenido'] as String? ?? '');
    final e = (d['articuloEsperado'] as String? ?? '');
    if (e.isEmpty) continue;
    final on = norm(o), en = norm(e);
    String tipo;
    if (o == e) {
      exactos++;
      normalizados++;
      tipo = 'exacto';
    } else if (on == en) {
      normalizados++;
      tipo = 'exacto tras normalizar';
    } else if (on.startsWith(en)) {
      prefijos++;
      tipo = 'extraído más largo que el esperado (recorte)';
    } else if (en.startsWith(on)) {
      cortes++;
      tipo = 'CORTE: se perdió texto (${en.length - on.length} car.)';
    } else {
      otros++;
      tipo = 'DIFERENCIA de caracteres';
    }
    // CER sobre el tramo que el esperado cubre.
    final ref = en;
    final cand = on.length > ref.length + 10 ? on.substring(0, math.min(on.length, ref.length + 10)) : on;
    final dist = distanciaConPrefijo(ref, cand);
    final ajustada = (en.startsWith(on) ? 0 : dist);
    errores += ajustada;
    caracteres += ref.length;
    if (tipo != 'exacto' && tipo != 'exacto tras normalizar') {
      var k = 0;
      while (k < on.length && k < en.length && on[k] == en[k]) {
        k++;
      }
      String ventana(String s) => s.substring(math.max(0, k - 25), math.min(s.length, k + 35));
      detalle.add('${d['codigoEsperado']}: $tipo${dist > 0 && !en.startsWith(on) ? ' | edición=$dist' : ''}'
          '${tipo.startsWith('DIFERENCIA') ? '\n      OBTENIDO: …${ventana(on)}…\n      ESPERADO: …${ventana(en)}…' : ''}');
    }
  }
  stdout.writeln('Documentos: ${datos.where((d) => (d['articuloEsperado'] as String? ?? '').isNotEmpty).length}');
  stdout.writeln('Idéntico: $exactos | idéntico tras normalizar N°/MDP-T: $normalizados | extraído más largo (recorte): $prefijos');
  stdout.writeln('CORTES (se perdió texto): $cortes | DIFERENCIAS de caracteres: $otros');
  stdout.writeln('CER (sin contar texto cortado): ${(errores / caracteres * 100).toStringAsFixed(2)}% ($errores/$caracteres)');
  detalle.forEach(stdout.writeln);
}
