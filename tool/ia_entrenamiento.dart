// Núcleo de entrenamiento compartido por las herramientas de tool/: pasos de
// retropropagación y optimizador Adam, escritos a mano sobre las capas de
// lib/services/ia/capas_red.dart (sin librerías de aprendizaje automático).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:procesador_documental_mdp/services/ia/capas_red.dart';
import 'package:procesador_documental_mdp/services/ia/red_digitos.dart';

const _conv1Lado = RedDigitos.entradaLado - RedDigitos.conv1Nucleo + 1; // 24
const _pool1Lado = _conv1Lado ~/ 2; // 12
const _conv2Lado = _pool1Lado - RedDigitos.conv2Nucleo + 1; // 8

/// Estado del optimizador Adam para un arreglo de parámetros.
class _EstadoAdam {
  final Float32List m;
  final Float32List v;

  _EstadoAdam(int n)
      : m = Float32List(n),
        v = Float32List(n);

  void aplicar(Float32List parametros, Float32List gradiente, {required double tasa, required int paso}) {
    const beta1 = 0.9, beta2 = 0.999, epsilon = 1e-8;
    final correccion1 = 1 - math.pow(beta1, paso).toDouble();
    final correccion2 = 1 - math.pow(beta2, paso).toDouble();
    for (var i = 0; i < parametros.length; i++) {
      final g = gradiente[i];
      m[i] = beta1 * m[i] + (1 - beta1) * g;
      v[i] = beta2 * v[i] + (1 - beta2) * g * g;
      final mHat = m[i] / correccion1;
      final vHat = v[i] / correccion2;
      parametros[i] -= tasa * mHat / (math.sqrt(vHat) + epsilon);
    }
  }
}

/// Entrena una [RedDigitos] por lotes con Adam.
class EntrenadorRed {
  final RedDigitos red;
  late final List<_EstadoAdam> _adam = [
    _EstadoAdam(red.conv1Pesos.length),
    _EstadoAdam(red.conv1Sesgo.length),
    _EstadoAdam(red.conv2Pesos.length),
    _EstadoAdam(red.conv2Sesgo.length),
    _EstadoAdam(red.densa1Pesos.length),
    _EstadoAdam(red.densa1Sesgo.length),
    _EstadoAdam(red.densa2Pesos.length),
    _EstadoAdam(red.densa2Sesgo.length),
  ];
  int _paso = 0;

  EntrenadorRed(this.red);

  /// Un paso de Adam con el lote dado. Cada muestra puede traer un [peso]
  /// (por defecto 1) que escala su contribución a la pérdida. Devuelve la
  /// pérdida media del lote.
  double entrenarLote(List<Float32List> imagenes, List<int> etiquetas, {required double tasa, List<double>? pesos}) {
    final g = [
      Float32List(red.conv1Pesos.length),
      Float32List(red.conv1Sesgo.length),
      Float32List(red.conv2Pesos.length),
      Float32List(red.conv2Sesgo.length),
      Float32List(red.densa1Pesos.length),
      Float32List(red.densa1Sesgo.length),
      Float32List(red.densa2Pesos.length),
      Float32List(red.densa2Sesgo.length),
    ];
    var perdida = 0.0;
    var sumaPesos = 0.0;
    for (var k = 0; k < imagenes.length; k++) {
      final w = pesos == null ? 1.0 : pesos[k];
      perdida += w * _pasoMuestra(imagenes[k], etiquetas[k], g, w);
      sumaPesos += w;
    }
    if (sumaPesos <= 0) return 0;
    for (final a in g) {
      for (var i = 0; i < a.length; i++) {
        a[i] /= sumaPesos;
      }
    }
    _paso++;
    final params = [
      red.conv1Pesos,
      red.conv1Sesgo,
      red.conv2Pesos,
      red.conv2Sesgo,
      red.densa1Pesos,
      red.densa1Sesgo,
      red.densa2Pesos,
      red.densa2Sesgo,
    ];
    for (var i = 0; i < params.length; i++) {
      _adam[i].aplicar(params[i], g[i], tasa: tasa, paso: _paso);
    }
    return perdida / sumaPesos;
  }

