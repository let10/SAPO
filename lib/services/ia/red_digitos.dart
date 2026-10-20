import 'dart:math' as math;
import 'dart:typed_data';

import 'capas_red.dart';

/// Red neuronal convolucional pequeña para reconocer un dígito (0-9) escrito
/// en una imagen de 28x28 en escala de grises, igual que el conjunto MNIST
/// (fondo ≈ 0, trazo ≈ 1). Arquitectura clásica tipo LeNet:
///
/// ```
/// entrada 28x28x1
///   → Conv 5x5, 8 filtros   → ReLU → MaxPool 2x2   (24x24x8 → 12x12x8)
///   → Conv 5x5, 16 filtros  → ReLU → MaxPool 2x2   (8x8x16  → 4x4x16)
///   → Aplanar (256)
///   → Densa 256→32 → ReLU
///   → Densa 32→10  → Softmax
/// ```
///
/// No usa ninguna librería de aprendizaje automático: todas las capas están
/// escritas a mano en [CapasRed]. Esta clase solo hace la propagación hacia
/// adelante (inferencia); el entrenamiento vive aparte, en
/// `tool/entrenar_red_digitos.dart`, para no llevar código de entrenamiento
/// dentro de la aplicación ya compilada.
class RedDigitos {
  static const int entradaLado = 28;
  static const int conv1Filtros = 8;
  static const int conv1Nucleo = 5;
  static const int conv2Filtros = 16;
  static const int conv2Nucleo = 5;
  static const int densa1Salidas = 32;
  static const int clases = 10;

  // Dimensiones intermedias (derivadas de la arquitectura de arriba).
  static const int _conv1Lado = entradaLado - conv1Nucleo + 1; // 24
  static const int _pool1Lado = _conv1Lado ~/ 2; // 12
  static const int _conv2Lado = _pool1Lado - conv2Nucleo + 1; // 8
  static const int _pool2Lado = _conv2Lado ~/ 2; // 4
  static const int densa1Entradas = _pool2Lado * _pool2Lado * conv2Filtros; // 256

  Float32List conv1Pesos; // (8, 1, 5, 5)
  Float32List conv1Sesgo; // (8)
  Float32List conv2Pesos; // (16, 8, 5, 5)
  Float32List conv2Sesgo; // (16)
  Float32List densa1Pesos; // (32, 256)
  Float32List densa1Sesgo; // (32)
  Float32List densa2Pesos; // (10, 32)
  Float32List densa2Sesgo; // (10)

  RedDigitos({
    required this.conv1Pesos,
    required this.conv1Sesgo,
    required this.conv2Pesos,
    required this.conv2Sesgo,
    required this.densa1Pesos,
    required this.densa1Sesgo,
    required this.densa2Pesos,
    required this.densa2Sesgo,
  });

  /// Pesos aleatorios pequeños (inicialización de He), listos para entrenar.
  factory RedDigitos.aleatoria({int? semilla}) {
    final r = math.Random(semilla);
    Float32List inicializar(int n, int fanIn) {
      final l = Float32List(n);
      final escala = math.sqrt(2.0 / fanIn);
      for (var i = 0; i < n; i++) {
        // Aproximación normal(0,1) por suma de uniformes (Irwin–Hall).
        final u = (r.nextDouble() + r.nextDouble() + r.nextDouble() - 1.5) / 0.6614;
        l[i] = u * escala;
      }
      return l;
    }

    return RedDigitos(
      conv1Pesos: inicializar(conv1Filtros * 1 * conv1Nucleo * conv1Nucleo, conv1Nucleo * conv1Nucleo),
      conv1Sesgo: Float32List(conv1Filtros),
      conv2Pesos: inicializar(
          conv2Filtros * conv1Filtros * conv2Nucleo * conv2Nucleo, conv1Filtros * conv2Nucleo * conv2Nucleo),
      conv2Sesgo: Float32List(conv2Filtros),
      densa1Pesos: inicializar(densa1Salidas * densa1Entradas, densa1Entradas),
      densa1Sesgo: Float32List(densa1Salidas),
      densa2Pesos: inicializar(clases * densa1Salidas, densa1Salidas),
      densa2Sesgo: Float32List(clases),
    );
  }

  /// Reconoce un dígito. [imagen] debe tener 28×28 valores en [0,1] (fondo
  /// ≈ 0, trazo ≈ 1), fila por fila. Devuelve la probabilidad de cada clase
  /// (índice = dígito).
  Float32List reconocer(Float32List imagen) => _adelante(imagen).probabilidades;

  /// Igual que [reconocer], pero conserva todas las activaciones intermedias;
  /// lo usa el entrenamiento para la retropropagación.
  ActivacionesRed adelanteConCache(Float32List imagen) => _adelante(imagen);

