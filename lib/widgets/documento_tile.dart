import 'package:flutter/material.dart';

import '../models/documento.dart';
import 'panel_copiar.dart';
import 'panel_revision.dart';
import 'visor_texto.dart';

class DocumentoTile extends StatelessWidget {
  final Documento documento;
  final VoidCallback onQuitar;
  final VoidCallback onProcesar;
  final VoidCallback onCambio;

  /// Mientras las redes neuronales cargan, el botón Procesar queda inactivo.
  final bool puedeProcesar;

  /// Registra el documento (con sus datos ya confirmados) en la base de datos local.
  final VoidCallback onRegistrar;

  const DocumentoTile({
    super.key,
    required this.documento,
    required this.onQuitar,
    required this.onProcesar,
    required this.onCambio,
    this.puedeProcesar = true,
    required this.onRegistrar,
  });

  Color _colorEstado(ThemeData theme) {
    switch (documento.estado) {
      case EstadoDocumento.pendiente:
        return theme.colorScheme.secondaryContainer;
      case EstadoDocumento.procesando:
        return theme.colorScheme.primaryContainer;
      case EstadoDocumento.completado:
        return Colors.green.shade100;
      case EstadoDocumento.error:
        return theme.colorScheme.errorContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final procesando = documento.estado == EstadoDocumento.procesando;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.picture_as_pdf, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        documento.nombre,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        documento.ruta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    documento.estadoLabel,
                    style: theme.textTheme.labelSmall,
                  ),
                  backgroundColor: _colorEstado(theme),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar de la lista',
                  onPressed: procesando ? null : onQuitar,
                ),
              ],
            ),
            if (documento.estado == EstadoDocumento.procesando) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text(
                '${documento.etapa.isEmpty ? 'Procesando…' : documento.etapa}'
                '  (${documento.paginasNativas + documento.paginasOCR}'
                '${documento.totalPaginas > 0 ? ' de ${documento.totalPaginas}' : ''} páginas leídas: '
                '${documento.paginasNativas} nativas, ${documento.paginasOCR} OCR)',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (documento.estado == EstadoDocumento.completado) ...[
              const SizedBox(height: 4),
              Text(
                '${documento.totalPaginas} página${documento.totalPaginas != 1 ? 's' : ''} — '
                '${documento.paginasNativas} con texto nativo, ${documento.paginasOCR} con OCR',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (documento.datos != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    documento.datosConfirmados
                        ? 'Datos confirmados por el usuario.'
                        : documento.datos!.camposPorRevisar == 0
                        ? 'Los cuatro campos fueron detectados; falta su confirmación.'
                        : '${documento.datos!.camposPorRevisar} de 4 campos requieren revisión.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: documento.datosConfirmados
                          ? Colors.green.shade800
                          : documento.datos!.camposPorRevisar == 0
                          ? theme.colorScheme.onSurfaceVariant
                          : Colors.deepOrange.shade800,
                    ),
                  ),
                ),
            ],
            if (documento.estado == EstadoDocumento.error) ...[
              const SizedBox(height: 4),
              Text(
                documento.errorMensaje,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (documento.tieneEdiciones)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'PDF editado (${documento.resumenEdicion}); se modificó el archivo.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (documento.sePuedeProcesar)
                  FilledButton.tonalIcon(
                    onPressed: puedeProcesar ? onProcesar : null,
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('Procesar'),
                  ),
                if (procesando)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    label: const Text('Procesando...'),
                  ),
                if (documento.estado == EstadoDocumento.completado &&
                    documento.datos != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => mostrarRevisionDatos(
                      context,
                      documento,
                      alCambiar: onCambio,
                    ),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Revisar datos'),
                  ),
                ],
                if (documento.datosConfirmados && documento.datos != null) ...[
                  const SizedBox(width: 8),
                  documento.registrado
                      ? FilledButton.icon(
                          onPressed: null,
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: const Text('Registrado'),
                        )
                      : FilledButton.icon(
                          onPressed: onRegistrar,
                          icon: const Icon(Icons.save_alt, size: 18),
                          label: const Text('Registrar documento'),
                        ),
                ],
                if (documento.tieneTexto) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => mostrarVisorTexto(context, documento),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Ver texto OCR'),
                  ),
                ],
              ],
            ),
            if (documento.datosConfirmados && documento.datos != null)
              PanelCopiarDatos(documento: documento),
          ],
        ),
      ),
    );
  }
}
