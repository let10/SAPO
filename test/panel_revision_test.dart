import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:procesador_documental_mdp/models/campos_resolucion.dart';
import 'package:procesador_documental_mdp/models/documento.dart';
import 'package:procesador_documental_mdp/widgets/panel_revision.dart';

Documento _documento({String codigo = '074-2026-A-MDP-T', String fecha = '08/07/2026'}) {
  return Documento(nombre: 'prueba.pdf', ruta: r'C:\prueba.pdf', estado: EstadoDocumento.completado)
    ..textoCompleto = 'texto ocr bruto'
    ..datos = DatosResolucion(
      nombreCompleto: CampoExtraido(
        valor: 'RESOLUCIÓN DE ALCALDÍA N° $codigo',
        estado: EstadoCampo.detectado,
      ),
      codigo: CampoExtraido(valor: codigo, estado: EstadoCampo.detectado),
      fecha: CampoExtraido(valor: fecha, nota: 'Verifique contra el documento.'),
      articuloPrimeroPrincipal: CampoExtraido(
        valor: 'AUTORIZAR, la incorporación de Mayores Ingresos Púbicos:',
        estado: EstadoCampo.detectado,
      ),
    );
}

Future<void> _abrir(
  WidgetTester tester,
  Documento doc,
  VoidCallback alCambiar, {
  Future<void> Function(Documento, String)? renombrar,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => mostrarRevisionDatos(
              context,
              doc,
              alCambiar: alCambiar,
              vistaPrevia: false,
              renombrarArchivo: renombrar ?? (d, n) async {},
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

Finder _campo(String clave) => find.byKey(Key(clave));
String _texto(WidgetTester tester, String clave) => tester.widget<TextField>(_campo(clave)).controller!.text;
FilledButton _confirmar(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirmar datos'));

void main() {
  testWidgets('muestra los campos editables con su estado', (tester) async {
    await _abrir(tester, _documento(), () {});

    expect(find.text('REVISIÓN DE DATOS EXTRAÍDOS'), findsOneWidget);
    for (final etiqueta in ['Nombre completo:', 'Número de resolución:', 'Código:', 'Fecha:', 'Artículo Primero:']) {
      expect(find.text(etiqueta), findsOneWidget, reason: etiqueta);
    }
    expect(find.text('DETECTADO'), findsNWidgets(3));
    expect(find.text('REQUIERE REVISIÓN'), findsOneWidget);
    expect(find.text('Verifique contra el documento.'), findsOneWidget);
    expect(find.text('Ver texto OCR'), findsOneWidget);
    // nombre, número, código, día, mes, año y artículo
    expect(find.byType(TextField), findsNWidgets(7));
    expect(_texto(tester, 'campo-numero'), '074');
    expect(_texto(tester, 'campo-dia'), '08');
    expect(_texto(tester, 'campo-mes'), '07');
    expect(_texto(tester, 'campo-anio'), '2026');
  });

  group('código y nombre se actualizan juntos', () {
    testWidgets('al editar el código cambia el nombre (y el número)', (tester) async {
      final doc = _documento();
      await _abrir(tester, doc, () {});

      await tester.enterText(_campo('campo-codigo'), '075-2026-GM-MDP-T');
      await tester.pump();

      expect(_texto(tester, 'campo-nombre'), 'RESOLUCIÓN DE ALCALDÍA N° 075-2026-GM-MDP-T');
      expect(_texto(tester, 'campo-numero'), '075');
      expect(doc.datos!.codigo.valor, '075-2026-GM-MDP-T');
      expect(doc.datos!.nombreCompleto.valor, 'RESOLUCIÓN DE ALCALDÍA N° 075-2026-GM-MDP-T');
      expect(doc.datos!.codigo.editadoManualmente, isTrue);
      expect(doc.datos!.nombreCompleto.editadoManualmente, isTrue);
    });

    testWidgets('al editar el nombre cambia el código', (tester) async {
      final doc = _documento();
      await _abrir(tester, doc, () {});

      await tester.enterText(_campo('campo-nombre'), 'RESOLUCIÓN DE GERENCIA MUNICIPAL N° 130-2026-GM-MDP-T');
      await tester.pump();

      expect(_texto(tester, 'campo-codigo'), '130-2026-GM-MDP-T');
      expect(_texto(tester, 'campo-numero'), '130');
      expect(doc.datos!.codigo.valor, '130-2026-GM-MDP-T');
    });
  });

  group('número de resolución', () {
    const sinNumero = '___-2026-A-MDP-T';

    testWidgets('sin número detectado no se puede confirmar y se pide escribirlo', (tester) async {
      await _abrir(tester, _documento(codigo: sinNumero), () {});

      expect(find.textContaining('No se detectó el número'), findsOneWidget);
      expect(_confirmar(tester).onPressed, isNull);
    });

    testWidgets('al escribir 87 se completa a 087 en el código y en el nombre', (tester) async {
      final doc = _documento(codigo: sinNumero);
      await _abrir(tester, doc, () {});

      await tester.enterText(_campo('campo-numero'), '87');
      await tester.pump();

      expect(_texto(tester, 'campo-codigo'), '087-2026-A-MDP-T');
      expect(_texto(tester, 'campo-nombre'), 'RESOLUCIÓN DE ALCALDÍA N° 087-2026-A-MDP-T');
      expect(doc.datos!.codigo.valor, '087-2026-A-MDP-T');

      // al terminar de escribir, el propio campo también queda en tres cifras
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(_texto(tester, 'campo-numero'), '087');
      expect(_confirmar(tester).onPressed, isNotNull);
    });

    testWidgets('solo acepta dígitos', (tester) async {
      await _abrir(tester, _documento(codigo: sinNumero), () {});
      await tester.enterText(_campo('campo-numero'), '8a7');
      await tester.pump();
      expect(_texto(tester, 'campo-numero'), '87');
    });
  });

  group('fecha por partes', () {
    testWidgets('cada parte se edita por separado', (tester) async {
      final doc = _documento();
      await _abrir(tester, doc, () {});

      await tester.enterText(_campo('campo-dia'), '15');
      await tester.pump();
      expect(doc.datos!.fecha.valor, '15/07/2026');
      expect(_texto(tester, 'campo-mes'), '07');
      expect(_texto(tester, 'campo-anio'), '2026');

      await tester.enterText(_campo('campo-mes'), '09');
      await tester.pump();
      expect(doc.datos!.fecha.valor, '15/09/2026');

      await tester.enterText(_campo('campo-anio'), '2027');
      await tester.pump();
      expect(doc.datos!.fecha.valor, '15/09/2027');
      expect(doc.datos!.fecha.editadoManualmente, isTrue);
    });

    testWidgets('se valida el calendario y bloquea la confirmación', (tester) async {
      final doc = _documento();
      await _abrir(tester, doc, () {});

      await tester.enterText(_campo('campo-dia'), '31');
      await tester.enterText(_campo('campo-mes'), '02');
      await tester.pump();
      expect(find.textContaining('Fecha no válida'), findsOneWidget);
      expect(_confirmar(tester).onPressed, isNull);

      await tester.enterText(_campo('campo-dia'), '16');
      await tester.pump();
      expect(find.textContaining('Fecha no válida'), findsNothing);
      expect(doc.datos!.fecha.valor, '16/02/2026');
      expect(_confirmar(tester).onPressed, isNotNull);
    });
  });

  testWidgets('editar un campo desconfirma los datos', (tester) async {
    final doc = _documento()..datosConfirmados = true;
    var cambios = 0;
    await _abrir(tester, doc, () => cambios++);

    await tester.enterText(_campo('campo-articulo'), 'APROBAR algo.');
    await tester.pump();

    expect(doc.datos!.articuloPrimeroPrincipal.valor, 'APROBAR algo.');
    expect(doc.datosConfirmados, isFalse);
    expect(cambios, greaterThan(0));
    expect(find.text('editado manualmente'), findsOneWidget);
  });

  testWidgets('al confirmar se renombra el archivo con el nombre completo', (tester) async {
    final doc = _documento();
    String? recibido;
    await _abrir(tester, doc, () {}, renombrar: (d, n) async => recibido = n);

    expect(find.textContaining('RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T.pdf'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar datos'));
    await tester.pumpAndSettle();

    expect(recibido, 'RESOLUCIÓN DE ALCALDÍA N° 074-2026-A-MDP-T');
    expect(doc.datosConfirmados, isTrue);
    expect(find.text('REVISIÓN DE DATOS EXTRAÍDOS'), findsNothing);
  });

  testWidgets('si no se puede renombrar, no confirma y muestra el motivo', (tester) async {
    final doc = _documento();
    await _abrir(tester, doc, () {},
        renombrar: (d, n) async => throw StateError('Ya existe un archivo con ese nombre'));

    await tester.tap(find.widgetWithText(FilledButton, 'Confirmar datos'));
    await tester.pumpAndSettle();

    expect(doc.datosConfirmados, isFalse);
    expect(find.textContaining('Ya existe un archivo con ese nombre'), findsOneWidget);
    expect(find.text('REVISIÓN DE DATOS EXTRAÍDOS'), findsOneWidget);
  });

  testWidgets('no se puede confirmar con un campo vacío', (tester) async {
    await _abrir(tester, _documento(), () {});

    await tester.enterText(_campo('campo-articulo'), '');
    await tester.pump();

    expect(_confirmar(tester).onPressed, isNull);
  });
}
