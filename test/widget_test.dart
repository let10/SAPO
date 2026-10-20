import 'package:flutter_test/flutter_test.dart';
import 'package:procesador_documental_mdp/app/app.dart';

void main() {
  testWidgets('Pantalla principal muestra título y botón', (WidgetTester tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('Procesamiento de Documentos Administrativos'), findsOneWidget);
    expect(find.text('Seleccionar documentos PDF'), findsOneWidget);
  });
}
