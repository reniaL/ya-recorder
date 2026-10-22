import 'package:flutter/material.dart';

enum AppPalette {
  teal(Color(0xff0b6657)),
  duckYellow(Color(0xffffd43b));

  const AppPalette(this.seedColor);

  final Color seedColor;
}