  double _pasoMuestra(Float32List imagen, int etiqueta, List<Float32List> g, double peso) {
    final act = red.adelanteConCache(imagen);
    final perdida = -math.log(act.probabilidades[etiqueta].clamp(1e-7, 1.0));
    final dLogits = CapasRed.gradienteSoftmaxEntropiaCruzada(act.probabilidades, etiqueta);
    if (peso != 1.0) {
      for (var i = 0; i < dLogits.length; i++) {
        dLogits[i] *= peso;
      }
    }

    void sumar(Float32List destino, Float32List origen) {
      for (var i = 0; i < destino.length; i++) {
        destino[i] += origen[i];
      }
    }

    final (dDensa1ReluLocal, dP2, dS2) = CapasRed.densaAtras(
      entrada: act.densa1Relu,
      pesos: red.densa2Pesos,
      numEntradas: RedDigitos.densa1Salidas,
      numSalidas: RedDigitos.clases,
      dSalida: dLogits,
    );
    sumar(g[6], dP2);
    sumar(g[7], dS2);

    final dDensa1Pre = CapasRed.reluAtras(dDensa1ReluLocal, act.densa1Relu);
    final (dPool2Flat, dP1, dS1) = CapasRed.densaAtras(
      entrada: act.pool2,
      pesos: red.densa1Pesos,
      numEntradas: RedDigitos.densa1Entradas,
      numSalidas: RedDigitos.densa1Salidas,
      dSalida: dDensa1Pre,
    );
    sumar(g[4], dP1);
    sumar(g[5], dS1);

    final dConv2Relu = CapasRed.maxPool2x2Atras(
      dSalida: dPool2Flat,
      indicesMax: act.pool2Idx,
      altoE: _conv2Lado,
      anchoE: _conv2Lado,
      canales: RedDigitos.conv2Filtros,
    );
    final dConv2Pre = CapasRed.reluAtras(dConv2Relu, act.conv2Relu);
    final (dPool1, dPc2, dSc2) = CapasRed.conv2dAtras(
      entrada: act.pool1,
      altoE: _pool1Lado,
      anchoE: _pool1Lado,
      canalesE: RedDigitos.conv1Filtros,
      pesos: red.conv2Pesos,
      canalesS: RedDigitos.conv2Filtros,
      nucleo: RedDigitos.conv2Nucleo,
      dSalida: dConv2Pre,
    );
    sumar(g[2], dPc2);
    sumar(g[3], dSc2);

    final dConv1Relu = CapasRed.maxPool2x2Atras(
      dSalida: dPool1,
      indicesMax: act.pool1Idx,
      altoE: _conv1Lado,
      anchoE: _conv1Lado,
      canales: RedDigitos.conv1Filtros,
    );
    final dConv1Pre = CapasRed.reluAtras(dConv1Relu, act.conv1Relu);
    final (_, dPc1, dSc1) = CapasRed.conv2dAtras(
      entrada: imagen,
      altoE: RedDigitos.entradaLado,
      anchoE: RedDigitos.entradaLado,
      canalesE: 1,
      pesos: red.conv1Pesos,
      canalesS: RedDigitos.conv1Filtros,
      nucleo: RedDigitos.conv1Nucleo,
      dSalida: dConv1Pre,
    );
    sumar(g[0], dPc1);
    sumar(g[1], dSc1);
    return perdida;
  }

  static double exactitud(RedDigitos red, List<Float32List> imagenes, List<int> etiquetas) {
    if (imagenes.isEmpty) return 0;
    var ok = 0;
    for (var i = 0; i < imagenes.length; i++) {
      if (red.adelanteConCache(imagenes[i]).prediccion == etiquetas[i]) ok++;
    }
    return ok / imagenes.length;
  }
}
