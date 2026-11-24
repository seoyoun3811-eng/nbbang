import '../models/settle_item.dart';

/// 정산 계산 결과
class SettlementResult {
  final Map<String, int> perPerson; // 사람별 최종 금액 (올림 적용)
  final int itemsTotal; // 상품 금액 합계
  final int baseTotal; // 실제로 나눈 기준 금액 (결제금액 또는 상품 합계)
  final int roundedSum; // 올림 적용 후 전체 합

  SettlementResult({
    required this.perPerson,
    required this.itemsTotal,
    required this.baseTotal,
    required this.roundedSum,
  });

  /// 올림 때문에 기준 금액보다 더 걷히는 금액
  int get diff => roundedSum - baseTotal;
}

class Settlement {
  /// 품목별로 지정된 사람들에게 금액을 나눠서 사람별 합계를 구함
  ///
  /// paymentTotal: 결제금액. 주어지면 상품 합계와 달라도
  ///   각자 몫을 비율대로 맞춰서 전체 합이 결제금액과 같아지게 함
  /// roundUnit: 1(그대로), 10(10원 올림), 100(100원 올림)
  static SettlementResult split({
    required List<SettleItem> items,
    required List<String> people,
    required int roundUnit,
    int? paymentTotal,
  }) {
    final raw = {for (final p in people) p: 0.0};
    var itemsTotal = 0;

    for (final it in items) {
      if (it.total <= 0) continue;
      itemsTotal += it.total;

      final targets = (it.assignedAll || it.assigned.isEmpty)
          ? people
          : it.assigned.where(people.contains).toList();
      if (targets.isEmpty) continue;

      final share = it.total / targets.length;
      for (final t in targets) {
        raw[t] = raw[t]! + share;
      }
    }

    // 결제금액 기준으로 비율 맞추기
    var baseTotal = itemsTotal;
    if (paymentTotal != null && paymentTotal > 0 && itemsTotal > 0) {
      baseTotal = paymentTotal;
      if (paymentTotal != itemsTotal) {
        final ratio = paymentTotal / itemsTotal;
        raw.updateAll((k, v) => v * ratio);
      }
    }

    final unit = roundUnit < 1 ? 1 : roundUnit;
    // 부동소수점 오차로 1원 더 올라가는 것을 막기 위해 아주 작은 값을 빼고 올림
    final perPerson = raw.map((k, v) {
      final c = ((v - 1e-6) / unit).ceil();
      return MapEntry(k, (c < 0 ? 0 : c) * unit);
    });
    final roundedSum = perPerson.values.fold(0, (a, b) => a + b);

    return SettlementResult(
      perPerson: perPerson,
      itemsTotal: itemsTotal,
      baseTotal: baseTotal,
      roundedSum: roundedSum,
    );
  }
}
