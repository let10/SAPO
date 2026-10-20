import 'dart:math' as math;
import 'dart:typed_data';

/// Operaciones de una red neuronal convolucional pequeña, escritas a mano
/// (sin ninguna librería de aprendizaje automático). Cada función de
/// propagación hacia adelante tiene su contraparte de retropropagación, usada
/// solo durante el entrenamiento (ver `tool/entrenar_red_digitos.dart`).
///
/// Convención de datos: los mapas de características 3D (alto x ancho x
/// canales) se guardan en un `Float32List` plano, en orden
/// `indice = (y * ancho + x) * canales + canal`.
class CapasRed {
  // ── Convolución 2D (sin relleno, paso 1) ──────────────────────────────────

  /// [pesos] en orden `(canalSalida, canalEntrada, ky, kx)`.
  static Float32List conv2dAdelante({
    required Float32List entrada,
    required int altoE,
    required int anchoE,
    required int canalesE,
    required Float32List pesos,
    required Float32List sesgo,
    required int canalesS,
    required int nucleo,
  }) {
    final altoS = altoE - nucleo + 1;
    final anchoS = anchoE - nucleo + 1;
    final salida = Float32List(altoS * anchoS * canalesS);

    for (var oy = 0; oy < altoS; oy++) {
      for (var ox = 0; ox < anchoS; ox++) {
        for (var oc = 0; oc < canalesS; oc++) {
          var acumulado = sesgo[oc];
          for (var ic = 0; ic < canalesE; ic++) {
            for (var ky = 0; ky < nucleo; ky++) {
              final filaE = (oy + ky) * anchoE;
              final filaPeso = ((oc * canalesE + ic) * nucleo + ky) * nucleo;
              for (var kx = 0; kx < nucleo; kx++) {
                final valorE = entrada[(filaE + ox + kx) * canalesE + ic];
                acumulado += valorE * pesos[filaPeso + kx];
              }
            }
          }
          salida[(oy * anchoS + ox) * canalesS + oc] = acumulado;
        }
      }
    }
    return salida;
  }

  /// Gradientes de la convolución: devuelve `(dEntrada, dPesos, dSesgo)`.
  static (Float32List, Float32List, Float32List) conv2dAtras({
    required Float32List entrada,
    required int altoE,
    required int anchoE,
    required int canalesE,
    required Float32List pesos,
    required int canalesS,
    required int nucleo,
    required Float32List dSalida,
  }) {
    final altoS = altoE - nucleo + 1;
    final anchoS = anchoE - nucleo + 1;
    final dEntrada = Float32List(entrada.length);
    final dPesos = Float32List(pesos.length);
    final dSesgo = Float32List(canalesS);

    for (var oy = 0; oy < altoS; oy++) {
      for (var ox = 0; ox < anchoS; ox++) {
        for (var oc = 0; oc < canalesS; oc++) {
          final grad = dSalida[(oy * anchoS + ox) * canalesS + oc];
          if (grad == 0) continue;
          dSesgo[oc] += grad;
          for (var ic = 0; ic < canalesE; ic++) {
            for (var ky = 0; ky < nucleo; ky++) {
              final filaE = (oy + ky) * anchoE;
              final filaPeso = ((oc * canalesE + ic) * nucleo + ky) * nucleo;
              for (var kx = 0; kx < nucleo; kx++) {
                final idxE = (filaE + ox + kx) * canalesE + ic;
                dPesos[filaPeso + kx] += entrada[idxE] * grad;
                dEntrada[idxE] += pesos[filaPeso + kx] * grad;
              }
            }
          }
        }
      }
    }
    return (dEntrada, dPesos, dSesgo);
  }

  // ── Max-pooling 2x2, paso 2 ────────────────────────────────────────────────

  /// Devuelve `(salida, indicesMax)`; `indicesMax[i]` guarda, para cada
  /// posición de salida y canal, cuál de las 4 posiciones de la ventana ganó
  /// (0..3), para poder propagar el gradiente solo a esa posición.
  static (Float32List, Uint8List) maxPool2x2Adelante({
    required Float32List entrada,
    required int altoE,
    required int anchoE,
    required int canales,
  }) {
    final altoS = altoE ~/ 2;
    final anchoS = anchoE ~/ 2;
    final salida = Float32List(altoS * anchoS * canales);
    final indices = Uint8List(altoS * anchoS * canales);

    for (var oy = 0; oy < altoS; oy++) {
      for (var ox = 0; ox < anchoS; ox++) {
        for (var c = 0; c < canales; c++) {
          var mejor = double.negativeInfinity;
          var mejorIdx = 0;
          for (var dy = 0; dy < 2; dy++) {
            for (var dx = 0; dx < 2; dx++) {
              final y = oy * 2 + dy, x = ox * 2 + dx;
              final v = entrada[(y * anchoE + x) * canales + c];
              if (v > mejor) {
                mejor = v;
                mejorIdx = dy * 2 + dx;
              }
            }
          }
          final idxS = (oy * anchoS + ox) * canales + c;
          salida[idxS] = mejor;
          indices[idxS] = mejorIdx;
        }
      }
    }
    return (salida, indices);
  }

