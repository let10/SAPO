import 'package:flutter/material.dart';

/// Paleta y tema visual de la aplicación: lila/lavanda, sobrio e institucional.
/// Solo define apariencia (colores, formas, tipografía); no afecta lógica.
const Color _semillaLila = Color(0xFF6E5A96);

/// Colores semánticos de estado (DETECTADO / REQUIERE REVISIÓN y similares),
/// armonizados con la paleta lila en lugar de los verdes/naranjas por defecto.
class EstadoColores {
  const EstadoColores._();

  static const Color exitoTexto = Color(0xFF2E6B4F);
  static const Color exitoFondo = Color(0xFFE2F1E7);

  static const Color advertenciaTexto = Color(0xFF8A5A12);
  static const Color advertenciaFondo = Color(0xFFFBEDD6);

  static const Color neutroFondo = Color(0xFFEDE8F5);
}

ThemeData construirTema() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _semillaLila,
    brightness: Brightness.light,
  );

  final radioBase = BorderRadius.circular(10);
  final formaBase = RoundedRectangleBorder(borderRadius: radioBase);

  final textTheme = const TextTheme().copyWith(
    titleLarge: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.1),
    titleMedium: const TextStyle(fontWeight: FontWeight.w600),
    titleSmall: const TextStyle(fontWeight: FontWeight.w600),
    labelLarge: const TextStyle(fontWeight: FontWeight.w600),
    bodyMedium: const TextStyle(height: 1.35),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colorScheme.surface,
    fontFamily: 'Segoe UI',
    textTheme: textTheme,
    splashFactory: InkSparkle.splashFactory,

    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surfaceContainer,
      foregroundColor: colorScheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: colorScheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: colorScheme.primary),
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 3,
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: formaBase,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: formaBase,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: formaBase,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: radioBase,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radioBase,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radioBase,
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radioBase,
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radioBase,
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerHighest,
      side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),

    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: 0.8),
      thickness: 1,
      space: 1,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? colorScheme.primary : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? colorScheme.primary.withValues(alpha: 0.4) : null,
      ),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: colorScheme.primaryContainer,
        selectedForegroundColor: colorScheme.onPrimaryContainer,
        shape: formaBase,
      ),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
      linearTrackColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
    ),

    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(colorScheme.outline.withValues(alpha: 0.5)),
      radius: const Radius.circular(8),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorScheme.inverseSurface,
      contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: TextStyle(color: colorScheme.onInverseSurface, fontSize: 12),
    ),
  );
}
