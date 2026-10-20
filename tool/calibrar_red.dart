// Mide la calibración de una red ya entrenada sobre un conjunto del dominio:
// para cada documento, la confianza que reporta (producto de la probabilidad de
// cada dígito) frente a si acertó todos los dígitos. Solo es una estimación
// honesta si la red no se entrenó con ese conjunto.
//   dart run tool/calibrar_red.dart <modelo.bin> <numero|sello_dia>
import 'dart:io';
import 'dart:typed_data';

import 'package:procesador_documental_mdp/services/ia/red_digitos.dart';

void main(List<String> args) {
  final red = RedDigitos.cargarPesos(ByteData.sublistView(File(args[0]).readAsBytesSync()));
  final b = File('tool/datos_entrenamiento/dominio_${args[1]}.bin').readAsBytesSync();
  final conf = <int, double>{};
  final ok = <int, bool>{};
  var digitosOk = 0, digitos = 0;
  for (var o = 0; o + 787 <= b.length; o += 787) {
    final p = Float32List(784);
    for (var i = 0; i < 784; i++) {
      p[i] = b[o + 3 + i] / 255.0;
    }
    final doc = b[o + 1] | (b[o + 2] << 8);
    final pr = red.reconocer(p);
    var mejor = 0;
    for (var k = 1; k < pr.length; k++) {
      if (pr[k] > pr[mejor]) mejor = k;
    }
    conf[doc] = (conf[doc] ?? 1.0) * pr[mejor];
    ok[doc] = (ok[doc] ?? true) && mejor == b[o];
    digitos++;
    if (mejor == b[o]) digitosOk++;
  }
  final g = [for (final d in conf.keys) (conf[d]!, ok[d]!)]..sort((a, b) => b.$1.compareTo(a.$1));
  stdout.writeln('Dígitos: $digitosOk/$digitos | grupos completos: ${g.where((e) => e.$2).length}/${g.length}');
  for (final t in [0.99, 0.97, 0.95, 0.9, 0.8, 0.6]) {
    final sel = g.where((e) => e.$1 >= t).toList();
    final n = sel.where((e) => e.$2).length;
    stdout.writeln('  confianza ≥ $t: ${sel.length} grupos, correctos $n');
  }
  stdout.writeln('  errores con su confianza: ${g.where((e) => !e.$2).map((e) => e.$1.toStringAsFixed(3)).join(', ')}');
}
