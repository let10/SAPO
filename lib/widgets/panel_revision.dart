import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/campos_resolucion.dart';
import '../models/documento.dart';
import '../services/extraccion/extractor_fecha.dart';
import '../services/renombrador_pdf.dart';
import '../utils/codigo_nombre.dart';
import 'vista_previa_pdf.dart';
import 'visor_texto.dart';

/// Panel "REVISIÓN DE DATOS EXTRAÍDOS": a la izquierda los campos editables y a
/// la derecha el visor del PDF (casi toda la ventana). El usuario corrige
/// cualquier error de OCR y confirma; desde el visor también puede eliminar o
/// girar páginas. Al confirmar, el PDF se renombra con el nombre completo.
Future<void> mostrarRevisionDatos(
  BuildContext context,
  Documento documento, {
  required VoidCallback alCambiar,
  bool vistaPrevia = true,
  Future<void> Function(Documento documento, String nombreCompleto)? renombrarArchivo,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PanelRevision(
      documento: documento,
      alCambiar: alCambiar,
      vistaPrevia: vistaPrevia,
      renombrarArchivo: renombrarArchivo ?? (d, n) => RenombradorPdf().renombrar(d, n),
    ),
  );
}

class _PanelRevision extends StatefulWidget {
  final Documento documento;
  final VoidCallback alCambiar;
  final bool vistaPrevia;
  final Future<void> Function(Documento documento, String nombreCompleto) renombrarArchivo;

  const _PanelRevision({
    required this.documento,
    required this.alCambiar,
    required this.vistaPrevia,
    required this.renombrarArchivo,
  });

  @override
  State<_PanelRevision> createState() => _PanelRevisionState();
}

class _PanelRevisionState extends State<_PanelRevision> {
  late final DatosResolucion _datos = widget.documento.datos!;
  late final TextEditingController _nombre;
  late final TextEditingController _numero;
  late final TextEditingController _codigo;
  late final TextEditingController _dia;
  late final TextEditingController _mes;
  late final TextEditingController _anio;
  late final TextEditingController _articulo;
  final FocusNode _focoNumero = FocusNode();
  final FocusNode _focoDia = FocusNode();
  final FocusNode _focoMes = FocusNode();
  final FocusNode _focoAnio = FocusNode();
  final GlobalKey _claveVistaPrevia = GlobalKey();

  bool _renombrando = false;
  String? _errorRenombrado;

  @override
  void initState() {
    super.initState();
    _nombre = TextEditingController(text: _datos.nombreCompleto.valor);
    _codigo = TextEditingController(text: _datos.codigo.valor);
    _numero = TextEditingController(text: CodigoNombre.numeroDeCodigo(_datos.codigo.valor));
    final partes = _datos.fecha.valor.split('/');
    final hayFecha = partes.length == 3;
    _dia = TextEditingController(text: hayFecha ? partes[0] : '');
    _mes = TextEditingController(text: hayFecha ? partes[1] : '');
    _anio = TextEditingController(text: hayFecha ? partes[2] : '');
    _articulo = TextEditingController(text: _datos.articuloPrimeroPrincipal.valor);

    _focoNumero.addListener(() {
      if (!_focoNumero.hasFocus) _completarNumero();
    });
    _focoDia.addListener(() {
      if (!_focoDia.hasFocus) _completarParte(_dia);
    });
    _focoMes.addListener(() {
      if (!_focoMes.hasFocus) _completarParte(_mes);
    });
  }

  @override
  void dispose() {
    for (final c in [_nombre, _numero, _codigo, _dia, _mes, _anio, _articulo]) {
      c.dispose();
    }
    for (final f in [_focoNumero, _focoDia, _focoMes, _focoAnio]) {
      f.dispose();
    }
    super.dispose();
  }

  void _marcarEditado(CampoExtraido campo) {
    campo.editadoManualmente = true;
    widget.documento.datosConfirmados = false;
  }

  // ── Nombre completo y código comparten número y siglas ───────────────────

  void _nombreEditado(String valor) {
    setState(() {
      _datos.nombreCompleto.valor = valor;
      _marcarEditado(_datos.nombreCompleto);
      final codigo = CodigoNombre.codigoDeNombre(valor);
      if (codigo != null) {
        _codigo.text = codigo;
        _datos.codigo.valor = codigo;
        _marcarEditado(_datos.codigo);
        _numero.text = CodigoNombre.numeroDeCodigo(codigo);
      }
    });
    widget.alCambiar();
  }

  void _codigoEditado(String valor) => _aplicarCodigo(valor);

  void _numeroEditado(String texto) {
    final digitos = texto.replaceAll(RegExp(r'\D'), '');
    _aplicarCodigo(CodigoNombre.codigoConNumero(_codigo.text, digitos), desdeNumero: true);
  }

