// Aumento de datos y dígitos sintéticos para entrenar las redes del dominio
// (herramientas de tool/; no forma parte de la aplicación).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:procesador_documental_mdp/services/ia/segmentador_componentes.dart';
import 'package:procesador_documental_mdp/services/renderizador_pagina.dart';

const _lado = 28;

double _muestrear(Float32List p, double x, double y) {
  final x0 = x.floor(), y0 = y.floor();
  final fx = x - x0, fy = y - y0;
  double v(int xx, int yy) => (xx < 0 || yy < 0 || xx >= _lado || yy >= _lado) ? 0.0 : p[yy * _lado + xx];
  return v(x0, y0) * (1 - fx) * (1 - fy) + v(x0 + 1, y0) * fx * (1 - fy) + v(x0, y0 + 1) * (1 - fx) * fy + v(x0 + 1, y0 + 1) * fx * fy;
}

/// Deformación aleatoria de un parche 28×28: rotación, inclinación, escala,
/// desplazamiento, grosor del trazo y ruido. Imita la variación natural entre
/// una y otra escritura (o entre dos impresiones de un mismo sello).
Float32List aumentar(
  Float32List p,
  math.Random r, {
  double rotacion = 0.26,
  double inclinacion = 0.3,
  double escala = 0.15,
  double desplazamiento = 2.0,
  double ruido = 0.03,
}) {
  double u(double a) => (r.nextDouble() * 2 - 1) * a;
  final ang = u(rotacion), sh = u(inclinacion);
  final sx = 1 + u(escala), sy = 1 + u(escala);
  final tx = u(desplazamiento), ty = u(desplazamiento);
  // Matriz directa A = R · Sh · S ; se usa su inversa para muestrear.
  final c = math.cos(ang), s = math.sin(ang);
  final a11 = (c * sx), a12 = (c * sh * sy - s * sy), a21 = (s * sx), a22 = (s * sh * sy + c * sy);
  final det = a11 * a22 - a12 * a21;
  final i11 = a22 / det, i12 = -a12 / det, i21 = -a21 / det, i22 = a11 / det;

  var salida = Float32List(_lado * _lado);
  const cx = 13.5, cy = 13.5;
  for (var y = 0; y < _lado; y++) {
    for (var x = 0; x < _lado; x++) {
      final dx = x - cx - tx, dy = y - cy - ty;
      salida[y * _lado + x] = _muestrear(p, i11 * dx + i12 * dy + cx, i21 * dx + i22 * dy + cy);
    }
  }

  final grosor = r.nextDouble();
  if (grosor < 0.25) {
    salida = _morfologia(salida, dilatar: true);
  } else if (grosor < 0.33) {
    salida = _morfologia(salida, dilatar: false);
  }
  if (ruido > 0) {
    for (var i = 0; i < salida.length; i++) {
      salida[i] = (salida[i] + u(ruido)).clamp(0.0, 1.0);
    }
  }
  return salida;
}

Float32List _morfologia(Float32List p, {required bool dilatar}) {
  final o = Float32List(p.length);
  for (var y = 0; y < _lado; y++) {
    for (var x = 0; x < _lado; x++) {
      var m = dilatar ? 0.0 : 1.0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx, yy = y + dy;
          final v = (xx < 0 || yy < 0 || xx >= _lado || yy >= _lado) ? 0.0 : p[yy * _lado + xx];
          if (dilatar ? v > m : v < m) m = v;
        }
      }
      o[y * _lado + x] = m;
    }
  }
  return o;
}

/// Dígitos sintéticos con el aspecto de los sellos de goma de la fecha: una
/// tipografía condensada, trazo grueso y tinta despareja. Se dibujan con la
/// fuente de mapa de bits de `package:image`, se aprietan horizontalmente, se
/// ensucian (huecos de tinta, motas, desenfoque) y pasan por el mismo
/// segmentador que usa la aplicación, para que el parche sea idéntico en
/// forma al de un dígito real.
class GeneradorSello {
  static Float32List digito(int d, math.Random r) {
    for (var intento = 0; intento < 5; intento++) {
      final p = _intentar(d, r);
      if (p != null) return p;
    }
    return Float32List(_lado * _lado);
  }

  static Float32List? _intentar(int d, math.Random r) {
    const ancho = 120, alto = 120;
    final lienzo = img.Image(width: ancho, height: alto, numChannels: 3);
    img.fill(lienzo, color: img.ColorRgb8(255, 255, 255));
    final fuente = r.nextBool() ? img.arial48 : img.arial24;
    img.drawString(lienzo, '$d', font: fuente, x: 35, y: 30, color: img.ColorRgb8(0, 0, 0));

    // Gris de la imagen original.
    final gris = Float64List(ancho * alto);
    for (var y = 0; y < alto; y++) {
      for (var x = 0; x < ancho; x++) {
        gris[y * ancho + x] = lienzo.getPixel(x, y).r.toDouble();
      }
    }

    // Aprieta horizontalmente (tipografía condensada).
    final factor = 0.5 + r.nextDouble() * 0.3;
    final nuevoAncho = (ancho * factor).round();
    final apretada = Float64List(nuevoAncho * alto);
    for (var y = 0; y < alto; y++) {
      for (var x = 0; x < nuevoAncho; x++) {
        final sx = x / factor;
        final x0 = sx.floor().clamp(0, ancho - 1), x1 = (x0 + 1).clamp(0, ancho - 1);
        final f = sx - x0;
        apretada[y * nuevoAncho + x] = gris[y * ancho + x0] * (1 - f) + gris[y * ancho + x1] * f;
      }
    }

    // Engrosa el trazo (la tinta del sello es más gruesa que la fuente fina).
    var actual = apretada;
    final engrosar = r.nextInt(3);
    for (var k = 0; k < engrosar; k++) {
      actual = _minimo3(actual, nuevoAncho, alto);
    }

    // Tinta despareja: nivel de gris variable, huecos y motas.
    final nivelTinta = 20 + r.nextInt(100);
    final huecos = 0.03 + r.nextDouble() * 0.12;
    final salida = Uint8List(nuevoAncho * alto);
    for (var i = 0; i < salida.length; i++) {
      var v = actual[i];
      if (v < 160) {
        v = nivelTinta.toDouble();
        if (r.nextDouble() < huecos) v = 190 + r.nextInt(50).toDouble();
      } else {
        v = 255;
        if (r.nextDouble() < 0.002) v = 100 + r.nextInt(80).toDouble();
      }
      salida[i] = v.round().clamp(0, 255);
    }
    var finalGris = salida;
    if (r.nextDouble() < 0.5) finalGris = _desenfoque3(salida, nuevoAncho, alto);

    final ds = SegmentadorComponentes.segmentar(
      ImagenGris(pixeles: finalGris, ancho: nuevoAncho, alto: alto),
      alturaMinimaRelativa: 0.5,
      cantidadEsperada: 1,
    );
    if (ds.isEmpty) return null;
    return ds.first.patch;
  }

  static Float64List _minimo3(Float64List p, int w, int h) {
    final o = Float64List(p.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var m = 255.0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            final v = p[yy * w + xx];
            if (v < m) m = v;
          }
        }
        o[y * w + x] = m;
      }
    }
    return o;
  }

  static Uint8List _desenfoque3(Uint8List p, int w, int h) {
    final o = Uint8List(p.length);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var suma = 0, n = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
            suma += p[yy * w + xx];
            n++;
          }
        }
        o[y * w + x] = suma ~/ n;
      }
    }
    return o;
  }
}
