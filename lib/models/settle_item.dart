/// 정산 품목 하나 (상품명, 단가, 개수, 누가 먹었는지)
class SettleItem {
  String name;
  int price; // 단가
  int qty; // 개수
  bool assignedAll; // '모두'로 나눌지
  Set<String> assigned; // 개별 선택된 사람들

  SettleItem({
    this.name = '',
    this.price = 0,
    this.qty = 1,
    this.assignedAll = false,
    Set<String>? assigned,
  }) : assigned = assigned ?? <String>{};

  /// 품목 소계 = 단가 × 개수
  int get total => price * (qty < 1 ? 1 : qty);

  /// 사람이 지정되어 있는지
  bool get hasTarget => assignedAll || assigned.isNotEmpty;

  /// 사람 선택 버튼에 보여줄 짧은 글자
  String targetLabel() {
    if (assignedAll) return '모두';
    if (assigned.isEmpty) return '선택';
    if (assigned.length == 1) return assigned.first;
    return '${assigned.first} 외 ${assigned.length - 1}';
  }
}
