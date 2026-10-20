import 'dart:math' as math;
import 'dart:typed_data';

import '../renderizador_pagina.dart';
import 'red_digitos.dart';
import 'segmentador_digitos.dart';

/// Un dígito aislado de una franja de imagen, ya normalizado para la red.
class DigitoSegmentado {
  /// 28×28 en [0,1] (fondo ≈ 0, trazo ≈ 1), con el dígito escalado a 20 px de
  /// lado mayor y centrado por su centro de masa, como en MNIST.
  final Float32List patch;

  /// Caja del dígito en la imagen de origen (inclusive).
  final int x0, y0, x1, y1;

  const DigitoSegmentado(this.patch, this.x0, this.y0, this.x1, this.y1);

  int get ancho => x1 - x0 + 1;
  int get alto => y1 - y0 + 1;
}

/// Separa una franja de tinta (tinta oscura sobre fondo blanco) en dígitos por
/// componentes conexas, en lugar de por columnas: un "1" escrito inclinado no
/// se funde con el dígito vecino aunque sus columnas se solapen, y un dígito
/// de trazos separados (el "5" con su barra, el "4" abierto) se vuelve a unir.
class SegmentadorComponentes {
  static const int _lado = RedDigitos.entradaLado;
  static const int _ladoDigito = 20;

