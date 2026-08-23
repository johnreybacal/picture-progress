import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../features/series/presentation/screens/series_list_page.dart';

class PictureProgressApp extends StatelessWidget {
  const PictureProgressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Picture Progress',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const SeriesListPage(),
    );
  }
}
