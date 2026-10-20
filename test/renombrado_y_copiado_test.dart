import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:procesador_documental_mdp/models/campos_resolucion.dart';
import 'package:procesador_documental_mdp/models/documento.dart';
import 'package:procesador_documental_mdp/services/renombrador_pdf.dart';
import 'package:procesador_documental_mdp/widgets/panel_copiar.dart';

void main() {
  group('RenombradorPdf', () {
    test('nombre de archivo: conserva N°, tildes y comas; agrega .pdf', () {
      expect(
        RenombradorPdf.nombreDeArchivo(
            'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO ECONÓMICO, LICENCIAS Y CONTROL N° 050-2026-SGDELC-GDESGA-MDP-T'),
        'RESOLUCIÓN DE SUBGERENCIA DE DESARROLLO ECONÓMICO, LICENCIAS Y CONTROL N° 050-2026-SGDELC-GDESGA-MDP-T.pdf',
      );
    });

    test('quita caracteres no permitidos en Windows y espacios sobrantes', () {
      expect(RenombradorPdf.nombreDeArchivo('  A/B:C*D?  '), 'A-B-C-D-.pdf');
      expect(RenombradorPdf.nombreDeArchivo(''), '');
      expect(RenombradorPdf.nombreDeArchivo('   '), '');
    });

    test('renombra en la misma carpeta, actualiza el documento y no sobrescribe', () async {
      final carpeta = await Directory.systemTemp.createTemp('prueba_renombrado_');
      addTearDown(() => carpeta.delete(recursive: true));
      final original = File(p.join(carpeta.path, 'doc01.pdf'))..writeAsBytesSync([1, 2, 3]);
      final doc = Documento(nombre: 'doc01.pdf', ruta: original.path);
      final r = RenombradorPdf();

      expect(await r.renombrar(doc, 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T'), isTrue);
      final nuevaRuta = p.join(carpeta.path, 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T.pdf');
      expect(doc.ruta, nuevaRuta);
      expect(doc.nombre, 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T.pdf');
      expect(File(nuevaRuta).readAsBytesSync(), [1, 2, 3]);
      expect(original.existsSync(), isFalse);

      // mismo nombre: no hace nada
      expect(await r.renombrar(doc, 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T'), isFalse);

      // otro archivo con el nombre de destino: se niega
      final otro = File(p.join(carpeta.path, 'otro.pdf'))..writeAsBytesSync([9]);
      final doc2 = Documento(nombre: 'otro.pdf', ruta: otro.path);
      expect(() => r.renombrar(doc2, 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T'), throwsStateError);
      expect(File(nuevaRuta).readAsBytesSync(), [1, 2, 3]);
      expect(otro.existsSync(), isTrue);

      // nombre vacío
      expect(() => r.renombrar(doc2, '  '), throwsStateError);
    });
  });

  group('PanelCopiarDatos', () {
    Documento documento() => Documento(nombre: 'x.pdf', ruta: r'C:\x.pdf')
      ..datos = DatosResolucion(
        nombreCompleto: CampoExtraido(valor: 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T'),
        codigo: CampoExtraido(valor: '074-2026-A-MDP-T'),
        fecha: CampoExtraido(valor: '08/07/2026'),
        articuloPrimeroPrincipal: CampoExtraido(valor: 'AUTORIZAR, ${'texto muy largo ' * 40}final.'),
      );

    testWidgets('muestra los cuatro datos y resume el artículo sin recortar lo copiado', (tester) async {
      final doc = documento();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: PanelCopiarDatos(documento: doc))),
      ));

      expect(find.text('Datos para copiar a la web de la municipalidad'), findsOneWidget);
      expect(find.text('RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T'), findsOneWidget);
      expect(find.text('074-2026-A-MDP-T'), findsOneWidget);
      expect(find.text('08/07/2026'), findsOneWidget);
      expect(find.text('Copiar'), findsNWidgets(4));
      // el artículo se muestra resumido (termina en …) y no hay contador de caracteres
      expect(find.textContaining('…'), findsOneWidget);
      expect(find.textContaining('caracteres'), findsNothing);
    });

    testWidgets('Copiar deja el valor completo en el portapapeles', (tester) async {
      final doc = documento();
      final portapapeles = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          portapapeles.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: PanelCopiarDatos(documento: doc))),
      ));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Copiar').last);
      await tester.pump();
      expect(portapapeles.single, doc.datos!.articuloPrimeroPrincipal.valor);
      expect(portapapeles.single.length, greaterThan(300));
      expect(find.text('Copiado'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Copiado'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Copiar').at(1));
      await tester.pump();
      expect(portapapeles.last, '074-2026-A-MDP-T');
    });
  });
}
