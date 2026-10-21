import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../models/documento.dart';

/// Datos confirmados listos para copiar y pegar en el formulario de la web de la
/// municipalidad (Título o Nombre, Número, Fecha y Breve descripción).
class PanelCopiarDatos extends StatelessWidget {
  final Documento documento;

  const PanelCopiarDatos({super.key, required this.documento});

  @override
  Widget build(BuildContext context) {
    final datos = documento.datos;
    if (datos == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final articulo = datos.articuloPrimeroPrincipal.valor;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Datos para copiar a la web de la municipalidad', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          FilaCopiar(
            etiqueta: 'Título o Nombre',
            mostrar: datos.nombreCompleto.valor,
            copiar: datos.nombreCompleto.valor,
          ),
          FilaCopiar(
            etiqueta: 'Número',
            mostrar: datos.codigo.valor,
            copiar: datos.codigo.valor,
          ),
          FilaCopiar(
            etiqueta: 'Fecha',
            mostrar: datos.fecha.valor,
            copiar: datos.fecha.valor,
          ),
          FilaCopiar(
            etiqueta: 'Breve descripción (Artículo Primero)',
            mostrar: _resumir(articulo),
            copiar: articulo,
          ),
        ],
      ),
    );
  }

  static String _resumir(String texto, {int maximo = 90}) {
    final limpio = texto.replaceAll(RegExp(r'\s+'), ' ').trim();
    return limpio.length <= maximo ? limpio : '${limpio.substring(0, maximo).trimRight()}…';
  }
}

/// Una fila: etiqueta, valor (resumido si es largo) y botón Copiar.
class FilaCopiar extends StatefulWidget {
  final String etiqueta;
  final String mostrar;
  final String copiar;

  const FilaCopiar({
    super.key,
    required this.etiqueta,
    required this.mostrar,
    required this.copiar,
  });

  @override
  State<FilaCopiar> createState() => _FilaCopiarState();
}

class _FilaCopiarState extends State<FilaCopiar> {
  bool _copiado = false;
  Timer? _temporizador;

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  Future<void> _copiar() async {
    await Clipboard.setData(ClipboardData(text: widget.copiar));
    if (!mounted) return;
    setState(() => _copiado = true);
    _temporizador?.cancel();
    _temporizador = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copiado = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 230,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(widget.etiqueta, style: theme.textTheme.labelLarge),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(widget.mostrar.isEmpty ? '—' : widget.mostrar, style: theme.textTheme.bodyMedium),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 112,
            child: _copiado
                ? FilledButton.icon(
                    onPressed: _copiar,
                    style: FilledButton.styleFrom(backgroundColor: EstadoColores.exitoTexto),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Copiado'),
                  )
                : OutlinedButton.icon(
                    onPressed: widget.copiar.isEmpty ? null : _copiar,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar'),
                  ),
          ),
        ],
      ),
    );
  }
}