  /// Fija el código y reescribe el nombre completo con el mismo código.
  void _aplicarCodigo(String codigo, {bool desdeNumero = false}) {
    setState(() {
      if (_codigo.text != codigo) _codigo.text = codigo;
      _datos.codigo.valor = codigo;
      _marcarEditado(_datos.codigo);

      final nombre = CodigoNombre.nombreConCodigo(_nombre.text, codigo);
      if (nombre != _nombre.text) _nombre.text = nombre;
      _datos.nombreCompleto.valor = nombre;
      _marcarEditado(_datos.nombreCompleto);

      if (!desdeNumero) _numero.text = CodigoNombre.numeroDeCodigo(codigo);
    });
    widget.alCambiar();
  }

  /// Al salir del campo Número: 87 → 087.
  void _completarNumero() {
    final digitos = _numero.text.replaceAll(RegExp(r'\D'), '');
    if (digitos.isEmpty) return;
    final normalizado = CodigoNombre.numeroNormalizado(digitos);
    if (_numero.text != normalizado) setState(() => _numero.text = normalizado);
  }

  // ── Fecha por partes ─────────────────────────────────────────────────────

  String get _fechaTexto {
    if (_dia.text.isEmpty && _mes.text.isEmpty && _anio.text.isEmpty) return '';
    return '${_dia.text}/${_mes.text}/${_anio.text}';
  }

  void _fechaEditada() {
    setState(() {
      _datos.fecha.valor = _fechaTexto;
      _marcarEditado(_datos.fecha);
    });
    widget.alCambiar();
  }

  void _completarParte(TextEditingController c) {
    if (c.text.length == 1) {
      c.text = '0${c.text}';
      _fechaEditada();
    }
  }

  String? _errorFecha() {
    final texto = _fechaTexto;
    if (texto.isEmpty) return null;
    final c = ExtractorFecha.validarTextoDDMMAAAA(texto);
    return c.valida ? null : 'Fecha no válida (${c.motivo.isEmpty ? 'complete día, mes y año' : c.motivo})';
  }

  // ── Resto ────────────────────────────────────────────────────────────────

  void _articuloEditado(String valor) {
    setState(() {
      _datos.articuloPrimeroPrincipal.valor = valor;
      _marcarEditado(_datos.articuloPrimeroPrincipal);
    });
    widget.alCambiar();
  }

  void _documentoModificado() {
    if (mounted) setState(() {});
    widget.alCambiar();
  }

  bool get _puedeConfirmar =>
      _nombre.text.trim().isNotEmpty &&
      _codigo.text.trim().isNotEmpty &&
      !_codigo.text.contains('___') &&
      _articulo.text.trim().isNotEmpty &&
      _fechaTexto.isNotEmpty &&
      _errorFecha() == null;

