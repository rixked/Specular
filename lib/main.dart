import 'package:material_ui/material_ui.dart';

// Placeholder until the visual direction (SPEC.md §9, §13) is decided.
void main() {
  runApp(const SpecularApp());
}

class SpecularApp extends StatelessWidget {
  const SpecularApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Specular',
      theme: ThemeData(brightness: Brightness.dark),
      home: const Scaffold(body: Center(child: Text('Specular'))),
    );
  }
}
