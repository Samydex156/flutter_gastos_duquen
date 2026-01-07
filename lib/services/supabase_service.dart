import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // --- EXPENSES ---
  Future<List<Map<String, dynamic>>> getExpenses(
    int userId,
    String date,
  ) async {
    final data = await _supabase
        .from('expenses')
        .select()
        .eq('user_id', userId)
        .eq('date', date)
        .order('id', ascending: false);

    // On web, everything from Supabase is considered synced
    return data.map((e) => {...e, 'is_synced': 1}).toList();
  }

  Future<int> insertExpense(Map<String, dynamic> row) async {
    final response = await _supabase
        .from('expenses')
        .insert({
          'description': row['description'],
          'amount': row['amount'],
          'date': row['date'],
          'user_id': row['user_id'],
          'daily_register_id': row['daily_register_id'],
        })
        .select()
        .single();
    return response['id'] as int;
  }

  Future<void> updateExpense(int id, Map<String, dynamic> row) async {
    await _supabase
        .from('expenses')
        .update({'description': row['description'], 'amount': row['amount']})
        .eq('id', id);
  }

  Future<void> deleteExpense(int id) async {
    await _supabase.from('expenses').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> getExpensesInDateRange(
    int userId,
    String startDate,
    String endDate,
  ) async {
    return await _supabase
        .from('expenses')
        .select()
        .eq('user_id', userId)
        .gte('date', startDate)
        .lte('date', endDate)
        .order('date', ascending: true);
  }

  // --- BUDGET ---
  Future<double> getMonthlyBudget(int userId, int month, int year) async {
    final res = await _supabase
        .from('budgets')
        .select('amount')
        .eq('user_id', userId)
        .eq('month', month)
        .eq('year', year)
        .maybeSingle();
    return res != null ? (res['amount'] as num).toDouble() : 0.0;
  }

  Future<void> setMonthlyBudget(
    int userId,
    int month,
    int year,
    double amount,
  ) async {
    await _supabase.from('budgets').upsert({
      'user_id': userId,
      'month': month,
      'year': year,
      'amount': amount,
    });
  }

  // --- DAILY REGISTER (CAJA) ---
  Future<Map<String, dynamic>?> getActiveDailyRegister(int userId) async {
    final res = await _supabase
        .from('daily_registers')
        .select()
        .eq('user_id', userId)
        .eq('status', 'open')
        .maybeSingle();
    return res;
  }

  Future<int> openDailyRegister(int userId, double initialAmount) async {
    final res = await _supabase
        .from('daily_registers')
        .insert({
          'user_id': userId,
          'initial_amount': initialAmount,
          'status': 'open',
          'opened_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();
    return res['id'] as int;
  }

  Future<void> closeDailyRegister(int registerId, double finalAmount) async {
    await _supabase
        .from('daily_registers')
        .update({
          'final_amount': finalAmount,
          'status': 'closed',
          'closed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', registerId);
  }

  Future<double> getTotalExpensesInRegister(int registerId) async {
    final res = await _supabase
        .from('expenses')
        .select('amount')
        .eq('daily_register_id', registerId);

    double total = 0;
    for (var item in res) {
      total += (item['amount'] as num).toDouble();
    }
    return total;
  }
}
