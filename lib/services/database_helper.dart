import 'dart:async';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('gastos_offline_v2.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    String path;
    if (Platform.isWindows) {
      // In Windows, when installed in Program Files, we must use a writable directory
      final String localAppData =
          Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
      final String dbDirectory = p.join(localAppData, 'GastosDuQuen');
      // Create directory if it doesn't exist
      await Directory(dbDirectory).create(recursive: true);
      path = p.join(dbDirectory, filePath);
    } else {
      final dbPath = await getDatabasesPath();
      path = p.join(dbPath, filePath);
    }

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      description TEXT NOT NULL,
      amount REAL NOT NULL,
      date TEXT NOT NULL,
      user_id INTEGER NOT NULL,
      daily_register_id INTEGER,
      is_synced INTEGER DEFAULT 0,
      supabase_id INTEGER,
      is_deleted INTEGER DEFAULT 0
    )
    ''');

    await db.execute('''
    CREATE TABLE usuarios_local (
      id INTEGER PRIMARY KEY,
      email TEXT NOT NULL
    )
    ''');

    await db.execute('''
    CREATE TABLE monthly_budget (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      month INTEGER NOT NULL,
      year INTEGER NOT NULL,
      amount REAL NOT NULL,
      is_synced INTEGER DEFAULT 0,
      supabase_id INTEGER
    )
    ''');

    await db.execute('''
    CREATE TABLE daily_registers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      opened_at TEXT NOT NULL,
      closed_at TEXT,
      initial_amount REAL NOT NULL DEFAULT 0,
      final_amount REAL,
      status TEXT NOT NULL DEFAULT 'open',
      is_synced INTEGER DEFAULT 0,
      supabase_id INTEGER
    )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN is_deleted INTEGER DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute('''
      CREATE TABLE monthly_budget (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        month INTEGER NOT NULL,
        year INTEGER NOT NULL,
        amount REAL NOT NULL
      )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN daily_register_id INTEGER',
      );
      await db.execute('''
      CREATE TABLE daily_registers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        initial_amount REAL NOT NULL DEFAULT 0,
        final_amount REAL,
        status TEXT NOT NULL DEFAULT 'open'
      )
      ''');
    }
    if (oldVersion < 5) {
      // Add sync columns to existing tables
      await db.execute(
        'ALTER TABLE daily_registers ADD COLUMN is_synced INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE daily_registers ADD COLUMN supabase_id INTEGER',
      );
      await db.execute(
        'ALTER TABLE monthly_budget ADD COLUMN is_synced INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE monthly_budget ADD COLUMN supabase_id INTEGER',
      );
    }
  }

  Future<void> saveLocalUser(int id, String email) async {
    final db = await instance.database;
    await db.delete('usuarios_local');
    await db.insert('usuarios_local', {'id': id, 'email': email});
  }

  Future<void> logoutLocalUser() async {
    final db = await instance.database;
    await db.delete('usuarios_local');
  }

  Future<int> insertExpense(Map<String, dynamic> row) async {
    final db = await instance.database;
    // ensure default
    if (!row.containsKey('is_deleted')) {
      row['is_deleted'] = 0;
    }
    return await db.insert('expenses', row);
  }

  Future<int> updateExpense(int id, Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.update('expenses', row, where: 'id = ?', whereArgs: [id]);
  }

  // Soft delete for sync logic
  Future<int> softDeleteExpense(int id) async {
    final db = await instance.database;
    return await db.update(
      'expenses',
      {'is_deleted': 1, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Hard delete (used after sync confirms delete or for permanent removal)
  Future<int> deleteExpensePermanent(int id) async {
    final db = await instance.database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  // Backwards compatibility shim if needed, but we prefer softDelete / deleteExpensePermanent
  Future<int> deleteExpense(int id) async {
    return deleteExpensePermanent(id);
  }

  Future<int> updateSupabaseId(int localId, int supabaseId) async {
    final db = await instance.database;
    return await db.update(
      'expenses',
      {'supabase_id': supabaseId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<bool> checkIfSupabaseIdExists(int supabaseId) async {
    final db = await instance.database;
    final res = await db.query(
      'expenses',
      where: 'supabase_id = ?',
      whereArgs: [supabaseId],
    );
    return res.isNotEmpty;
  }

  Future<List<Map<String, dynamic>>> getExpenses(
    int userId,
    String date,
  ) async {
    final db = await instance.database;
    return await db.query(
      'expenses',
      where: 'user_id = ? AND date = ? AND is_deleted = 0',
      whereArgs: [userId, date],
      orderBy: 'id DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedExpenses(int userId) async {
    final db = await instance.database;
    return await db.query(
      'expenses',
      where: 'user_id = ? AND is_synced = 0 AND is_deleted = 0',
      whereArgs: [userId],
    );
  }

  Future<List<Map<String, dynamic>>> getExpensesToDelete(int userId) async {
    final db = await instance.database;
    return await db.query(
      'expenses',
      where: 'user_id = ? AND is_deleted = 1 AND is_synced = 0',
      whereArgs: [userId],
    );
  }

  Future<int> markAsSynced(int id) async {
    final db = await instance.database;
    return await db.update(
      'expenses',
      {'is_synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getExpensesInDateRange(
    int userId,
    String startDate,
    String endDate,
  ) async {
    final db = await instance.database;
    return await db.query(
      'expenses',
      where: 'user_id = ? AND date >= ? AND date <= ? AND is_deleted = 0',
      whereArgs: [userId, startDate, endDate],
      orderBy: 'date ASC',
    );
  }

  // --- BUDGET METHODS ---
  Future<void> setMonthlyBudget(
    int userId,
    int month,
    int year,
    double amount,
  ) async {
    final db = await instance.database;
    final res = await db.query(
      'monthly_budget',
      where: 'user_id = ? AND month = ? AND year = ?',
      whereArgs: [userId, month, year],
    );
    if (res.isNotEmpty) {
      await db.update(
        'monthly_budget',
        {'amount': amount, 'is_synced': 0},
        where: 'user_id = ? AND month = ? AND year = ?',
        whereArgs: [userId, month, year],
      );
    } else {
      await db.insert('monthly_budget', {
        'user_id': userId,
        'month': month,
        'year': year,
        'amount': amount,
        'is_synced': 0,
      });
    }
  }

  Future<double> getMonthlyBudget(int userId, int month, int year) async {
    final db = await instance.database;
    final res = await db.query(
      'monthly_budget',
      where: 'user_id = ? AND month = ? AND year = ?',
      whereArgs: [userId, month, year],
    );
    if (res.isNotEmpty) {
      return (res.first['amount'] as num).toDouble();
    }
    return 0.0;
  }

  Future<List<Map<String, dynamic>>> getUnsyncedBudgets(int userId) async {
    final db = await instance.database;
    return await db.query(
      'monthly_budget',
      where: 'user_id = ? AND is_synced = 0',
      whereArgs: [userId],
    );
  }

  Future<void> markBudgetSynced(int id, int supabaseId) async {
    final db = await instance.database;
    await db.update(
      'monthly_budget',
      {'is_synced': 1, 'supabase_id': supabaseId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- DAILY REGISTER METHODS (CAJA) ---

  Future<int> openDailyRegister(int userId, double initialAmount) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert('daily_registers', {
      'user_id': userId,
      'opened_at': now,
      'initial_amount': initialAmount,
      'status': 'open',
      'is_synced': 0,
    });
  }

  Future<int> closeDailyRegister(int registerId, double finalAmount) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update(
      'daily_registers',
      {
        'final_amount': finalAmount,
        'closed_at': now,
        'status': 'closed',
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [registerId],
    );
  }

  Future<Map<String, dynamic>?> getActiveDailyRegister(int userId) async {
    final db = await instance.database;
    final res = await db.query(
      'daily_registers',
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, 'open'],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  Future<double> getTotalExpensesInRegister(int registerId) async {
    final db = await instance.database;
    final res = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses WHERE daily_register_id = ? AND is_deleted = 0',
      [registerId],
    );
    return (res.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getUnsyncedRegisters(int userId) async {
    final db = await instance.database;
    return await db.query(
      'daily_registers',
      where: 'user_id = ? AND is_synced = 0',
      whereArgs: [userId],
    );
  }

  Future<void> markRegisterSynced(int id, int supabaseId) async {
    final db = await instance.database;
    await db.update(
      'daily_registers',
      {'is_synced': 1, 'supabase_id': supabaseId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int?> getLocalRegisterIdBySupabaseId(int supabaseId) async {
    final db = await instance.database;
    final res = await db.query(
      'daily_registers',
      columns: ['id'],
      where: 'supabase_id = ?',
      whereArgs: [supabaseId],
    );
    return res.isNotEmpty ? res.first['id'] as int : null;
  }

  Future<int?> getSupabaseRegisterIdByLocalId(int localId) async {
    final db = await instance.database;
    final res = await db.query(
      'daily_registers',
      columns: ['supabase_id'],
      where: 'id = ?',
      whereArgs: [localId],
    );
    return res.isNotEmpty ? res.first['supabase_id'] as int? : null;
  }
}
