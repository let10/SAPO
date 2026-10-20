# Procesador Documental MDP

Aplicación de escritorio Windows desarrollada en Flutter para el procesamiento y registro de documentos administrativos de la Municipalidad Distrital de Pocollay.

Funciones principales:
- Lectura de PDF con texto nativo u OCR mediante Tesseract.
- Extracción de nombre completo, código, fecha y Artículo Primero.
- Revisión humana de los datos extraídos.
- Renombrado del PDF.
- Registro local en SQLite.
- Redes neuronales locales para apoyo en casos específicos.

Ejecución:
flutter pub get
flutter run -d windows

