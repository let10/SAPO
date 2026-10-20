import 'package:file_picker/file_picker.dart';
import '../models/documento.dart';

class SelectorDocumentos {
  Future<List<Documento>> seleccionar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
      dialogTitle: 'Seleccionar documentos PDF',
    );

    if (result == null || result.files.isEmpty) return [];

    return result.files
        .where((f) => f.path != null)
        .map((f) => Documento(
              nombre: f.name,
              ruta: f.path!,
            ))
        .toList();
  }
}
