import 'dart:io';

/// Abre el PDF con el programa predeterminado del sistema.
/// Lanza [StateError] si el archivo no está en la ruta guardada.
Future<void> abrirPdfDelSistema(String ruta) async {
  if (!File(ruta).existsSync()) {
    throw StateError('No se encontró el archivo PDF.');
  }
  if (Platform.isWindows) {
    // `start` es un comando de cmd. El título vacío permite rutas con espacios.
    await Process.start(
      'cmd',
      ['/c', 'start', '', ruta],
      mode: ProcessStartMode.detached,
    );
    return;
  }
  if (Platform.isMacOS) {
    await Process.start('open', [ruta], mode: ProcessStartMode.detached);
    return;
  }
  await Process.start('xdg-open', [ruta], mode: ProcessStartMode.detached);
}
