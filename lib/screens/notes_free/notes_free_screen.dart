import 'package:flutter/material.dart';
import '../../config/theme.dart';

class NotesFreeScreen extends StatelessWidget {
  const NotesFreeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('随心记'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.edit_note, size: 64, color: AppTheme.primaryLight),
            const SizedBox(height: 16),
            const Text('自由记录，随心所想',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
            const Text('灵感、随笔、日记', style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
