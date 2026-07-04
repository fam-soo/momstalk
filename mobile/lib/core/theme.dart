import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

final appTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4A90D9),
    brightness: Brightness.light,
  ),
  // Noto Sans KR: 한글 완전 지원, Flutter font registry에 직접 등록
  textTheme: GoogleFonts.notoSansKrTextTheme(),
  appBarTheme: AppBarTheme(
    centerTitle: true,
    elevation: 0,
    scrolledUnderElevation: 1,
    titleTextStyle: GoogleFonts.notoSansKr(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    ),
  ),
  cardTheme: CardThemeData(
    elevation: 0,
    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: Colors.grey.shade200),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    isDense: true,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(46),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
  ),
  listTileTheme: const ListTileThemeData(
    dense: true,
    visualDensity: VisualDensity(horizontal: 0, vertical: -1),
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
  ),
  chipTheme: ChipThemeData(
    labelStyle: const TextStyle(fontSize: 12),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
    visualDensity: VisualDensity.compact,
  ),
);
