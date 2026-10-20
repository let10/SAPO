import 'dart:typed_data';

import '../renderizador_pagina.dart';
import 'red_digitos.dart';

/// Separa una imagen en escala de grises (como las que produce
/// `RenderizadorPagina.renderizarGrisado`) en recortes de 28×28, uno por cada
/// dígito que encuentra, de izquierda a derecha. Pensado para una franja
/// corta ya recortada alrededor del número o la fecha (no una página entera).
class SegmentadorDigitos {
  /// Umbral de binarización (0-255): un píxel es "tinta" si es más oscuro que
  /// este valor. Se calcula con Otsu sobre la propia franja.
  static int umbralOtsu(Uint8List pixeles) {
    final hist = List<int>.filled(256, 0);
    for (final v in pixeles) {
      hist[v]++;
    }
    final total = pixeles.length;
    var sumaTotal = 0;
    for (var v = 0; v < 256; v++) {
      sumaTotal += v * hist[v];
    }
    var sumaFondo = 0, pesoFondo = 0;
    double mejor = -1;
    var umbral = 127;
    for (var v = 0; v < 256; v++) {
      pesoFondo += hist[v];
      if (pesoFondo == 0) continue;
      final pesoFrente = total - pesoFondo;
      if (pesoFrente == 0) break;
      sumaFondo += v * hist[v];
      final mediaFondo = sumaFondo / pesoFondo;
      final mediaFrente = (sumaTotal - sumaFondo) / pesoFrente;
      final varianza = pesoFondo.toDouble() * pesoFrente * (mediaFondo - mediaFrente) * (mediaFondo - mediaFrente);
      if (varianza > mejor) {
        mejor = varianza;
        umbral = v;
      }
    }
    return umbral;
  }

  /// Devuelve, para cada dígito detectado, una imagen 28×28 normalizada a
  /// [0,1] con la misma convención que MNIST (fondo ≈ 0, trazo ≈ 1). Si no
  /// detecta ninguna región de tinta, devuelve una lista vacía.
  static List<Float32List> segmentar(ImagenGris imagen) {
    final w = imagen.ancho, h = imagen.alto;
    final px = imagen.pixeles;
    final umbral = umbralOtsu(px);
    final esTinta = Uint8List(w * h);
    for (var i = 0; i < px.length; i++) {
      esTinta[i] = px[i] <= umbral ? 1 : 0;
    }

    // Proyección vertical: cuántos píxeles de tinta hay en cada columna.
    final porColumna = List<int>.filled(w, 0);
    for (var y = 0; y < h; y++) {
      final fila = y * w;
      for (var x = 0; x < w; x++) {
        porColumna[x] += esTinta[fila + x];
      }
    }

    // Agrupa columnas consecutivas con tinta en "manchas" (posibles dígitos),
    // tolerando huecos de hasta 2 columnas (para no partir un dígito con un
    // trazo delgado en el medio, como el "1").
    final manchas = <(int, int)>[];
    var inicio = -1;
    var ultimaConTinta = -1;
    for (var x = 0; x < w; x++) {
      if (porColumna[x] > 0) {
        if (inicio < 0) inicio = x;
        ultimaConTinta = x;
      } else if (inicio >= 0 && x - ultimaConTinta > 2) {
        manchas.add((inicio, ultimaConTinta));
        inicio = -1;
      }
    }
    if (inicio >= 0) manchas.add((inicio, ultimaConTinta));

    // Descarta manchas demasiado angostas (ruido, puntuación suelta).
    final anchoMinimo = (w * 0.02).clamp(1, 6).round();
    final validas = manchas.where((m) => (m.$2 - m.$1 + 1) >= anchoMinimo).toList();

    final resultado = <Float32List>[];
    for (final (x0, x1) in validas) {
      // Extensión vertical real del trazo dentro de esta mancha (recorta
      // márgenes en blanco arriba/abajo).
      var y0 = h, y1 = -1;
      for (var y = 0; y < h; y++) {
        final fila = y * w;
        for (var x = x0; x <= x1; x++) {
          if (esTinta[fila + x] != 0) {
            if (y < y0) y0 = y;
            if (y > y1) y1 = y;
            break;
          }
        }
      }
      if (y1 < y0) continue;

      resultado.add(_recortarYEscalar(px, w, x0, y0, x1, y1));
    }
    return resultado;
  }

  /// Recorta el rectángulo `[x0,x1] x [y0,y1]` (con un margen proporcional) y
  /// lo reescala a 28×28, invirtiendo la escala de grises para que el trazo
  /// quede cerca de 1 y el fondo cerca de 0 (convención de MNIST).
  static Float32List _recortarYEscalar(Uint8List gris, int anchoOriginal, int x0, int y0, int x1, int y1) {
    const lado = RedDigitos.entradaLado;
    final altoCaja = y1 - y0 + 1;
    final margen = (altoCaja * 0.18).round();

    final xi = (x0 - margen).clamp(0, anchoOriginal - 1);
    final xf = (x1 + margen);
    final yi = (y0 - margen);
    final yf = (y1 + margen);
    final anchoFinal = xf - xi + 1;
    final altoFinal = yf - yi + 1;

    final salida = Float32List(lado * lado);
    for (var oy = 0; oy < lado; oy++) {
      final sy = (yi + (oy / lado) * altoFinal).round();
      for (var ox = 0; ox < lado; ox++) {
        final sx = (xi + (ox / lado) * anchoFinal).round();
        final valor = _muestrear(gris, anchoOriginal, sx, sy);
        salida[oy * lado + ox] = (255 - valor) / 255.0;
      }
    }
    return salida;
  }

  static int _muestrear(Uint8List gris, int ancho, int x, int y) {
    if (x < 0 || y < 0 || x >= ancho) return 255;
    final idx = y * ancho + x;
    if (idx < 0 || idx >= gris.length) return 255;
    return gris[idx];
  }
}