  /// [alturaMinimaRelativa]: las manchas más bajas que esta fracción de la
  /// más alta (puntos, motas) no son dígitos. [solapeFusion]: dos manchas se
  /// unen en un solo dígito si se solapan en horizontal al menos esta fracción
  /// de la más angosta.
  ///
  /// [cantidadEsperada]: si se conoce cuántos dígitos debe haber (los números
  /// de resolución de esta serie llevan siempre tres cifras), las manchas se
  /// ajustan a esa cantidad: se unen las más cercanas si sobran (un "0" abierto
  /// que quedó en dos mitades) o se parte la más ancha si faltan (dos dígitos
  /// pegados).
  static List<DigitoSegmentado> segmentar(
    ImagenGris imagen, {
    double alturaMinimaRelativa = 0.3,
    double solapeFusion = 0.6,
    int? cantidadEsperada,
  }) {
    final w = imagen.ancho, h = imagen.alto;
    final px = imagen.pixeles;
    var minimo = 255;
    for (final v in px) {
      if (v < minimo) minimo = v;
    }
    if (minimo > 200) return const [];

    final umbral = math.min(SegmentadorDigitos.umbralOtsu(px), 200);
    final etiquetas = Int32List(w * h);
    final cajas = <_Mancha>[];
    final pila = Int32List(w * h);

    for (var inicio = 0; inicio < w * h; inicio++) {
      if (px[inicio] > umbral || etiquetas[inicio] != 0) continue;
      final id = cajas.length + 1;
      final m = _Mancha(id);
      var tope = 0;
      pila[tope++] = inicio;
      etiquetas[inicio] = id;
      while (tope > 0) {
        final p = pila[--tope];
        final y = p ~/ w, x = p - y * w;
        m.agregar(x, y);
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w || (dx == 0 && dy == 0)) continue;
            final q = ny * w + nx;
            if (etiquetas[q] == 0 && px[q] <= umbral) {
              etiquetas[q] = id;
              pila[tope++] = q;
            }
          }
        }
      }
      cajas.add(m);
    }
    if (cajas.isEmpty) return const [];

    var mayorAlto = 0;
    for (final m in cajas) {
      if (m.alto > mayorAlto) mayorAlto = m.alto;
    }
    // Descarta solo las motas: las manchas bajas pero anchas son trazos
    // horizontales de un dígito (la barra del "5", la del "7") y se conservan
    // para unirlas después con su dígito.
    final manchas = cajas
        .where((m) =>
            m.area >= 8 && (m.alto >= alturaMinimaRelativa * mayorAlto || m.ancho >= alturaMinimaRelativa * mayorAlto))
        .toList();

    // Une manchas que se solapan en horizontal (trazos separados de un mismo dígito).
    var fusionado = true;
    while (fusionado) {
      fusionado = false;
      manchas.sort((a, b) => a.x0.compareTo(b.x0));
      for (var i = 0; i < manchas.length && !fusionado; i++) {
        for (var j = i + 1; j < manchas.length; j++) {
          final a = manchas[i], b = manchas[j];
          final solape = math.min(a.x1, b.x1) - math.max(a.x0, b.x0) + 1;
          if (solape > 0 && solape >= solapeFusion * math.min(a.ancho, b.ancho)) {
            a.unir(b);
            manchas.removeAt(j);
            fusionado = true;
            break;
          }
        }
      }
    }
    manchas.sort((a, b) => a.x0.compareTo(b.x0));

    if (cantidadEsperada != null) {
      while (manchas.length > cantidadEsperada && manchas.length > 1) {
        // Une la pareja vecina más cercana, pero penaliza las uniones que
        // darían una mancha más ancha que un dígito (dos dígitos pegados).
        var mejor = 0;
        var menorCoste = double.infinity;
        for (var i = 0; i + 1 < manchas.length; i++) {
          final a = manchas[i], b = manchas[i + 1];
          final hueco = (b.x0 - a.x1 - 1).toDouble();
          final ancho = math.max(a.x1, b.x1) - math.min(a.x0, b.x0) + 1;
          final alto = math.max(a.y1, b.y1) - math.min(a.y0, b.y0) + 1;
          final coste = hueco + (ancho / alto > 0.95 ? 1000.0 : 0.0);
          if (coste < menorCoste) {
            menorCoste = coste;
            mejor = i;
          }
        }
        manchas[mejor].unir(manchas[mejor + 1]);
        manchas.removeAt(mejor + 1);
      }
      while (manchas.length >= 2 && manchas.length < cantidadEsperada) {
        // Parte la más ancha (relativa a su altura) si parece contener dos dígitos.
        var candidata = -1;
        var mayorProporcion = 0.0;
        for (var i = 0; i < manchas.length; i++) {
          final proporcion = manchas[i].ancho / manchas[i].alto;
          if (proporcion > mayorProporcion) {
            mayorProporcion = proporcion;
            candidata = i;
          }
        }
        if (candidata < 0 || mayorProporcion < 0.8) break;
        final partes = _partir(manchas[candidata], px, etiquetas, w, umbral);
        if (partes == null) break;
        manchas
          ..removeAt(candidata)
          ..insertAll(candidata, partes);
      }
    }

    return [
      for (final m in manchas) DigitoSegmentado(_normalizar(px, etiquetas, w, m), m.x0, m.y0, m.x1, m.y1),
    ];
  }

  /// Corta una mancha en dos por la columna con menos tinta del tramo central.
  static List<_Mancha>? _partir(_Mancha m, Uint8List px, Int32List etiquetas, int w, int umbral) {
    final desde = m.x0 + (m.ancho * 0.3).round();
    final hasta = m.x0 + (m.ancho * 0.7).round();
    if (hasta <= desde) return null;
    var mejorX = desde;
    var menorTinta = 1 << 30;
    for (var x = desde; x <= hasta; x++) {
      var tinta = 0;
      for (var y = m.y0; y <= m.y1; y++) {
        final p = y * w + x;
        if (m.ids.contains(etiquetas[p]) && px[p] <= umbral) tinta++;
      }
      if (tinta < menorTinta) {
        menorTinta = tinta;
        mejorX = x;
      }
    }
    final izquierda = _Mancha.recortada(m, m.x0, mejorX - 1, px, etiquetas, w, umbral);
    final derecha = _Mancha.recortada(m, mejorX, m.x1, px, etiquetas, w, umbral);
    if (izquierda == null || derecha == null) return null;
    return [izquierda, derecha];
  }

  /// Escala el dígito (solo los píxeles de sus manchas) a 20 px de lado mayor,
  /// conservando la proporción, y lo centra por su centro de masa en 28×28.
  static Float32List _normalizar(Uint8List px, Int32List etiquetas, int w, _Mancha m) {
    final cw = m.ancho, ch = m.alto;
    final escala = _ladoDigito / math.max(cw, ch);
    final tw = math.max(1, (cw * escala).round());
    final th = math.max(1, (ch * escala).round());

    double tinta(int x, int y) {
      if (x < m.x0 || x > m.x1 || y < m.y0 || y > m.y1) return 0;
      final p = y * w + x;
      return m.ids.contains(etiquetas[p]) ? (255 - px[p]) / 255.0 : 0;
    }

    final reducida = Float32List(tw * th);
    var suma = 0.0, sx = 0.0, sy = 0.0, maximo = 0.0;
    for (var ty = 0; ty < th; ty++) {
      final y0 = m.y0 + (ty / escala).floor();
      final y1 = math.max(y0, m.y0 + ((ty + 1) / escala).ceil() - 1);
      for (var tx = 0; tx < tw; tx++) {
        final x0 = m.x0 + (tx / escala).floor();
        final x1 = math.max(x0, m.x0 + ((tx + 1) / escala).ceil() - 1);
        var acumulado = 0.0;
        var cuenta = 0;
        for (var y = y0; y <= y1; y++) {
          for (var x = x0; x <= x1; x++) {
            acumulado += tinta(x, y);
            cuenta++;
          }
        }
        final v = cuenta == 0 ? 0.0 : acumulado / cuenta;
        reducida[ty * tw + tx] = v;
        suma += v;
        sx += v * tx;
        sy += v * ty;
        if (v > maximo) maximo = v;
      }
    }

    final salida = Float32List(_lado * _lado);
    if (suma <= 0 || maximo <= 0) return salida;
    final cx = sx / suma, cy = sy / suma;
    final ox = (13.5 - cx).round().clamp(0, _lado - tw);
    final oy = (13.5 - cy).round().clamp(0, _lado - th);
    for (var ty = 0; ty < th; ty++) {
      for (var tx = 0; tx < tw; tx++) {
        salida[(ty + oy) * _lado + tx + ox] = (reducida[ty * tw + tx] / maximo).clamp(0.0, 1.0);
      }
    }
    return salida;
  }
}

