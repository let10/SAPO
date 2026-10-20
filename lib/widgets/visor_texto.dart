import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/documento.dart';

Future<void> mostrarVisorTexto(BuildContext context, Documento documento) {
  return showDialog(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                documento.nombre,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 16,
                children: [
                  Text('${documento.totalPaginas} página${documento.totalPaginas != 1 ? 's' : ''}'),
                  Text('${documento.paginasNativas} con texto nativo'),
                  Text('${documento.paginasOCR} con OCR'),
                ],
              ),
              const Divider(height: 20),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    child: SelectableText(
                      documento.textoCompleto.isEmpty
                          ? '(Sin texto extraído)'
                          : documento.textoCompleto,
                      style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: documento.textoCompleto));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Texto copiado al portapapeles')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar todo'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
