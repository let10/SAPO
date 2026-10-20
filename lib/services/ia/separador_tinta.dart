import 'dart:typed_data';

import '../renderizador_pagina.dart';

/// Separa por color la tinta que interesa del resto de la página. Las
/// resoluciones llevan el número escrito a mano con bolígrafo azul sobre una
/// línea impresa en negro, y la fecha con un sello de tinta oscura: separarlas
/// por color deja el trazo limpio, sin la línea impresa ni el texto vecino.
///
/// Ambas funciones devuelven una [ImagenGris] con la convención del resto del
/// módulo: tinta oscura (0), fondo blanco (255).
class SeparadorTinta {
  /// Azulidad mínima (b − promedio de r y g) para considerar un píxel como
  /// tinta azul; por debajo, el color es gris/negro y no se cuenta.
  static const int _azulidadMinima = 22;

  /// Tinta de bolígrafo azul: cuanto más azul y oscuro el píxel, más tinta.
  static ImagenGris tintaAzul(ImagenColor imagen) {
    final n = imagen.ancho * imagen.alto;
    final salida = Uint8List(n)..fillRange(0, n, 255);
    final rgb = imagen.rgb;
    for (var i = 0, o = 0; i < n; i++, o += 3) {
      final r = rgb[o], g = rgb[o + 1], b = rgb[o + 2];
      final azulidad = b - ((r + g) >> 1);
      if (azulidad <= _azulidadMinima) continue;
      final luminancia = (r * 299 + g * 587 + b * 114) ~/ 1000;
      if (luminancia > 225) continue;
      final tinta = ((azulidad - _azulidadMinima) * 4).clamp(0, 255);
      salida[i] = 255 - tinta;
    }
    return ImagenGris(pixeles: salida, ancho: imagen.ancho, alto: imagen.alto);
  }

  /// Tinta oscura (sello, texto impreso): luminancia con estiramiento de
  /// contraste entre los percentiles 1 % y 99 %.
  static ImagenGris tintaOscura(ImagenColor imagen) {
    final n = imagen.ancho * imagen.alto;
    final lum = Uint8List(n);
    final hist = List<int>.filled(256, 0);
    final rgb = imagen.rgb;
    for (var i = 0, o = 0; i < n; i++, o += 3) {
      final v = (rgb[o] * 299 + rgb[o + 1] * 587 + rgb[o + 2] * 114) ~/ 1000;
      lum[i] = v;
      hist[v]++;
    }
    var acum = 0, lo = 0, hi = 255;
    for (var v = 0; v < 256; v++) {
      acum += hist[v];
      if (acum >= n * 0.01) {
        lo = v;
        break;
      }
    }
    acum = 0;
    for (var v = 255; v >= 0; v--) {
      acum += hist[v];
      if (acum >= n * 0.01) {
        hi = v;
        break;
      }
    }
    if (hi <= lo) {
      lo = 0;
      hi = 255;
    }
    final rango = hi - lo;
    for (var i = 0; i < n; i++) {
      lum[i] = ((lum[i] - lo) * 255 ~/ rango).clamp(0, 255);
    }
    return ImagenGris(pixeles: lum, ancho: imagen.ancho, alto: imagen.alto);
  }
}
