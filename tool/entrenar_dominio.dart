// Ajusta la red de dígitos al dominio real de las resoluciones: la escritura a
// mano del número ("numero") o el sello de la fecha ("sello"). Parte de los
// pesos entrenados con MNIST y los afina con los dígitos recortados de los
// documentos verificados (tool/construir_dataset_dominio.dart), con aumento de
// datos y, para el sello, dígitos sintéticos que cubren los que aún no
// aparecen en los documentos reales.
//
//   dart run tool/entrenar_dominio.dart <numero|sello> cv    [pasos=1500] [pliegues=6]
//   dart run tool/entrenar_dominio.dart <numero|sello> final [pasos=1500]
//
// "cv" valida con documentos que la red NO vio al entrenar (validación cruzada
// por documento) y compara contra la red de MNIST sin afinar. "final" entrena
// con todos los documentos y guarda assets/ia/red_<modo>.bin.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:procesador_documental_mdp/services/ia/red_digitos.dart';

import 'entrenar_red_digitos.dart' show ConjuntoMnist;
import 'ia_aumento.dart';
import 'ia_entrenamiento.dart';

const _carpeta = 'tool/datos_entrenamiento';

/// Engrosa el trazo con un desenfoque 3×3 y renormaliza el máximo a 1: los
/// trazos de bolígrafo, una vez reducidos a 28×28, son mucho más finos que los
/// de MNIST.
Float32List _engrosar(Float32List p, int pasadas) {
  var a = p;
  for (var k = 0; k < pasadas; k++) {
    final o = Float32List(784);
    var maximo = 0.0;
    for (var y = 0; y < 28; y++) {
      for (var x = 0; x < 28; x++) {
        var s = 0.0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= 28 || yy >= 28) continue;
            final peso = (dx == 0 ? 2 : 1) * (dy == 0 ? 2 : 1);
            s += a[yy * 28 + xx] * peso;
          }
        }
        o[y * 28 + x] = s / 16;
        if (o[y * 28 + x] > maximo) maximo = o[y * 28 + x];
      }
    }
    if (maximo > 0) {
      for (var i = 0; i < 784; i++) {
        o[i] = (o[i] / maximo).clamp(0.0, 1.0);
      }
    }
    a = o;
  }
  return a;
}

int _pasadasEngrosar = 0;

class _Muestras {
  final List<Float32List> imagenes = [];
  final List<int> etiquetas = [];
  final List<int> documentos = [];

  void agregar(Float32List i, int e, int d) {
    imagenes.add(i);
    etiquetas.add(e);
    documentos.add(d);
  }

  int get longitud => etiquetas.length;

  static _Muestras cargar(String ruta) {
    final m = _Muestras();
    final f = File(ruta);
    if (!f.existsSync()) return m;
    final b = f.readAsBytesSync();
    for (var o = 0; o + 787 <= b.length; o += 787) {
      final p = Float32List(784);
      for (var i = 0; i < 784; i++) {
        p[i] = b[o + 3 + i] / 255.0;
      }
      m.agregar(_pasadasEngrosar > 0 ? _engrosar(p, _pasadasEngrosar) : p, b[o], b[o + 1] | (b[o + 2] << 8));
    }
    return m;
  }

  _Muestras filtrar(bool Function(int doc) incluir) {
    final m = _Muestras();
    for (var i = 0; i < longitud; i++) {
      if (incluir(documentos[i])) m.agregar(imagenes[i], etiquetas[i], documentos[i]);
    }
    return m;
  }
}

RedDigitos _redMnist() =>
    RedDigitos.cargarPesos(ByteData.sublistView(File('assets/ia/red_digitos.bin').readAsBytesSync()));

RedDigitos _entrenar({
  required String modo,
  required _Muestras reales,
  required List<Float32List> sinteticos,
  required List<int> etiquetasSinteticas,
  required ConjuntoMnist mnist,
  required int pasos,
  required int semilla,
}) {
  final r = math.Random(semilla);
  final red = _redMnist();
  final entrenador = EntrenadorRed(red);
  final esNumero = modo == 'numero';
  for (var paso = 0; paso < pasos; paso++) {
    final tasa = paso < pasos * 0.6 ? 0.001 : 0.0003;
    final lote = <Float32List>[];
    final etiquetas = <int>[];
    final pesos = <double>[];

    final nReales = reales.longitud == 0 ? 0 : (esNumero ? 16 : 12);
    for (var k = 0; k < nReales; k++) {
      final i = r.nextInt(reales.longitud);
      lote.add(esNumero
          ? aumentar(reales.imagenes[i], r)
          : aumentar(reales.imagenes[i], r, rotacion: 0.1, inclinacion: 0.1, escala: 0.12));
      etiquetas.add(reales.etiquetas[i]);
      pesos.add(1.0);
    }
    if (esNumero) {
      for (var k = 0; k < 16; k++) {
        final i = r.nextInt(mnist.longitud);
        lote.add(mnist.imagenes[i]);
        etiquetas.add(mnist.etiquetas[i]);
        pesos.add(1.0);
      }
    } else {
      for (var k = 0; k < 20; k++) {
        final i = r.nextInt(sinteticos.length);
        lote.add(aumentar(sinteticos[i], r, rotacion: 0.08, inclinacion: 0.08, escala: 0.1, desplazamiento: 1.5));
        etiquetas.add(etiquetasSinteticas[i]);
        pesos.add(0.7);
      }
    }
    entrenador.entrenarLote(lote, etiquetas, tasa: tasa, pesos: pesos);
  }
  return red;
}