  static Float32List maxPool2x2Atras({
    required Float32List dSalida,
    required Uint8List indicesMax,
    required int altoE,
    required int anchoE,
    required int canales,
  }) {
    final altoS = altoE ~/ 2;
    final anchoS = anchoE ~/ 2;
    final dEntrada = Float32List(altoE * anchoE * canales);

    for (var oy = 0; oy < altoS; oy++) {
      for (var ox = 0; ox < anchoS; ox++) {
        for (var c = 0; c < canales; c++) {
          final idxS = (oy * anchoS + ox) * canales + c;
          final mejorIdx = indicesMax[idxS];
          final dy = mejorIdx ~/ 2, dx = mejorIdx % 2;
          final y = oy * 2 + dy, x = ox * 2 + dx;
          dEntrada[(y * anchoE + x) * canales + c] += dSalida[idxS];
        }
      }
    }
    return dEntrada;
  }

  // ── Capa densa (totalmente conectada) ─────────────────────────────────────

  /// [pesos] en orden `(salida, entrada)`.
  static Float32List densaAdelante({
    required Float32List entrada,
    required Float32List pesos,
    required Float32List sesgo,
    required int numEntradas,
    required int numSalidas,
  }) {
    final salida = Float32List(numSalidas);
    for (var o = 0; o < numSalidas; o++) {
      var acumulado = sesgo[o];
      final fila = o * numEntradas;
      for (var i = 0; i < numEntradas; i++) {
        acumulado += entrada[i] * pesos[fila + i];
      }
      salida[o] = acumulado;
    }
    return salida;
  }

  static (Float32List, Float32List, Float32List) densaAtras({
    required Float32List entrada,
    required Float32List pesos,
    required int numEntradas,
    required int numSalidas,
    required Float32List dSalida,
  }) {
    final dEntrada = Float32List(numEntradas);
    final dPesos = Float32List(pesos.length);
    final dSesgo = Float32List(numSalidas);
    for (var o = 0; o < numSalidas; o++) {
      final grad = dSalida[o];
      dSesgo[o] = grad;
      final fila = o * numEntradas;
      for (var i = 0; i < numEntradas; i++) {
        dPesos[fila + i] = entrada[i] * grad;
        dEntrada[i] += pesos[fila + i] * grad;
      }
    }
    return (dEntrada, dPesos, dSesgo);
  }

  // ── Activaciones y pérdida ─────────────────────────────────────────────────

  static Float32List reluAdelante(Float32List x) {
    final y = Float32List(x.length);
    for (var i = 0; i < x.length; i++) {
      y[i] = x[i] > 0 ? x[i] : 0;
    }
    return y;
  }

  static Float32List reluAtras(Float32List dY, Float32List salidaRelu) {
    final dX = Float32List(dY.length);
    for (var i = 0; i < dY.length; i++) {
      dX[i] = salidaRelu[i] > 0 ? dY[i] : 0;
    }
    return dX;
  }

  static Float32List softmax(Float32List logits) {
    var maximo = logits[0];
    for (final v in logits) {
      if (v > maximo) maximo = v;
    }
    final exp = Float32List(logits.length);
    var suma = 0.0;
    for (var i = 0; i < logits.length; i++) {
      exp[i] = _exp(logits[i] - maximo);
      suma += exp[i];
    }
    for (var i = 0; i < exp.length; i++) {
      exp[i] = exp[i] / suma;
    }
    return exp;
  }

  /// Gradiente de softmax + entropía cruzada combinados (`probabilidad - 1`
  /// en la clase correcta): la simplificación clásica que evita calcular el
  /// logaritmo en la retropropagación.
  static Float32List gradienteSoftmaxEntropiaCruzada(Float32List probabilidades, int etiquetaVerdadera) {
    final d = Float32List.fromList(probabilidades);
    d[etiquetaVerdadera] -= 1.0;
    return d;
  }

  static double _exp(double x) {
    // Evita overflow/underflow para valores muy negativos.
    if (x < -40) return 0.0;
    return math.exp(x);
  }
}
