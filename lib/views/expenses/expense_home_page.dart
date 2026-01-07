import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/database_helper.dart';
import '../reports/daily_report_pdf_page.dart';
import '../login_page.dart';

class ExpenseHomePage extends StatefulWidget {
  final int userId;
  final String userEmail;
  const ExpenseHomePage({
    super.key,
    required this.userId,
    required this.userEmail,
  });

  @override
  State<ExpenseHomePage> createState() => ExpenseHomePageState();
}

class ExpenseHomePageState extends State<ExpenseHomePage> {
  DateTime _selectedDate = DateTime.now();
  String get _dateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);
  String get _displayDate => DateFormat('dd/MM/yyyy').format(_selectedDate);

  List<Map<String, dynamic>> _localExpenses = [];
  bool _isSyncing = false;
  int? _activeRegisterId;
  double _monthlyBudget = 0.0;
  double _monthlyTotal = 0.0;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await _checkActiveRegister();
    await _loadLocalExpenses();
    await _loadBudgetInfo();
    _syncData();
  }

  Future<void> _checkActiveRegister() async {
    final reg = await DatabaseHelper.instance.getActiveDailyRegister(
      widget.userId,
    );
    if (mounted) {
      setState(() {
        _activeRegisterId = reg != null ? reg['id'] as int : null;
      });
    }
  }

  Future<void> _loadBudgetInfo() async {
    final now = DateTime.now();
    final budget = await DatabaseHelper.instance.getMonthlyBudget(
      widget.userId,
      now.month,
      now.year,
    );

    // Calculate monthly total
    final firstDay = DateTime(now.year, now.month, 1);
    final lastDay = DateTime(now.year, now.month + 1, 0);
    final expenses = await DatabaseHelper.instance.getExpensesInDateRange(
      widget.userId,
      DateFormat('yyyy-MM-dd').format(firstDay),
      DateFormat('yyyy-MM-dd').format(lastDay),
    );

    double total = expenses.fold(
      0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

    if (mounted) {
      setState(() {
        _monthlyBudget = budget;
        _monthlyTotal = total;
      });
    }
  }

  // --- PUBLICO PARA NAVEGACION ---
  void setDate(DateTime date) {
    setState(() {
      _selectedDate = date;
    });
    _loadLocalExpenses();
  }

  Future<void> _loadLocalExpenses() async {
    final data = await DatabaseHelper.instance.getExpenses(
      widget.userId,
      _dateStr,
    );
    if (mounted) setState(() => _localExpenses = data);
  }

  // --- CAMBIAR FECHA RAPIDO ---
  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadLocalExpenses();
  }

  // --- ABRIR CAJA ---
  Future<void> _showOpenBoxDialog() async {
    final amountCtrl = TextEditingController(text: "0");
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Abrir Caja Diaria"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Ingresa el monto inicial en efectivo:"),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(prefixText: "Bs. "),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0.0;
              await DatabaseHelper.instance.openDailyRegister(
                widget.userId,
                amount,
              );
              if (context.mounted) Navigator.pop(context);
              _checkActiveRegister();
            },
            child: const Text("Abrir Caja"),
          ),
        ],
      ),
    );
  }

  // --- CERRAR CAJA ---
  Future<void> _showCloseBoxDialog() async {
    if (_activeRegisterId == null) return;

    final finalAmountCtrl = TextEditingController();
    final reg = await DatabaseHelper.instance.getActiveDailyRegister(
      widget.userId,
    );
    final initialAmount = (reg!['initial_amount'] as num).toDouble();
    final totalExpenses = await DatabaseHelper.instance
        .getTotalExpensesInRegister(_activeRegisterId!);
    final expectedAmount = initialAmount - totalExpenses;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cerrar Caja (Arqueo)"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Monto Inicial: Bs. ${initialAmount.toStringAsFixed(2)}"),
            Text("Gastos Registrados: Bs. ${totalExpenses.toStringAsFixed(2)}"),
            Text(
              "Esperado en Caja: Bs. ${expectedAmount.toStringAsFixed(2)}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),
            const Text("Ingresa el monto físico real:"),
            TextField(
              controller: finalAmountCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(prefixText: "Bs. "),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              final finalAmount = double.tryParse(finalAmountCtrl.text) ?? 0.0;
              final diff = expectedAmount - finalAmount;

              await DatabaseHelper.instance.closeDailyRegister(
                _activeRegisterId!,
                finalAmount,
              );

              if (context.mounted) {
                Navigator.pop(context);
                String msg = "Caja cerrada.";
                if (diff == 0) {
                  msg += " ¡Cuadra perfecto!";
                } else if (diff > 0) {
                  msg += " Faltan Bs. ${diff.toStringAsFixed(2)}";
                } else {
                  msg += " Sobran Bs. ${(-diff).toStringAsFixed(2)}";
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: diff == 0 ? Colors.green : Colors.orange,
                  ),
                );
              }
              _checkActiveRegister();
            },
            child: const Text("Cerrar Caja"),
          ),
        ],
      ),
    );
  }

  // --- AGREGAR ---
  Future<void> _showAddDialog() async {
    if (_activeRegisterId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Debes abrir caja primero"),
          backgroundColor: Colors.red,
        ),
      );
      _showOpenBoxDialog();
      return;
    }

    final addDescCtrl = TextEditingController();
    final addAmountCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Agregar Gasto"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: addDescCtrl,
              decoration: const InputDecoration(labelText: "Descripción"),
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
            ),
            TextField(
              controller: addAmountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Monto"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              final desc = addDescCtrl.text.trim();
              final amount = double.tryParse(addAmountCtrl.text.trim());

              if (desc.isNotEmpty && amount != null) {
                await DatabaseHelper.instance.insertExpense({
                  'description': desc,
                  'amount': amount,
                  'date': _dateStr,
                  'user_id': widget.userId,
                  'daily_register_id': _activeRegisterId,
                  'is_synced': 0,
                  'supabase_id': null,
                });

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (!mounted) return;
                await _loadLocalExpenses();
                await _loadBudgetInfo();
                _syncData();
              }
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  // --- EDITAR ---
  Future<void> _showEditDialog(Map<String, dynamic> item) async {
    final editDescCtrl = TextEditingController(text: item['description']);
    final editAmountCtrl = TextEditingController(
      text: (item['amount'] as num).toString(),
    );

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Editar Gasto"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: editDescCtrl,
              decoration: const InputDecoration(labelText: "Descripción"),
            ),
            TextField(
              controller: editAmountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Monto"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newDesc = editDescCtrl.text.trim();
              final newAmount = double.tryParse(editAmountCtrl.text.trim());
              if (newDesc.isNotEmpty && newAmount != null) {
                await DatabaseHelper.instance.updateExpense(item['id'], {
                  'description': newDesc,
                  'amount': newAmount,
                  'is_synced': 0,
                });

                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                if (!mounted) return;
                await _loadLocalExpenses();
                _syncData();
              }
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  // --- ELIMINAR ---
  Future<void> _deleteExpense(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Eliminar Gasto"),
        content: Text("¿Seguro que quieres borrar '${item['description']}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Eliminar", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 1. Verificar conectividad
      var connectivity = await Connectivity().checkConnectivity();
      bool isOnline = !connectivity.contains(ConnectivityResult.none);

      // 2. Intentar borrar
      if (isOnline) {
        // ONLINE: Borrar remoto y luego local permanente
        final supabaseId = item['supabase_id'];
        if (supabaseId != null) {
          try {
            await Supabase.instance.client
                .from('expenses')
                .delete()
                .eq('id', supabaseId);
          } catch (e) {
            debugPrint("Error borrando remoto: $e");
            // Si falla remoto, ¿qué hacemos?
            // Podríamos marcar softDelete para reintentar luego,
            // pero si estamos 'Online' asumimos que debería funcionar.
            // Para seguridad: softDelete.
            await DatabaseHelper.instance.softDeleteExpense(item['id']);
            await _loadLocalExpenses();
            return;
          }
        }
        // Si borró remoto OK (o no tenia supabase_id), borramos físico local
        await DatabaseHelper.instance.deleteExpensePermanent(item['id']);
      } else {
        // OFFLINE: Soft delete local
        await DatabaseHelper.instance.softDeleteExpense(item['id']);
      }

      await _loadLocalExpenses();
    }
  }

  // --- OPCIONES AL TOCAR ITEM ---
  void _showItemOptions(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  item['description'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Editar'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Eliminar'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteExpense(item);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- SYNC ---
  Future<void> _syncData() async {
    if (_isSyncing) return;
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (!mounted) return;
    if (connectivityResult.contains(ConnectivityResult.none)) return;

    setState(() => _isSyncing = true);

    String? lastError;

    try {
      final supabase = Supabase.instance.client;
      final db = DatabaseHelper.instance;

      // ------------------------------------------------
      // 0. PUSH DAILY REGISTERS (CAJAS) - Necesario antes de los gastos
      // ------------------------------------------------
      final unsyncedRegs = await db.getUnsyncedRegisters(widget.userId);
      for (var reg in unsyncedRegs) {
        try {
          final data = {
            'user_id': reg['user_id'],
            'opened_at': reg['opened_at'],
            'closed_at': reg['closed_at'],
            'initial_amount': reg['initial_amount'],
            'final_amount': reg['final_amount'],
            'status': reg['status'],
          };

          if (reg['supabase_id'] == null) {
            final res = await supabase
                .from('daily_registers')
                .insert(data)
                .select()
                .single();
            await db.markRegisterSynced(reg['id'], res['id'] as int);
          } else {
            await supabase
                .from('daily_registers')
                .update(data)
                .eq('id', reg['supabase_id']);
            await db.markRegisterSynced(reg['id'], reg['supabase_id'] as int);
          }
        } catch (e) {
          debugPrint("Error sync-reg: $e");
        }
      }

      // ------------------------------------------------
      // 0.1 PUSH BUDGETS
      // ------------------------------------------------
      final unsyncedBudgets = await db.getUnsyncedBudgets(widget.userId);
      for (var b in unsyncedBudgets) {
        try {
          final data = {
            'user_id': b['user_id'],
            'month': b['month'],
            'year': b['year'],
            'amount': b['amount'],
          };
          // Upsert for budget
          final res = await supabase
              .from('budgets')
              .upsert(data)
              .select()
              .single();
          await db.markBudgetSynced(b['id'], res['id'] as int);
        } catch (e) {
          debugPrint("Error sync-budget: $e");
        }
      }

      // ------------------------------------------------
      // 1. PUSH DELETES EXPENSES
      // ------------------------------------------------
      final toDelete = await db.getExpensesToDelete(widget.userId);
      for (var row in toDelete) {
        final supabaseId = row['supabase_id'];
        if (supabaseId != null) {
          try {
            await supabase.from('expenses').delete().eq('id', supabaseId);
          } catch (e) {
            debugPrint("Error sync-delete: $e");
            lastError = "Error al borrar en nube: $e";
          }
        }
        await db.deleteExpensePermanent(row['id']);
      }

      // ------------------------------------------------
      // 2. PUSH INSERTS / UPDATES EXPENSES
      // ------------------------------------------------
      final unsynced = await db.getUnsyncedExpenses(widget.userId);
      for (var row in unsynced) {
        if (row['is_deleted'] == 1) continue;

        // Map local daily_register_id to supabase id
        int? remoteRegId;
        if (row['daily_register_id'] != null) {
          remoteRegId = await db.getSupabaseRegisterIdByLocalId(
            row['daily_register_id'],
          );
        }

        final supabaseId = row['supabase_id'];
        final rowData = {
          'description': row['description'],
          'amount': row['amount'],
          'date': row['date'],
          'user_id': row['user_id'],
          'daily_register_id': remoteRegId,
        };

        if (supabaseId == null) {
          try {
            final response = await supabase
                .from('expenses')
                .insert(rowData)
                .select()
                .single();
            await db.updateSupabaseId(row['id'], response['id'] as int);
            await db.markAsSynced(row['id']);
          } catch (e) {
            debugPrint("Error sync-insert: $e");
            lastError = "Error al subir '${row['description']}': $e";
          }
        } else {
          try {
            await supabase
                .from('expenses')
                .update(rowData)
                .eq('id', supabaseId);
            await db.markAsSynced(row['id']);
          } catch (e) {
            debugPrint("Error sync-update: $e");
            lastError = "Error al actualizar '${row['description']}': $e";
          }
        }
      }

      // ------------------------------------------------
      // 3. PULL (Opcional simplificado)
      // ------------------------------------------------
      // Aquí se podrían traer registros remotos creados en otros dispositivos
      // Por brevedad, mantendremos la lógica actual de gastos pero podrías expandirla.

      if (!mounted) return;
      await _loadLocalExpenses();
      await _loadBudgetInfo();
      _checkActiveRegister();

      if (lastError != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lastError), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint("Error global sync: $e");
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _logout() async {
    await DatabaseHelper.instance.logoutLocalUser();
    if (!mounted) return;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  Future<void> _showSetBudgetDialog() async {
    final budgetCtrl = TextEditingController(text: _monthlyBudget.toString());
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Presupuesto Mensual"),
        content: TextField(
          controller: budgetCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "Monto del presupuesto",
            prefixText: "Bs. ",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(budgetCtrl.text) ?? 0.0;
              final now = DateTime.now();
              await DatabaseHelper.instance.setMonthlyBudget(
                widget.userId,
                now.month,
                now.year,
                val,
              );
              if (context.mounted) Navigator.pop(context);
              _loadBudgetInfo();
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double total = _localExpenses.fold(
      0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

    double remainingBudget = _monthlyBudget - _monthlyTotal;
    bool isOverBudget = remainingBudget < 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text("Gastos DuQuen", style: TextStyle(fontSize: 18)),
            Text(
              widget.userEmail,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (_activeRegisterId != null)
            IconButton(
              icon: const Icon(Icons.lock_clock),
              tooltip: "Cerrar Caja (Arqueo)",
              onPressed: _showCloseBoxDialog,
            ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.sync),
            tooltip: "Sincronizar datos",
            onPressed: _isSyncing ? null : _syncData,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: "Generar PDF",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DailyReportPdfPage(
                    userId: widget.userId,
                    userEmail: widget.userEmail,
                    dateStr: _dateStr,
                    displayDate: _displayDate,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Cerrar sesión",
            onPressed: _logout,
          ),
        ],
      ),
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          // Swipe Right -> Anterior
          if (details.primaryVelocity! > 0) {
            _changeDate(-1);
          }
          // Swipe Left -> Siguiente
          else if (details.primaryVelocity! < 0) {
            _changeDate(1);
          }
        },
        child: Column(
          children: [
            // HEADER MODERNO
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade800, Colors.blue.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayDate,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Bs. ${total.toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 32,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -1.0,
                            ),
                          ),
                          Text(
                            "TOTAL DIARIO",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade100,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                      if (_activeRegisterId == null)
                        ElevatedButton.icon(
                          onPressed: _showOpenBoxDialog,
                          icon: const Icon(Icons.no_encryption_gmailerrorred),
                          label: const Text("ABRIR CAJA"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        )
                      else
                        const Column(
                          children: [
                            Icon(Icons.check_circle, color: Colors.greenAccent),
                            Text(
                              "CAJA ABIERTA",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // BUDGET SUMMARY CARD
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: InkWell(
                onTap: _showSetBudgetDialog,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isOverBudget
                        ? Colors.red.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isOverBudget
                          ? Colors.red.shade200
                          : Colors.green.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Presupuesto Mensual",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                "Bs. ${_monthlyBudget.toStringAsFixed(2)}",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isOverBudget ? "Excedido" : "Restante",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isOverBudget
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                              Text(
                                "Bs. ${remainingBudget.abs().toStringAsFixed(2)}",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: isOverBudget
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: _monthlyBudget > 0
                              ? (_monthlyTotal / _monthlyBudget).clamp(0, 1)
                              : 0,
                          backgroundColor: Colors.white,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isOverBudget ? Colors.red : Colors.blue,
                          ),
                          minHeight: 8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // LISTA
            Expanded(
              child: _localExpenses.isEmpty
                  ? const Center(child: Text("No hay gastos registrados"))
                  : ListView.builder(
                      itemCount: _localExpenses.length,
                      itemBuilder: (context, index) {
                        final item = _localExpenses[index];
                        final isSynced = item['is_synced'] == 1;
                        final iconBgColor = isSynced
                            ? Colors.blue.shade50
                            : Colors.orange.shade50;
                        final iconColor = isSynced
                            ? Colors.blue
                            : Colors.orange;
                        final iconData = isSynced
                            ? Icons.check
                            : Icons.cloud_upload;

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ), // Slightly more spacing
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: InkWell(
                            onTap: () => _showItemOptions(item),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  // Icono de Estado (Cloud status)
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: iconBgColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      iconData,
                                      color: iconColor,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Descripción
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['description'],
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (!isSynced)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4.0,
                                            ),
                                            child: Text(
                                              "Sincronizando...",
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.orange.shade800,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Monto
                                  Text(
                                    "Bs. ${(item['amount'] as num).toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        tooltip: 'Agregar Gasto',
        child: const Icon(Icons.add),
      ),
    );
  }
}
