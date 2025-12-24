import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../services/database_helper.dart';

class DashboardPage extends StatefulWidget {
  final int userId;
  final Function(DateTime) onDateSelected; // Callback de navegación

  const DashboardPage({
    super.key,
    required this.userId,
    required this.onDateSelected, // Requerido
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLoading = true;
  double _totalMonth = 0;
  double _monthlyBudget = 0;
  List<double> _dailyTotalsWeek = [0, 0, 0, 0, 0, 0, 0];
  // Mapa para guardar totales por día del mes: día -> monto
  double _dailyAvailableAvg = 0;
  int _remainingDays = 0;
  Map<int, double> _monthDailyTotals = {};
  DateTime _currentMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReportData();
    });
  }

  // Agregamos un método público para refrescar si se desea
  Future<void> refresh() => _loadReportData();

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);

    final db = DatabaseHelper.instance;
    final fmt = DateFormat('yyyy-MM-dd');

    final weekExpenses = await db.getExpensesInDateRange(
      widget.userId,
      fmt.format(startOfWeek),
      fmt.format(endOfWeek),
    );

    final monthExpenses = await db.getExpensesInDateRange(
      widget.userId,
      fmt.format(startOfMonth),
      fmt.format(endOfMonth),
    );

    final budget = await db.getMonthlyBudget(
      widget.userId,
      startOfMonth.month,
      startOfMonth.year,
    );

    List<double> daysWeek = [0, 0, 0, 0, 0, 0, 0];

    for (var item in weekExpenses) {
      final amount = (item['amount'] as num).toDouble();
      final date = DateTime.parse(item['date']);

      int dayIndex = date.weekday - 1;
      if (dayIndex >= 0 && dayIndex < 7) {
        daysWeek[dayIndex] += amount;
      }
    }

    // Procesar mes completo
    double sumMonth = 0;
    Map<int, double> monthMap = {};

    // Inicializar todo el mes en 0 (determinamos cuántos días tiene el mes)
    int daysInMonth = DateUtils.getDaysInMonth(
      startOfMonth.year,
      startOfMonth.month,
    );
    for (int i = 1; i <= daysInMonth; i++) {
      monthMap[i] = 0.0;
    }

    for (var item in monthExpenses) {
      final amount = (item['amount'] as num).toDouble();
      final date = DateTime.parse(item['date']);
      sumMonth += amount;
      // Asumimos que date cae en este mes porque la query lo filtra
      monthMap[date.day] = (monthMap[date.day] ?? 0) + amount;
    }

    // Calcular promedio diario disponible
    final todaySimple = DateTime(now.year, now.month, now.day);
    // Último día del mes
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0);
    final endOfMonthSimple = DateTime(
      lastDayOfMonth.year,
      lastDayOfMonth.month,
      lastDayOfMonth.day,
    );

    int remDays = endOfMonthSimple.difference(todaySimple).inDays + 1;
    if (remDays < 0) remDays = 0;

    double balance = budget - sumMonth;
    double avgDaily = 0;
    // Solo mostramos promedio positivo si hay saldo y quedan días
    if (remDays > 0 && balance > 0) {
      avgDaily = balance / remDays;
    }

    if (mounted) {
      setState(() {
        _totalMonth = sumMonth;
        _monthlyBudget = budget;
        _dailyTotalsWeek = daysWeek;
        _monthDailyTotals = monthMap;
        _currentMonth = startOfMonth;
        _remainingDays = remDays;
        _dailyAvailableAvg = avgDaily;
        _isLoading = false;
      });
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    // Ajustar por si array es 0-indexed
    return months[month - 1];
  }

  Future<void> _showSetBudgetDialog() async {
    final ctrl = TextEditingController(
      text: _monthlyBudget > 0 ? _monthlyBudget.toStringAsFixed(2) : '',
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Definir Presupuesto Mensual"),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: "Monto Inicial (Caja)",
            prefixText: "Bs. ",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(ctrl.text.trim());
              if (val != null) {
                await DatabaseHelper.instance.setMonthlyBudget(
                  widget.userId,
                  _currentMonth.month,
                  _currentMonth.year,
                  val,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _loadReportData();
              }
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text("Reporte de Gastos", style: TextStyle(fontSize: 14)),
            Text(
              "Acumulado Total Mes: Bs. ${_totalMonth.toStringAsFixed(2)}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReportData,
          ),
        ],
      ),
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),

                  // --- TARJETA DE PRESUPUESTO / CAJA ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade800, Colors.blue.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Caja Mensual",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            InkWell(
                              onTap: _showSetBudgetDialog,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildBudgetInfo("Presupuesto", _monthlyBudget),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            _buildBudgetInfo("Gastado", _totalMonth),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            _buildBudgetInfo(
                              "Saldo",
                              _monthlyBudget - _totalMonth,
                              isBold: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // --- TARJETA DE PROMEDIO DIARIO ---
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue.shade100),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Días restantes",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "$_remainingDays días",
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade300,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Puedes gastar por día",
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Bs. ${_dailyAvailableAvg.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    "Gasto diario - Semana ${_getWeekOfMonth(DateTime.now()) - 1} (Actual) - ${_getMonthName(DateTime.now().month)}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // GRÁFICO (Altura reducida a 220)
                  Container(
                    height: 220,
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY:
                            _getMaxY() *
                            1.1, // Un poco más de espacio para etiquetas
                        barTouchData: BarTouchData(
                          enabled:
                              false, // Desactivar interacción táctil para que no parpadee
                          touchTooltipData: BarTouchTooltipData(
                            tooltipBgColor: Colors.transparent,
                            tooltipPadding: EdgeInsets.zero,
                            tooltipMargin: 2, // Pegado a la barra
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              return BarTooltipItem(
                                rod.toY.round().toString(),
                                const TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10, // Texto pequeño
                                ),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                const days = [
                                  'L',
                                  'M',
                                  'M',
                                  'J',
                                  'V',
                                  'S',
                                  'D',
                                ];
                                final index = value.toInt();
                                if (index >= 0 && index < days.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(
                                      days[index],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  );
                                }
                                return const Text('');
                              },
                              reservedSize: 30,
                            ),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        barGroups: _generateBars(),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // --- NUEVA LISTA DE DETALLE DE MES COMPLETO ---
                  Text(
                    "Detalle Mes Actual: ${_getMonthName(_currentMonth.month)} - ${_currentMonth.year}",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildMonthlyList(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  int _getWeekOfMonth(DateTime date) {
    final firstDay = DateTime(date.year, date.month, 1);
    final dayOfWeek = firstDay.weekday;
    // Ajuste simple para semana del mes
    return ((date.day + dayOfWeek - 2) / 7).ceil() + 1;
  }

  // Helper para construir la lista ...
  Widget _buildMonthlyList() {
    // Ordenamos las llaves por día (1..31)
    final days = _monthDailyTotals.keys.toList()..sort();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: days.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final day = days[index];
          final amount = _monthDailyTotals[day] ?? 0;

          // Construimos la fecha real
          final date = DateTime(_currentMonth.year, _currentMonth.month, day);

          final weekDayName = [
            'Lunes',
            'Martes',
            'Miércoles',
            'Jueves',
            'Viernes',
            'Sábado',
            'Domingo',
          ][date.weekday - 1];
          final dateStr = weekDayName;

          final isZero = amount == 0;

          return ListTile(
            onTap: () {
              widget.onDateSelected(date);
            },
            dense: true,
            leading: CircleAvatar(
              backgroundColor: isZero
                  ? Colors.grey.shade100
                  : Colors.blue.shade50,
              child: Text(
                "$day",
                style: TextStyle(
                  color: isZero ? Colors.grey : Colors.blue,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            title: Text(
              dateStr,
              style: TextStyle(color: isZero ? Colors.grey : Colors.black87),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Bs. ${amount.toStringAsFixed(2)}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isZero ? Colors.grey : Colors.black,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  double _getMaxY() {
    double max = 0;
    for (var val in _dailyTotalsWeek) {
      if (val > max) max = val;
    }
    return max == 0 ? 100 : max * 1.2;
  }

  List<BarChartGroupData> _generateBars() {
    List<BarChartGroupData> bars = [];
    for (int i = 0; i < 7; i++) {
      bars.add(
        BarChartGroupData(
          x: i,
          showingTooltipIndicators: [0],
          barRods: [
            BarChartRodData(
              toY: _dailyTotalsWeek[i],
              color: Colors.blue,
              width: 16,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: _getMaxY(),
                color: Colors.grey.shade200,
              ),
            ),
          ],
        ),
      );
    }
    return bars;
  }

  Widget _buildBudgetInfo(String label, double amount, {bool isBold = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          "Bs. ${amount.toStringAsFixed(2)}",
          style: TextStyle(
            color: Colors.white,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 18 : 15,
          ),
        ),
      ],
    );
  }
}
