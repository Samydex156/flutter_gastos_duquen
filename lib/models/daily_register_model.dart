class DailyRegister {
  final int? id;
  final int userId;
  final String openedAt;
  final String? closedAt;
  final double initialAmount;
  final double? finalAmount;
  final String status; // 'open' or 'closed'

  DailyRegister({
    this.id,
    required this.userId,
    required this.openedAt,
    this.closedAt,
    required this.initialAmount,
    this.finalAmount,
    this.status = 'open',
  });

  factory DailyRegister.fromMap(Map<String, dynamic> map) {
    return DailyRegister(
      id: map['id'],
      userId: map['user_id'],
      openedAt: map['opened_at'],
      closedAt: map['closed_at'],
      initialAmount: (map['initial_amount'] as num).toDouble(),
      finalAmount: map['final_amount'] != null
          ? (map['final_amount'] as num).toDouble()
          : null,
      status: map['status'] ?? 'open',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'opened_at': openedAt,
      'closed_at': closedAt,
      'initial_amount': initialAmount,
      'final_amount': finalAmount,
      'status': status,
    };
  }
}
