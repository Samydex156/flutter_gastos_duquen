import 'package:flutter/material.dart';
import 'expenses/expense_home_page.dart';
import 'reports/dashboard_page.dart';

import 'package:flutter/services.dart';

class MainScreen extends StatefulWidget {
  final int userId;
  final String userEmail;
  const MainScreen({super.key, required this.userId, required this.userEmail});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<ExpenseHomePageState> _expenseKey = GlobalKey();
  DateTime? _lastPressedAt;

  void _goToDate(DateTime date) {
    setState(() {
      _currentIndex = 0;
    });
    // Pequeño delay para asegurar que el cambio de tab se procese
    Future.delayed(const Duration(milliseconds: 50), () {
      _expenseKey.currentState?.setDate(date);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Usamos IndexedStack para mantener el estado de las páginas (que no se recarguen al cambiar)
    final List<Widget> pages = [
      ExpenseHomePage(
        key: _expenseKey,
        userId: widget.userId,
        userEmail: widget.userEmail,
      ),
      DashboardPage(userId: widget.userId, onDateSelected: _goToDate),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
          });
          return;
        }

        final now = DateTime.now();
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          // Primera pulsación o pasó el tiempo
          _lastPressedAt = now;
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Presiona una vez más para salir'),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          // Segunda pulsación rápida -> Salir
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _currentIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.list_alt),
              label: 'Movimientos',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart),
              label: 'Reporte',
            ),
          ],
        ),
      ),
    );
  }
}
