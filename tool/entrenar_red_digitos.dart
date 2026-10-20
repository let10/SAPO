// Entrena la red neuronal de reconocimiento de dígitos (ver
// lib/services/ia/red_digitos.dart) con el conjunto de datos MNIST, usando
// retropropagación escrita a mano (sin ninguna librería de aprendizaje
// automático; ver tool/ia_entrenamiento.dart).
//
// Requiere los archivos binarios generados a partir de MNIST en
// tool/datos_entrenamiento/ (mnist_train.bin, mnist_test.bin): cada muestra
// son 785 bytes (1 de etiqueta + 784 de píxeles 0-255), sin separadores.
//
// Uso:
//   dart run tool/entrenar_red_digitos.dart [muestras] [epocas] [tasa]
//   dart run tool/entrenar_red_digitos.dart 20000 10 0.001
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:procesador_documental_mdp/services/ia/red_digitos.dart';

import 'ia_entrenamiento.dart';

class ConjuntoMnist {
  final List<Float32List> imagenes;
  final List<int> etiquetas;

  ConjuntoMnist(this.imagenes, this.etiquetas);

  int get longitud => etiquetas.length;

  static ConjuntoMnist cargar(String ruta, {int? limite}) {
    final bytes = File(ruta).readAsBytesSync();
    final total = bytes.length ~/ 785;
    final n = limite == null ? total : math.min(limite, total);
    final imagenes = <Float32List>[];
    final etiquetas = <int>[];
    for (var i = 0; i < n; i++) {
      final base = i * 785;
      etiquetas.add(bytes[base]);
      final img = Float32List(784);
      for (var p = 0; p < 784; p++) {
        img[p] = bytes[base + 1 + p] / 255.0;
      }
      imagenes.add(img);
    }
    return ConjuntoMnist(imagenes, etiquetas);
  }
}

Future<void> main(List<String> args) async {
  final muestras = args.isNotEmpty ? int.parse(args[0]) : 20000;
  final epocas = args.length > 1 ? int.parse(args[1]) : 10;
  final tasa = args.length > 2 ? double.parse(args[2]) : 0.001;
  const tamanoLote = 32;

  const base = 'tool/datos_entrenamiento';
  stdout.writeln('Cargando MNIST ($muestras muestras de entrenamiento)...');
  final entrenamiento = ConjuntoMnist.cargar('$base/mnist_train.bin', limite: muestras);
  final prueba = ConjuntoMnist.cargar('$base/mnist_test.bin');
  stdout.writeln('Entrenamiento: ${entrenamiento.longitud} | Prueba: ${prueba.longitud}');

  final red = RedDigitos.aleatoria(semilla: 42);
  final entrenador = EntrenadorRed(red);

  final indices = List<int>.generate(entrenamiento.longitud, (i) => i);
  final aleatorio = math.Random(7);
  var mejorExactitud = 0.0;

  final cronometroTotal = Stopwatch()..start();
  for (var epoca = 1; epoca <= epocas; epoca++) {
    indices.shuffle(aleatorio);
    var perdidaEpoca = 0.0;
    final cronometroEpoca = Stopwatch()..start();

    for (var inicio = 0; inicio < indices.length; inicio += tamanoLote) {
      final fin = math.min(inicio + tamanoLote, indices.length);
      final lote = indices.sublist(inicio, fin);
      perdidaEpoca += entrenador.entrenarLote(
            [for (final i in lote) entrenamiento.imagenes[i]],
            [for (final i in lote) entrenamiento.etiquetas[i]],
            tasa: tasa,
          ) *
          lote.length;
    }

    final exactitudPrueba = EntrenadorRed.exactitud(
        red, prueba.imagenes.sublist(0, 2000), prueba.etiquetas.sublist(0, 2000));
    stdout.writeln('Época $epoca/$epocas — pérdida media: '
        '${(perdidaEpoca / entrenamiento.longitud).toStringAsFixed(4)} — '
        'exactitud (prueba, 2000): ${(exactitudPrueba * 100).toStringAsFixed(2)}% — '
        '${cronometroEpoca.elapsed.inSeconds}s');

    if (exactitudPrueba > mejorExactitud) {
      mejorExactitud = exactitudPrueba;
      final destino = File('assets/ia/red_digitos.bin');
      await destino.writeAsBytes(red.guardarPesos());
      stdout.writeln('  -> nuevo mejor modelo guardado en ${destino.path}');
    }
  }

  stdout.writeln('Entrenamiento total: ${cronometroTotal.elapsed.inMinutes} min');
  final exactitudFinal = EntrenadorRed.exactitud(red, prueba.imagenes, prueba.etiquetas);
  stdout.writeln('Exactitud final sobre las ${prueba.longitud} imágenes de prueba completas: '
      '${(exactitudFinal * 100).toStringAsFixed(2)}%');
  stdout.writeln('Mejor exactitud (submuestra) durante el entrenamiento: '
      '${(mejorExactitud * 100).toStringAsFixed(2)}%');

  exit(0);
}
