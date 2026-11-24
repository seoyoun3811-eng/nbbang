import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart'; // flutterfire configure 가 자동으로 만들어 주는 파일
import 'screens/people_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const NbbangApp());
}

class NbbangApp extends StatelessWidget {
  const NbbangApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'N빵',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F7CF4),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      ),
      home: const PeopleScreen(),
    );
  }
}