  /// Renombra el PDF con el nombre completo y, si todo salió bien, confirma.
  Future<void> _confirmar() async {
    final documento = widget.documento;
    setState(() {
      _renombrando = true;
      _errorRenombrado = null;
    });
    try {
      await widget.renombrarArchivo(documento, _nombre.text.trim());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _renombrando = false;
        _errorRenombrado = 'No se pudo renombrar el archivo: ${e is StateError ? e.message : e}';
      });
      return;
    }
    documento.datosConfirmados = true;
    widget.alCambiar();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('REVISIÓN DE DATOS EXTRAÍDOS', style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                widget.documento.nombre,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
              const Divider(height: 16),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, restricciones) {
                    final izquierda = _panelIzquierdo(theme);
                    if (!widget.vistaPrevia) return izquierda;
                    final derecha = VistaPreviaPdf(
                      key: _claveVistaPrevia,
                      documento: widget.documento,
                      alModificarDocumento: _documentoModificado,
                    );
                    if (restricciones.maxWidth >= 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 6, child: izquierda),
                          const SizedBox(width: 14),
                          const VerticalDivider(width: 1),
                          const SizedBox(width: 14),
                          Expanded(flex: 5, child: derecha),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: izquierda),
                        const SizedBox(height: 12),
                        SizedBox(height: 420, child: derecha),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelIzquierdo(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Los datos se obtuvieron automáticamente. Corrija cualquier error antes de confirmar; '
          'el texto OCR bruto no se modifica.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: 12),
              child: _campos(theme),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Al confirmar, el archivo se renombrará como: ${RenombradorPdf.nombreDeArchivo(_nombre.text)}',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (_errorRenombrado != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_errorRenombrado!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: widget.documento.textoCompleto.isEmpty
                  ? null
                  : () => mostrarVisorTexto(context, widget.documento),
              icon: const Icon(Icons.description_outlined, size: 18),
              label: const Text('Ver texto OCR'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: _puedeConfirmar ? '' : 'Complete número, fecha y los demás campos con valores válidos',
              child: FilledButton.icon(
                onPressed: _puedeConfirmar && !_renombrando ? _confirmar : null,
                icon: _renombrando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: const Text('Confirmar datos'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _campos(ThemeData theme) {
    final sinNumero = _codigo.text.contains('___') || _numero.text.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EncabezadoCampo(etiqueta: 'Número de resolución:', campo: _datos.codigo, mostrarEstado: false),
        const SizedBox(height: 6),
        SizedBox(
          width: 170,
          child: TextField(
            key: const Key('campo-numero'),
            controller: _numero,
            focusNode: _focoNumero,
            onChanged: _numeroEditado,
            onSubmitted: (_) => _completarNumero(),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Ej.: 087'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 18),
          child: Text(
            sinNumero
                ? 'No se detectó el número: escríbalo aquí (87 se completa como 087); se actualizan el código y el nombre.'
                : 'Se completa a tres cifras (87 → 087) y actualiza el código y el nombre.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: sinNumero ? Colors.deepOrange.shade900 : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _BloqueCampo(
          campoKey: const Key('campo-nombre'),
          etiqueta: 'Nombre completo:',
          campo: _datos.nombreCompleto,
          controlador: _nombre,
          alEditar: _nombreEditado,
        ),
        _BloqueCampo(
          campoKey: const Key('campo-codigo'),
          etiqueta: 'Código:',
          campo: _datos.codigo,
          controlador: _codigo,
          alEditar: _codigoEditado,
        ),
        _bloqueFecha(theme),
        _BloqueCampo(
          campoKey: const Key('campo-articulo'),
          etiqueta: 'Artículo Primero:',
          campo: _datos.articuloPrimeroPrincipal,
          controlador: _articulo,
          lineasMin: 5,
          lineasMax: 12,
          alEditar: _articuloEditado,
        ),
      ],
    );
  }

  Widget _bloqueFecha(ThemeData theme) {
    final error = _errorFecha();
    Widget parte(Key key, TextEditingController c, FocusNode foco, String pista, int largo, double ancho,
        {FocusNode? siguiente}) {
      return SizedBox(
        width: ancho,
        child: TextField(
          key: key,
          controller: c,
          focusNode: foco,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(largo)],
          onChanged: (v) {
            _fechaEditada();
            if (siguiente != null && v.length == largo) siguiente.requestFocus();
          },
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: pista,
            errorText: error != null ? '' : null,
            errorStyle: const TextStyle(height: 0, fontSize: 0),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EncabezadoCampo(etiqueta: 'Fecha:', campo: _datos.fecha),
          const SizedBox(height: 6),
          Row(
            children: [
              parte(const Key('campo-dia'), _dia, _focoDia, 'DD', 2, 72, siguiente: _focoMes),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('/')),
              parte(const Key('campo-mes'), _mes, _focoMes, 'MM', 2, 72, siguiente: _focoAnio),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('/')),
              parte(const Key('campo-anio'), _anio, _focoAnio, 'AAAA', 4, 100),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(error, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          _NotaCampo(campo: _datos.fecha),
        ],
      ),
    );
  }
}

/// Etiqueta del campo con su estado (DETECTADO / REQUIERE REVISIÓN) y marca de edición.
class _EncabezadoCampo extends StatelessWidget {
  final String etiqueta;
  final CampoExtraido campo;
  final bool mostrarEstado;

  const _EncabezadoCampo({required this.etiqueta, required this.campo, this.mostrarEstado = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final revisar = campo.requiereRevision;
    final colorFondo = revisar ? Colors.orange.shade100 : Colors.green.shade100;
    final colorTexto = revisar ? Colors.deepOrange.shade900 : Colors.green.shade900;
    return Row(
      children: [
        Text(etiqueta, style: theme.textTheme.titleSmall),
        if (mostrarEstado) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: colorFondo, borderRadius: BorderRadius.circular(4)),
            child: Text(
              campo.estadoLabel,
              style: theme.textTheme.labelSmall?.copyWith(color: colorTexto, fontWeight: FontWeight.w600),
            ),
          ),
          if (campo.editadoManualmente) ...[
            const SizedBox(width: 8),
            Text('editado manualmente',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ],
      ],
    );
  }
}

class _NotaCampo extends StatelessWidget {
  final CampoExtraido campo;

  const _NotaCampo({required this.campo});

  @override
  Widget build(BuildContext context) {
    if (campo.nota.isEmpty) return const SizedBox.shrink();
    final revisar = campo.requiereRevision;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        campo.nota,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: revisar ? Colors.deepOrange.shade900 : Colors.green.shade900,
            ),
      ),
    );
  }
}

class _BloqueCampo extends StatelessWidget {
  final Key campoKey;
  final String etiqueta;
  final CampoExtraido campo;
  final TextEditingController controlador;
  final ValueChanged<String> alEditar;
  final int lineasMin;
  final int lineasMax;

  const _BloqueCampo({
    required this.campoKey,
    required this.etiqueta,
    required this.campo,
    required this.controlador,
    required this.alEditar,
    this.lineasMin = 1,
    this.lineasMax = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EncabezadoCampo(etiqueta: etiqueta, campo: campo),
          const SizedBox(height: 6),
          TextField(
            key: campoKey,
            controller: controlador,
            onChanged: alEditar,
            minLines: lineasMin,
            maxLines: lineasMax,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
          ),
          _NotaCampo(campo: campo),
        ],
      ),
    );
  }
}
