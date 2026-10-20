import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/documento.dart';

/// Renombra el PDF (en su misma carpeta) con el nombre completo de la resolución.
class RenombradorPdf {
  static const int _maxRuta = 250;

  /// Nombre de archivo a partir del nombre completo: quita los caracteres que
  /// Windows no admite en nombres de archivo y agrega `.pdf`.
  static String nombreDeArchivo(String nombreCompleto) {
    var n = nombreCompleto.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '-');
    n = n.replaceAll(RegExp(r'\s+'), ' ').trim();
    n = n.replaceAll(RegExp(r'[. ]+$'), '');
    return n.isEmpty ? '' : '$n.pdf';
  }

  /// Renombra el archivo del documento y actualiza su ruta y nombre. No
  /// sobrescribe nunca un archivo existente. Devuelve `false` si ya tenía ese nombre.
  Future<bool> renombrar(Documento documento, String nombreCompleto) async {
    final archivo = nombreDeArchivo(nombreCompleto);
    if (archivo.isEmpty) {
      throw StateError('El nombre completo está vacío; no se puede renombrar el archivo.');
    }
    final destino = p.join(p.dirname(documento.ruta), archivo);
    if (p.equals(documento.ruta, destino)) return false;
    if (destino.length > _maxRuta) {
      throw StateError('El nombre resultante es demasiado largo para Windows (${destino.length} caracteres).');
    }
    if (await File(destino).exists()) {
      throw StateError('Ya existe un archivo llamado "$archivo" en esa carpeta; no se sobrescribe.');
    }
    await File(documento.ruta).rename(destino);
    documento.ruta = destino;
    documento.nombre = archivo;
    return true;
  }
}
