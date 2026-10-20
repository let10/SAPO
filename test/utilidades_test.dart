import 'package:flutter_test/flutter_test.dart';
import 'package:procesador_documental_mdp/models/documento.dart';
import 'package:procesador_documental_mdp/utils/codigo_nombre.dart';
import 'package:procesador_documental_mdp/utils/orden_documentos.dart';

Documento _doc(String nombre, {EstadoDocumento estado = EstadoDocumento.pendiente, bool confirmado = false}) =>
    Documento(nombre: nombre, ruta: 'C:\\$nombre', estado: estado, datosConfirmados: confirmado);

void main() {
  group('CodigoNombre', () {
    test('extrae el código del nombre y recompone el nombre conservando el tipo', () {
      const nombre = 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T';
      expect(CodigoNombre.codigoDeNombre(nombre), '074-2026-A-MDP-T');
      expect(CodigoNombre.nombreConCodigo(nombre, '075-2026-A-MDP-T'), 'RESOLUCIÓN DE ALCALDÍA N° 075-2026-A-MDP-T');
      expect(CodigoNombre.codigoDeNombre('sin simbolo'), isNull);
      expect(CodigoNombre.nombreConCodigo('sin simbolo', '075'), 'sin simbolo');
      expect(CodigoNombre.nombreConCodigo('', '075'), '');
    });

    test('número del código y número normalizado', () {
      expect(CodigoNombre.numeroDeCodigo('074-2026-A-MDP-T'), '074');
      expect(CodigoNombre.numeroDeCodigo('___-2026-A-MDP-T'), '');
      expect(CodigoNombre.numeroNormalizado('87'), '087');
      expect(CodigoNombre.numeroNormalizado('7'), '007');
      expect(CodigoNombre.numeroNormalizado('117'), '117');
      expect(CodigoNombre.numeroNormalizado('0121'), '121');
      expect(CodigoNombre.numeroNormalizado(''), '___');
    });

    test('reemplaza el número del código', () {
      expect(CodigoNombre.codigoConNumero('___-2026-A-MDP-T', '87'), '087-2026-A-MDP-T');
      expect(CodigoNombre.codigoConNumero('074-2026-A-MDP-T', '9'), '009-2026-A-MDP-T');
      expect(CodigoNombre.codigoConNumero('074-2026-A-MDP-T', ''), '___-2026-A-MDP-T');
    });
  });

  group('ordenarDocumentos', () {
    test('confirmados primero (alfabético), luego procesados, pendientes al final', () {
      final lista = [
        _doc('zeta.pdf'),
        _doc('RESOLUCIÓN DE ALCALDÍA N° 092-2026-A-MDP-T.pdf', confirmado: true, estado: EstadoDocumento.completado),
        _doc('beta.pdf', estado: EstadoDocumento.completado),
        _doc('RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T.pdf', confirmado: true, estado: EstadoDocumento.completado),
        _doc('alfa.pdf'),
        _doc('Álamo.pdf', estado: EstadoDocumento.error),
      ];
      expect(ordenarDocumentos(lista).map((d) => d.nombre).toList(), [
        'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T.pdf',
        'RESOLUCIÓN DE ALCALDÍA N° 092-2026-A-MDP-T.pdf',
        'Álamo.pdf',
        'beta.pdf',
        'alfa.pdf',
        'zeta.pdf',
      ]);
    });

    test('no modifica la lista original y es estable con nombres iguales', () {
      final a = _doc('x.pdf');
      final b = _doc('x.pdf');
      final original = [b, a];
      final ordenada = ordenarDocumentos(original);
      expect(ordenada.first, same(b));
      expect(original.first, same(b));
    });
  });
}
