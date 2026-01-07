import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import 'login_page.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkLocalSession();
  }

  Future<void> _checkLocalSession() async {
    // Mínimo delay para que se vea el logo
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final db = await DatabaseHelper.instance.database;
    if (db == null) {
      _goToLogin();
      return;
    }
    final users = await db.query('usuarios_local');

    if (users.isNotEmpty) {
      final user = users.first;
      _goToMain(user['id'] as int, user['email'] as String);
    } else {
      _goToLogin();
    }
  }

  // AHORA VAMOS A LA MAIN SCREEN, NO DIRECTO A EXPENSES
  void _goToMain(int id, String email) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => MainScreen(userId: id, userEmail: email),
      ),
    );
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.account_balance_wallet, size: 80, color: Colors.white),
            SizedBox(height: 20),
            Text(
              "Gastos DuQuen\nCargando...",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