  ActivacionesRed _adelante(Float32List imagen) {
    final conv1 = CapasRed.conv2dAdelante(
      entrada: imagen,
      altoE: entradaLado,
      anchoE: entradaLado,
      canalesE: 1,
      pesos: conv1Pesos,
      sesgo: conv1Sesgo,
      canalesS: conv1Filtros,
      nucleo: conv1Nucleo,
    );
    final conv1Relu = CapasRed.reluAdelante(conv1);
    final (pool1, pool1Idx) = CapasRed.maxPool2x2Adelante(
      entrada: conv1Relu,
      altoE: _conv1Lado,
      anchoE: _conv1Lado,
      canales: conv1Filtros,
    );

    final conv2 = CapasRed.conv2dAdelante(
      entrada: pool1,
      altoE: _pool1Lado,
      anchoE: _pool1Lado,
      canalesE: conv1Filtros,
      pesos: conv2Pesos,
      sesgo: conv2Sesgo,
      canalesS: conv2Filtros,
      nucleo: conv2Nucleo,
    );
    final conv2Relu = CapasRed.reluAdelante(conv2);
    final (pool2, pool2Idx) = CapasRed.maxPool2x2Adelante(
      entrada: conv2Relu,
      altoE: _conv2Lado,
      anchoE: _conv2Lado,
      canales: conv2Filtros,
    );

    // pool2 ya está "aplanado" en memoria (es un Float32List plano).
    final densa1 = CapasRed.densaAdelante(
      entrada: pool2,
      pesos: densa1Pesos,
      sesgo: densa1Sesgo,
      numEntradas: densa1Entradas,
      numSalidas: densa1Salidas,
    );
    final densa1Relu = CapasRed.reluAdelante(densa1);

    final densa2 = CapasRed.densaAdelante(
      entrada: densa1Relu,
      pesos: densa2Pesos,
      sesgo: densa2Sesgo,
      numEntradas: densa1Salidas,
      numSalidas: clases,
    );
    final probabilidades = CapasRed.softmax(densa2);

    return ActivacionesRed(
      imagen: imagen,
      conv1Relu: conv1Relu,
      pool1: pool1,
      pool1Idx: pool1Idx,
      conv2Relu: conv2Relu,
      pool2: pool2,
      pool2Idx: pool2Idx,
      densa1Relu: densa1Relu,
      logits: densa2,
      probabilidades: probabilidades,
    );
  }

  // ── Persistencia ───────────────────────────────────────────────────────

  /// Formato binario simple: cada arreglo de pesos, en el mismo orden que los
  /// campos de la clase, como float32 little-endian, uno tras otro (sin
  /// encabezado: las dimensiones están fijadas por la arquitectura).
  Uint8List guardarPesos() {
    final partes = [
      conv1Pesos, conv1Sesgo, //
      conv2Pesos, conv2Sesgo, //
      densa1Pesos, densa1Sesgo, //
      densa2Pesos, densa2Sesgo, //
    ];
    final total = partes.fold<int>(0, (s, p) => s + p.length);
    final bytes = Uint8List(total * 4);
    final vista = ByteData.view(bytes.buffer);
    var offset = 0;
    for (final p in partes) {
      for (final v in p) {
        vista.setFloat32(offset, v, Endian.little);
        offset += 4;
      }
    }
    return bytes;
  }

  factory RedDigitos.cargarPesos(ByteData datos) {
    var offset = 0;
    Float32List leer(int n) {
      final l = Float32List(n);
      for (var i = 0; i < n; i++) {
        l[i] = datos.getFloat32(offset, Endian.little);
        offset += 4;
      }
      return l;
    }

    return RedDigitos(
      conv1Pesos: leer(conv1Filtros * 1 * conv1Nucleo * conv1Nucleo),
      conv1Sesgo: leer(conv1Filtros),
      conv2Pesos: leer(conv2Filtros * conv1Filtros * conv2Nucleo * conv2Nucleo),
      conv2Sesgo: leer(conv2Filtros),
      densa1Pesos: leer(densa1Salidas * densa1Entradas),
      densa1Sesgo: leer(densa1Salidas),
      densa2Pesos: leer(clases * densa1Salidas),
      densa2Sesgo: leer(clases),
    );
  }
}

/// Activaciones intermedias de una pasada hacia adelante, necesarias para
/// calcular los gradientes durante el entrenamiento.
class ActivacionesRed {
  final Float32List imagen;
  final Float32List conv1Relu;
  final Float32List pool1;
  final Uint8List pool1Idx;
  final Float32List conv2Relu;
  final Float32List pool2;
  final Uint8List pool2Idx;
  final Float32List densa1Relu;
  final Float32List logits;
  final Float32List probabilidades;

  const ActivacionesRed({
    required this.imagen,
    required this.conv1Relu,
    required this.pool1,
    required this.pool1Idx,
    required this.conv2Relu,
    required this.pool2,
    required this.pool2Idx,
    required this.densa1Relu,
    required this.logits,
    required this.probabilidades,
  });

  int get prediccion {
    var mejor = 0;
    for (var i = 1; i < probabilidades.length; i++) {
      if (probabilidades[i] > probabilidades[mejor]) mejor = i;
    }
    return mejor;
  }
}
