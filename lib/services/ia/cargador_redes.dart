import 'package:flutter/services.dart' show rootBundle;

import 'red_digitos.dart';
import 'redes_dominio.dart';

/// Carga los pesos entrenados de las dos redes neuronales desde los assets de
/// la aplicación. Si falta alguno o el archivo está dañado, lanza el error
/// para que la pantalla lo muestre; el procesamiento puede seguir después,
/// solo que sin esas lecturas adicionales.
class CargadorRedes {
  static const String rutaNumero = 'assets/ia/red_numero.bin';
  static const String rutaSello = 'assets/ia/red_sello.bin';

  static Future<RedesDominio> cargar() async {
    final numero = RedDigitos.cargarPesos(await rootBundle.load(rutaNumero));
    final sello = RedDigitos.cargarPesos(await rootBundle.load(rutaSello));
    return RedesDominio(numero: numero, sello: sello);
  }
}
