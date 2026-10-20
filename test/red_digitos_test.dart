import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:procesador_documental_mdp/services/ia/capas_red.dart';
import 'package:procesador_documental_mdp/services/ia/red_digitos.dart';
import 'package:procesador_documental_mdp/services/ia/segmentador_digitos.dart';
import 'package:procesador_documental_mdp/services/renderizador_pagina.dart';

void main() {
  group('CapasRed', () {
    test('conv2dAdelante: un filtro identidad reproduce el centro de la ventana', () {
      // Entrada 3x3, un canal; núcleo 3x3 con un 1 en el centro y 0 alrededor.
      final entrada = Float32List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final pesos = Float32List(9)..[4] = 1.0; // centro
      final sesgo = Float32List(1);
      final salida = CapasRed.conv2dAdelante(
        entrada: entrada,
        altoE: 3,
        anchoE: 3,
        canalesE: 1,
        pesos: pesos,
        sesgo: sesgo,
        canalesS: 1,
        nucleo: 3,
      );
      expect(salida, hasLength(1));
      expect(salida[0], closeTo(5.0, 1e-6)); // el valor central de la entrada
    });

    test('conv2dAtras: forma de los gradientes coincide con la de los parámetros', () {
      final entrada = Float32List(4 * 4);
      for (var i = 0; i < entrada.length; i++) {
        entrada[i] = i.toDouble();
      }
      final pesos = Float32List(2 * 1 * 3 * 3);
      final (dEntrada, dPesos, dSesgo) = CapasRed.conv2dAtras(
        entrada: entrada,
        altoE: 4,
        anchoE: 4,
        canalesE: 1,
        pesos: pesos,
        canalesS: 2,
        nucleo: 3,
        dSalida: Float32List(2 * 2 * 2), // salida 2x2, 2 canales
      );
      expect(dEntrada, hasLength(entrada.length));
      expect(dPesos, hasLength(pesos.length));
      expect(dSesgo, hasLength(2));
    });

    test('maxPool2x2: toma el máximo de cada ventana de 2x2', () {
      // 4x4, 1 canal.
      final entrada = Float32List.fromList([
        1, 2, 5, 6, //
        3, 4, 7, 8, //
        9, 10, 13, 14, //
        11, 12, 15, 16, //
      ]);
      final (salida, _) = CapasRed.maxPool2x2Adelante(entrada: entrada, altoE: 4, anchoE: 4, canales: 1);
      expect(salida, Float32List.fromList([4, 8, 12, 16]));
    });

    test('maxPool2x2Atras: el gradiente va solo a la posición ganadora', () {
      final entrada = Float32List.fromList([1, 5, 2, 3]);
      final (_, indices) = CapasRed.maxPool2x2Adelante(entrada: entrada, altoE: 2, anchoE: 2, canales: 1);
      final dEntrada = CapasRed.maxPool2x2Atras(
        dSalida: Float32List.fromList([10]),
        indicesMax: indices,
        altoE: 2,
        anchoE: 2,
        canales: 1,
      );
      expect(dEntrada, Float32List.fromList([0, 10, 0, 0])); // el "5" estaba en la posición 1
    });

    test('densaAdelante calcula pesos·entrada + sesgo', () {
      final entrada = Float32List.fromList([1, 2, 3]);
      final pesos = Float32List.fromList([1, 0, 0, 0, 1, 0]); // salida0=entrada0, salida1=entrada1
      final sesgo = Float32List.fromList([10, 20]);
      final salida = CapasRed.densaAdelante(entrada: entrada, pesos: pesos, sesgo: sesgo, numEntradas: 3, numSalidas: 2);
      expect(salida, Float32List.fromList([11, 22]));
    });

    test('softmax suma 1 y preserva el orden', () {
      final p = CapasRed.softmax(Float32List.fromList([1, 2, 3]));
      expect(p.reduce((a, b) => a + b), closeTo(1.0, 1e-5));
      expect(p[2], greaterThan(p[1]));
      expect(p[1], greaterThan(p[0]));
    });

    test('gradiente softmax+entropía cruzada: resta 1 en la clase correcta', () {
      final p = Float32List.fromList([0.2, 0.3, 0.5]);
      final g = CapasRed.gradienteSoftmaxEntropiaCruzada(p, 2);
      expect(g[0], closeTo(0.2, 1e-6));
      expect(g[1], closeTo(0.3, 1e-6));
      expect(g[2], closeTo(0.5 - 1.0, 1e-6));
    });

    test('reluAdelante y reluAtras', () {
      final y = CapasRed.reluAdelante(Float32List.fromList([-1, 0, 2]));
      expect(y, Float32List.fromList([0, 0, 2]));
      final dx = CapasRed.reluAtras(Float32List.fromList([5, 5, 5]), y);
      expect(dx, Float32List.fromList([0, 0, 5]));
    });
  });

  group('RedDigitos', () {
    test('una red con pesos aleatorios produce 10 probabilidades que suman 1', () {
      final red = RedDigitos.aleatoria(semilla: 1);
      final imagen = Float32List(28 * 28);
      final p = red.reconocer(imagen);
      expect(p, hasLength(10));
      expect(p.reduce((a, b) => a + b), closeTo(1.0, 1e-4));
      for (final v in p) {
        expect(v, greaterThanOrEqualTo(0));
      }
    });

    test('guardar y cargar pesos reproduce exactamente la misma red', () {
      final original = RedDigitos.aleatoria(semilla: 2);
      final bytes = original.guardarPesos();
      final cargada = RedDigitos.cargarPesos(ByteData.sublistView(bytes));

      final imagen = Float32List(28 * 28)..[100] = 0.7;
      final pOriginal = original.reconocer(imagen);
      final pCargada = cargada.reconocer(imagen);
      for (var i = 0; i < 10; i++) {
        expect(pCargada[i], closeTo(pOriginal[i], 1e-6));
      }
    });

    test('el tamaño del archivo de pesos coincide con la arquitectura', () {
      final red = RedDigitos.aleatoria(semilla: 3);
      final bytes = red.guardarPesos();
      const totalFloats = (8 * 1 * 5 * 5 + 8) + (16 * 8 * 5 * 5 + 16) + (32 * 256 + 32) + (10 * 32 + 10);
      expect(bytes.length, totalFloats * 4);
    });
  });

  group('SegmentadorDigitos', () {
    ImagenGris imagenSintetica(int ancho, int alto, List<(int, int, int, int)> rectangulosOscuros) {
      final px = Uint8List(ancho * alto)..fillRange(0, ancho * alto, 255);
      for (final (x0, y0, x1, y1) in rectangulosOscuros) {
        for (var y = y0; y <= y1; y++) {
          for (var x = x0; x <= x1; x++) {
            px[y * ancho + x] = 20;
          }
        }
      }
      return ImagenGris(pixeles: px, ancho: ancho, alto: alto);
    }

    test('separa dos manchas oscuras bien distanciadas en dos recortes de 28x28', () {
      final imagen = imagenSintetica(100, 40, [(10, 10, 25, 30), (60, 10, 75, 30)]);
      final recortes = SegmentadorDigitos.segmentar(imagen);
      expect(recortes, hasLength(2));
      for (final r in recortes) {
        expect(r, hasLength(28 * 28));
        for (final v in r) {
          expect(v, inInclusiveRange(0.0, 1.0));
        }
      }
    });

    test('una imagen completamente en blanco no produce ningún recorte', () {
      final imagen = imagenSintetica(50, 30, []);
      expect(SegmentadorDigitos.segmentar(imagen), isEmpty);
    });

    test('el trazo queda cerca de 1 y el fondo cerca de 0 (convención MNIST)', () {
      final imagen = imagenSintetica(40, 40, [(10, 10, 29, 29)]);
      final recortes = SegmentadorDigitos.segmentar(imagen);
      expect(recortes, hasLength(1));
      // El centro del recorte cae dentro del rectángulo oscuro → cerca de 1.
      final centro = recortes.first[14 * 28 + 14];
      expect(centro, greaterThan(0.5));
    });

    test('ignora manchas demasiado angostas (ruido)', () {
      final imagen = imagenSintetica(200, 40, [(10, 10, 11, 30), (100, 10, 115, 30)]);
      final recortes = SegmentadorDigitos.segmentar(imagen);
      expect(recortes, hasLength(1)); // la mancha de 2px de ancho se descarta
    });
  });
}
