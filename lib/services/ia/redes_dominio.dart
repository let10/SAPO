import 'dart:io';
import 'dart:typed_data';

import 'red_digitos.dart';

/// Las dos redes neuronales propias de la aplicación, con la misma
/// arquitectura ([RedDigitos]) pero entrenadas para dominios distintos:
///
/// * [numero]: dígitos escritos a mano con bolígrafo azul (el número de la
///   resolución). Entrenada con MNIST y un aumento de datos que imita la
///   escritura inclinada y de trazo fino.
/// * [sello]: dígitos del sello de goma de la fecha. Entrenada con los sellos
///   de los documentos verificados y dígitos sintéticos tipo sello.
class RedesDominio {
  final RedDigitos numero;
  final RedDigitos sello;

  const RedesDominio({required this.numero, required this.sello});

  /// Carga los dos modelos desde una carpeta con `red_numero.bin` y
  /// `red_sello.bin` (para las herramientas de consola; la aplicación los lee
  /// de sus assets con `CargadorRedes`). Devuelve `null` si falta alguno.
  static RedesDominio? desdeCarpeta(String carpeta) {
    try {
      RedDigitos leer(String nombre) =>
          RedDigitos.cargarPesos(ByteData.sublistView(File('$carpeta/$nombre').readAsBytesSync()));
      return RedesDominio(numero: leer('red_numero.bin'), sello: leer('red_sello.bin'));
    } catch (_) {
      return null;
    }
  }
}
