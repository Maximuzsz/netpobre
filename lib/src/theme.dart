import 'package:flutter/material.dart';

abstract final class CasaFlixColors {
  static const night = Color(0xFF08111D);
  static const deepSea = Color(0xFF102538);
  static const ink = Color(0xFF17364A);
  static const ivory = Color(0xFFF4F1E8);
  static const sky = Color(0xFF58C7F3);
  static const amber = Color(0xFFF4B860);
  static const muted = Color(0xFFA9B7C3);
}

abstract final class CasaFlixTheme {
  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: CasaFlixColors.sky,
          brightness: Brightness.dark,
          surface: CasaFlixColors.deepSea,
        ).copyWith(
          primary: CasaFlixColors.sky,
          secondary: CasaFlixColors.amber,
          onSurface: CasaFlixColors.ivory,
          surface: CasaFlixColors.deepSea,
        );

    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: CasaFlixColors.night,
      fontFamily: 'sans-serif',
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: CasaFlixColors.ivory,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CasaFlixColors.deepSea,
        labelStyle: const TextStyle(color: CasaFlixColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: CasaFlixColors.sky, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: CasaFlixColors.amber,
          foregroundColor: CasaFlixColors.night,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: CasaFlixColors.sky,
      ),
    );
  }
}

class CasaFlixMark extends StatelessWidget {
  const CasaFlixMark({super.key, this.size = 34, this.showName = true});

  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(size * .22),
          child: Image.asset(
            'assets/branding/netpobre-icon-1024.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
        if (showName) ...[
          const SizedBox(width: 12),
          Text(
            'NetPobre',
            style: TextStyle(
              color: CasaFlixColors.ivory,
              fontSize: size * .72,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
          ),
        ],
      ],
    );
  }
}
