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

  @override
  void initState() {
    super.initState();
    _loadLocalExpenses();
    _syncData();
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

  // --- AGREGAR ---
  // --- AGREGAR ---
  Future<void> _showAddDialog() async {
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
                  'is_synced': 0,
                  'supabase_id': null,
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

    String? lastError; // Para capturar errores y mostrarlos

    try {
      final supabase = Supabase.instance.client;
      final db = DatabaseHelper.instance;

      // ------------------------------------------------
      // 1. PUSH DELETES
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
      // 2. PUSH INSERTS / UPDATES
      // ------------------------------------------------
      final unsynced = await db.getUnsyncedExpenses(widget.userId);
      for (var row in unsynced) {
        if (row['is_deleted'] == 1) continue;

        final supabaseId = row['supabase_id'];

        if (supabaseId == null) {
          // INSERT
          try {
            final response = await supabase
                .from('expenses')
                .insert({
                  'description': row['description'],
                  'amount': row['amount'],
                  'date': row['date'],
                  'user_id': row['user_id'],
                })
                .select()
                .single();

            final remoteId = (response['id'] as num).toInt();

            await db.updateSupabaseId(row['id'], remoteId);
            await db.markAsSynced(row['id']);
          } catch (e) {
            debugPrint("Error sync-insert: $e");
            lastError = "Error al subir '${row['description']}': $e";
          }
        } else {
          // UPDATE
          try {
            await supabase
                .from('expenses')
                .update({
                  'description': row['description'],
                  'amount': row['amount'],
                })
                .eq('id', supabaseId);
            await db.markAsSynced(row['id']);
          } catch (e) {
            debugPrint("Error sync-update: $e");
            lastError = "Error al actualizar '${row['description']}': $e";
          }
        }
      }

      // ------------------------------------------------
      // 3. PULL
      // ------------------------------------------------
      int newItemsCount = 0;
      try {
        final remoteData = await supabase
            .from('expenses')
            .select()
            .eq('user_id', widget.userId);

        for (var remoteItem in remoteData) {
          final rId = (remoteItem['id'] as num).toInt();
          final exists = await db.checkIfSupabaseIdExists(rId);

          if (!exists) {
            await db.insertExpense({
              'description': remoteItem['description'],
              'amount': (remoteItem['amount'] as num).toDouble(),
              'date': remoteItem['date'],
              'user_id': widget.userId,
              'is_synced': 1,
              'supabase_id': rId,
              'is_deleted': 0,
            });
            newItemsCount++;
          }
        }
      } catch (e) {
        debugPrint("Error pull: $e");
        lastError = "Error obteniendo datos: $e";
      }

      if (!mounted) return;
      await _loadLocalExpenses();

      if (!mounted) return;

      if (lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lastError),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (unsynced.isNotEmpty ||
          toDelete.isNotEmpty ||
          newItemsCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Sincronización completada"),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("Error global sync: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error de conexión: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    double total = _localExpenses.fold(
      0,
      (sum, item) => sum + (item['amount'] as num).toDouble(),
    );

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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
                  // Indicador visual de gesto (pequeña barra)
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Text(
                    _displayDate,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Bs. ${total.toStringAsFixed(2)}",
                    style: const TextStyle(
                      fontSize: 36,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "TOTAL DIARIO",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade100,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
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
