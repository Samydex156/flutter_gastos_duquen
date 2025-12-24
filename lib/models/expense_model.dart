class Expense {
  final int? id;
  final String description;
  final double amount;
  final String date;
  final int userId;
  final int isSynced;
  final int? supabaseId;
  final int isDeleted;

  Expense({
    this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.userId,
    this.isSynced = 0,
    this.supabaseId,
    this.isDeleted = 0,
  });

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      description: map['description'],
      amount: (map['amount'] as num).toDouble(),
      date: map['date'],
      userId: map['user_id'],
      isSynced: map['is_synced'] ?? 0,
      supabaseId: map['supabase_id'],
      isDeleted: map['is_deleted'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'description': description,
      'amount': amount,
      'date': date,
      'user_id': userId,
      'is_synced': isSynced,
      'supabase_id': supabaseId,
      'is_deleted': isDeleted,
    };
  }
}