/// Exactitud por dígito y por grupo (número completo / día completo): un grupo
/// acierta si aciertan todos los dígitos que lo forman.
({double digitos, double grupos, int nDigitos, int nGrupos}) _evaluar(RedDigitos red, _Muestras m) {
  var ok = 0;
  final aciertoPorDoc = <int, bool>{};
  for (var i = 0; i < m.longitud; i++) {
    final acierta = red.adelanteConCache(m.imagenes[i]).prediccion == m.etiquetas[i];
    if (acierta) ok++;
    aciertoPorDoc[m.documentos[i]] = (aciertoPorDoc[m.documentos[i]] ?? true) && acierta;
  }
  final gruposOk = aciertoPorDoc.values.where((v) => v).length;
  return (
    digitos: m.longitud == 0 ? 0 : ok / m.longitud,
    grupos: aciertoPorDoc.isEmpty ? 0 : gruposOk / aciertoPorDoc.length,
    nDigitos: m.longitud,
    nGrupos: aciertoPorDoc.length,
  );
}

String _pct(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// Para cada documento: confianza de la red (producto de la probabilidad del
/// dígito elegido) y si acertó todos los dígitos.
List<(double, bool)> _confianzaPorGrupo(RedDigitos red, _Muestras m) {
  final conf = <int, double>{};
  final ok = <int, bool>{};
  for (var i = 0; i < m.longitud; i++) {
    final p = red.reconocer(m.imagenes[i]);
    var mejor = 0;
    for (var k = 1; k < p.length; k++) {
      if (p[k] > p[mejor]) mejor = k;
    }
    conf[m.documentos[i]] = (conf[m.documentos[i]] ?? 1.0) * p[mejor];
    ok[m.documentos[i]] = (ok[m.documentos[i]] ?? true) && mejor == m.etiquetas[i];
  }
  return [for (final d in conf.keys) (conf[d]!, ok[d]!)];
}

void _imprimirCalibracion(List<(double, bool)> g) {
  g.sort((a, b) => b.$1.compareTo(a.$1));
  for (final t in [0.99, 0.97, 0.95, 0.9, 0.8, 0.6]) {
    final sel = g.where((e) => e.$1 >= t).toList();
    final ok = sel.where((e) => e.$2).length;
    stdout.writeln('  confianza ≥ $t: ${sel.length}/${g.length} grupos, correctos $ok'
        '${sel.isEmpty ? '' : ' (${_pct(ok / sel.length)})'}');
  }
  stdout.writeln('  errores con su confianza: ${g.where((e) => !e.$2).map((e) => e.$1.toStringAsFixed(3)).join(', ')}');
}

Future<void> main(List<String> args) async {
  final modo = args[0];
  final accion = args[1];
  final pasos = args.length > 2 ? int.parse(args[2]) : 1500;
  final pliegues = args.length > 3 ? int.parse(args[3]) : 6;
  _pasadasEngrosar = args.length > 4 ? int.parse(args[4]) : 0;

  final mnist = ConjuntoMnist.cargar('$_carpeta/mnist_train.bin', limite: 12000);

  // Datos reales del dominio. En el sello, el "grupo" evaluado es el día (2
  // dígitos), así que solo los dígitos del día se usan para evaluar.
  final numero = _Muestras.cargar('$_carpeta/dominio_numero.bin');
  final dia = _Muestras.cargar('$_carpeta/dominio_sello_dia.bin');
  final anio = _Muestras.cargar('$_carpeta/dominio_sello_anio.bin');
  final reales = modo == 'numero' ? numero : (_Muestras()..agregarTodo(dia)..agregarTodo(anio));
  final aEvaluar = modo == 'numero' ? numero : dia;

  // Sintéticos tipo sello (solo para el modo sello).
  final sinteticos = <Float32List>[];
  final etiquetasSinteticas = <int>[];
  if (modo == 'sello') {
    final r = math.Random(99);
    for (var d = 0; d < 10; d++) {
      for (var k = 0; k < 250; k++) {
        sinteticos.add(GeneradorSello.digito(d, r));
        etiquetasSinteticas.add(d);
      }
    }
    stdout.writeln('Sintéticos tipo sello generados: ${sinteticos.length}');
  }
  stdout.writeln('Muestras reales ($modo): ${reales.longitud} (a evaluar: ${aEvaluar.longitud})');

  if (accion == 'final') {
    final red = _entrenar(
        modo: modo,
        reales: reales,
        sinteticos: sinteticos,
        etiquetasSinteticas: etiquetasSinteticas,
        mnist: mnist,
        pasos: pasos,
        semilla: 1);
    final e = _evaluar(red, aEvaluar);
    stdout.writeln('Exactitud sobre los propios datos de entrenamiento (NO es una estimación honesta): '
        'dígitos ${_pct(e.digitos)}, grupos ${_pct(e.grupos)}');
    final destino = File('assets/ia/red_$modo.bin');
    destino.writeAsBytesSync(red.guardarPesos());
    stdout.writeln('Guardado: ${destino.path}');
    exit(0);
  }

  // Validación cruzada por documento.
  final docs = aEvaluar.documentos.toSet().toList()..shuffle(math.Random(5));
  final base = _evaluar(_redMnist(), aEvaluar);
  stdout.writeln('Red MNIST SIN afinar sobre todos los documentos: dígitos ${_pct(base.digitos)}, grupos ${_pct(base.grupos)}');

  final confusionesBase = <String, int>{};
  final base0 = _redMnist();
  for (var i = 0; i < aEvaluar.longitud; i++) {
    final p = base0.adelanteConCache(aEvaluar.imagenes[i]).prediccion;
    if (p != aEvaluar.etiquetas[i]) {
      final k = '${aEvaluar.etiquetas[i]}→$p';
      confusionesBase[k] = (confusionesBase[k] ?? 0) + 1;
    }
  }
  stdout.writeln('Confusiones de la red MNIST sin afinar: ${(confusionesBase.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key}×${e.value}').join('  ')}');
  final confusionesAfinada = <String, int>{};
  final calibracion = <(double, bool)>[];
  stdout.writeln('Calibración de la red MNIST sin afinar:');
  _imprimirCalibracion(_confianzaPorGrupo(_redMnist(), aEvaluar));

  var okDigitos = 0, totDigitos = 0, okGrupos = 0, totGrupos = 0;
  for (var k = 0; k < pliegues; k++) {
    final fuera = <int>{for (var i = k; i < docs.length; i += pliegues) docs[i]};
    final entrenamiento = reales.filtrar((d) => !fuera.contains(d));
    final prueba = aEvaluar.filtrar(fuera.contains);
    final red = _entrenar(
        modo: modo,
        reales: entrenamiento,
        sinteticos: sinteticos,
        etiquetasSinteticas: etiquetasSinteticas,
        mnist: mnist,
        pasos: pasos,
        semilla: 10 + k);
    final e = _evaluar(red, prueba);
    for (var i = 0; i < prueba.longitud; i++) {
      final p = red.adelanteConCache(prueba.imagenes[i]).prediccion;
      if (p != prueba.etiquetas[i]) {
        final c = '${prueba.etiquetas[i]}→$p';
        confusionesAfinada[c] = (confusionesAfinada[c] ?? 0) + 1;
      }
    }
    calibracion.addAll(_confianzaPorGrupo(red, prueba));
    okDigitos += (e.digitos * e.nDigitos).round();
    totDigitos += e.nDigitos;
    okGrupos += (e.grupos * e.nGrupos).round();
    totGrupos += e.nGrupos;
    stdout.writeln('  pliegue ${k + 1}/$pliegues: ${e.nGrupos} documentos fuera → dígitos ${_pct(e.digitos)}, grupos ${_pct(e.grupos)}');
  }
  stdout.writeln('Confusiones de la red afinada: ${(confusionesAfinada.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => '${e.key}×${e.value}').join('  ')}');
  stdout.writeln('Calibración de la red afinada (documentos fuera de entrenamiento):');
  _imprimirCalibracion(calibracion);
  stdout.writeln('VALIDACIÓN CRUZADA ($modo): dígitos ${_pct(okDigitos / totDigitos)} '
      '($okDigitos/$totDigitos), grupos completos ${_pct(okGrupos / totGrupos)} ($okGrupos/$totGrupos)');
  exit(0);
}

extension on _Muestras {
  void agregarTodo(_Muestras o) {
    for (var i = 0; i < o.longitud; i++) {
      agregar(o.imagenes[i], o.etiquetas[i], o.documentos[i]);
    }
  }
}
