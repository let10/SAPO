// Entrena la red de dígitos con MNIST pero con un aumento de datos agresivo
// (inclinación, rotación, escala, trazo fino o grueso, ruido) para que
// generalice a la escritura real de los documentos. Los dígitos reales del
// dominio (tool/datos_entrenamiento/dominio_numero.bin) NO se usan para
// entrenar: solo se miden, así que su exactitud es una estimación honesta.
//
//   dart run tool/entrenar_mnist_robusto.dart <salida.bin> [muestras=30000] [epocas=12] [tasa=0.001] [semilla=1]
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:procesador_documental_mdp/services/ia/red_digitos.dart';

import 'entrenar_red_digitos.dart' show ConjuntoMnist;
import 'ia_aumento.dart';
import 'ia_entrenamiento.dart';

({List<Float32List> imagenes, List<int> etiquetas}) _cargarDominio(String ruta) {
  final imagenes = <Float32List>[];
  final etiquetas = <int>[];
  final f = File(ruta);
  if (!f.existsSync()) return (imagenes: imagenes, etiquetas: etiquetas);
  final b = f.readAsBytesSync();
  for (var o = 0; o + 787 <= b.length; o += 787) {
    etiquetas.add(b[o]);
    final p = Float32List(784);
    for (var i = 0; i < 784; i++) {
      p[i] = b[o + 3 + i] / 255.0;
    }
    imagenes.add(p);
  }
  return (imagenes: imagenes, etiquetas: etiquetas);
}

Future<void> main(List<String> args) async {
  final salida = args[0];
  final muestras = args.length > 1 ? int.parse(args[1]) : 30000;
  final epocas = args.length > 2 ? int.parse(args[2]) : 12;
  final tasa = args.length > 3 ? double.parse(args[3]) : 0.001;
  final semilla = args.length > 4 ? int.parse(args[4]) : 1;
  const lote = 32;

  const base = 'tool/datos_entrenamiento';
  final entrenamiento = ConjuntoMnist.cargar('$base/mnist_train.bin', limite: muestras);
  final prueba = ConjuntoMnist.cargar('$base/mnist_test.bin', limite: 2000);
  final dominio = _cargarDominio('$base/dominio_numero.bin');
  stdout.writeln('MNIST entrenamiento: ${entrenamiento.longitud} | dígitos reales para evaluar: ${dominio.imagenes.length}');

  final red = RedDigitos.aleatoria(semilla: semilla);
  final entrenador = EntrenadorRed(red);
  final r = math.Random(semilla + 100);
  final indices = List<int>.generate(entrenamiento.longitud, (i) => i);

  for (var epoca = 1; epoca <= epocas; epoca++) {
    indices.shuffle(r);
    var perdida = 0.0;
    final cronometro = Stopwatch()..start();
    // La tasa baja a la mitad en el último tercio.
    final tasaEpoca = epoca > epocas * 2 / 3 ? tasa * 0.4 : tasa;
    for (var inicio = 0; inicio < indices.length; inicio += lote) {
      final fin = math.min(inicio + lote, indices.length);
      final ids = indices.sublist(inicio, fin);
      perdida += entrenador.entrenarLote(
            [
              for (final i in ids)
                // Una de cada cuatro muestras queda sin deformar.
                r.nextInt(4) == 0
                    ? entrenamiento.imagenes[i]
                    : aumentar(entrenamiento.imagenes[i], r,
                        rotacion: 0.35, inclinacion: 0.45, escala: 0.25, desplazamiento: 3.0, ruido: 0.05),
            ],
            [for (final i in ids) entrenamiento.etiquetas[i]],
            tasa: tasaEpoca,
          ) *
          ids.length;
    }
    final exMnist = EntrenadorRed.exactitud(red, prueba.imagenes, prueba.etiquetas);
    final exReal = EntrenadorRed.exactitud(red, dominio.imagenes, dominio.etiquetas);
    stdout.writeln('Época $epoca/$epocas — pérdida ${(perdida / entrenamiento.longitud).toStringAsFixed(4)} — '
        'MNIST ${(exMnist * 100).toStringAsFixed(1)}% — dígitos reales (no vistos) ${(exReal * 100).toStringAsFixed(1)}% — '
        '${cronometro.elapsed.inSeconds}s');
  }
  File(salida).writeAsBytesSync(red.guardarPesos());
  stdout.writeln('Guardado: $salida');
  exit(0);
}