class _Mancha {
  final Set<int> ids;
  int x0 = 1 << 30, y0 = 1 << 30, x1 = -1, y1 = -1, area = 0;

  _Mancha(int id) : ids = {id};

  _Mancha._(this.ids, this.x0, this.y0, this.x1, this.y1, this.area);

  int get ancho => x1 - x0 + 1;
  int get alto => y1 - y0 + 1;

  void agregar(int x, int y) {
    if (x < x0) x0 = x;
    if (x > x1) x1 = x;
    if (y < y0) y0 = y;
    if (y > y1) y1 = y;
    area++;
  }

  void unir(_Mancha o) {
    ids.addAll(o.ids);
    x0 = math.min(x0, o.x0);
    y0 = math.min(y0, o.y0);
    x1 = math.max(x1, o.x1);
    y1 = math.max(y1, o.y1);
    area += o.area;
  }

  /// La parte de [m] comprendida entre las columnas [cx0] y [cx1], con su
  /// caja vertical recalculada a partir de la tinta que realmente contiene.
  static _Mancha? recortada(_Mancha m, int cx0, int cx1, Uint8List px, Int32List etiquetas, int w, int umbral) {
    var minY = 1 << 30, maxY = -1, area = 0;
    for (var y = m.y0; y <= m.y1; y++) {
      for (var x = cx0; x <= cx1; x++) {
        final p = y * w + x;
        if (m.ids.contains(etiquetas[p]) && px[p] <= umbral) {
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
          area++;
        }
      }
    }
    if (area == 0) return null;
    return _Mancha._(m.ids, cx0, minY, cx1, maxY, area);
  }
}
