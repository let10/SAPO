import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:procesador_documental_mdp/services/ocr_service.dart';

void main() {
  test('prioriza la copia de Tesseract junto al ejecutable', () {
    final esperado = p.join('C:', 'app', 'tesseract', 'tesseract.exe');
    final idioma = p.join('C:', 'app', 'tesseract', 'tessdata', 'spa.traineddata');
    final ruta = OcrService.localizarTesseract(
      ejecutable: p.join('C:', 'app', 'procesador_documental_mdp.exe'),
      directorioTrabajo: p.join('C:', 'otro'),
      existe: (r) => r == esperado || r == idioma,
    );
    expect(ruta, esperado);
  });

  test('si falta spa.traineddata, el error lo dice', () {
    expect(
      () => OcrService.localizarTesseract(
        ejecutable: p.join('C:', 'app', 'procesador_documental_mdp.exe'),
        directorioTrabajo: p.join('C:', 'otro'),
        existe: (r) => r.endsWith('tesseract.exe'),
      ),
      throwsA(predicate((Object e) => '$e'.contains('idioma español'))),
    );
  });

  test('desde el proyecto, sin copia junto al ejecutable, usa third_party', () {
    final esperado = p.join('C:', 'proyecto', 'third_party', 'tesseract', 'tesseract.exe');
    final ruta = OcrService.localizarTesseract(
      ejecutable: p.join('C:', 'dart-sdk', 'bin', 'dart.exe'),
      directorioTrabajo: p.join('C:', 'proyecto'),
      existe: (r) => r.contains('${p.separator}third_party${p.separator}'),
    );
    expect(ruta, esperado);
  });

  test('el prefijo de datos apunta a la carpeta tessdata', () {
    final ruta = p.join('C:', 'app', 'tesseract', 'tesseract.exe');
    expect(
      OcrService.prefijoDatosTesseract(ruta),
      '${p.join('C:', 'app', 'tesseract', 'tessdata')}${p.separator}',
    );
  });

  test('si no está, el error indica la carpeta junto al ejecutable', () {
    expect(
      () => OcrService.localizarTesseract(
        ejecutable: p.join('C:', 'app', 'app.exe'),
        directorioTrabajo: p.join('C:', 'vacio'),
        existe: (_) => false,
      ),
      throwsA(
        predicate(
          (Object e) =>
              '$e'.contains('junto a la aplicación') &&
              !'$e'.contains('Program Files'),
        ),
      ),
    );
  });
}
