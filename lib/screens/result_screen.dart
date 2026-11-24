import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/settle_item.dart';
import '../services/app_prefs.dart';
import '../services/settlement.dart';
import '../utils/format.dart';
import 'people_screen.dart' show kMe;

/// ④ 정산 결과 + 보내기 화면
class ResultScreen extends StatefulWidget {
  final List<String> people;
  final List<SettleItem> items;
  final String? store; // 상호명
  final String? datetime; // 거래 일시
  final int? paymentTotal; // 결제금액 (주어지면 이 금액 기준으로 나눔)

  const ResultScreen({
    super.key,
    required this.people,
    required this.items,
    this.store,
    this.datetime,
    this.paymentTotal,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late String _payer; // 결제한 사람 (받을 사람)
  int _roundUnit = 10; // 올림 단위: 1(그대로) / 10 / 100
  final _accountController = TextEditingController();
  final Set<String> _sentTo = {}; // 보내기 완료 표시

  @override
  void initState() {
    super.initState();
    _payer = widget.people.contains(kMe) ? kMe : widget.people.first;
    AppPrefs.loadAccount().then((v) {
      if (!mounted || v.isEmpty) return;
      setState(() => _accountController.text = v);
    });
  }

  @override
  void dispose() {
    _accountController.dispose();
    super.dispose();
  }

  SettlementResult get _result => Settlement.split(
        items: widget.items,
        people: widget.people,
        roundUnit: _roundUnit,
        paymentTotal: widget.paymentTotal,
      );

  // ───────────── 메시지 / 보내기 ─────────────

  String _messageFor(String name, int amount) {
    final b = StringBuffer();
    final store = widget.store;
    b.write(store == null ? '[N빵 정산]' : '[N빵 정산] $store');
    if (widget.datetime != null) b.write(' (${widget.datetime})');
    b.write('\n$name님 금액: ${won(amount)}원');
    b.write('\n(총 ${won(_result.baseTotal)}원 · 결제 $_payer)');
    final account = _accountController.text.trim();
    if (account.isNotEmpty) b.write('\n입금: $account');
    return b.toString();
  }

  /// 공유 시트를 열어서 카톡/문자 등으로 보내기
  Future<bool> _sendTo(String name, int amount) async {
    final result = await Share.share(_messageFor(name, amount),
        subject: 'N빵 정산');
    final ok = result.status == ShareResultStatus.success;
    if (ok && mounted) setState(() => _sentTo.add(name));
    return ok;
  }

  /// 전체 보내기: 결제자를 뺀 사람들에게 한 명씩 차례로
  Future<void> _sendAll() async {
    final res = _result;
    final targets =
        widget.people.where((p) => p != _payer).toList(growable: false);
    if (targets.isEmpty) return;

    for (final name in targets) {
      if (!mounted) return;
      final amount = res.perPerson[name] ?? 0;
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('다음: $name에게 보내기'),
          content: Text(
            _messageFor(name, amount),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, 'stop'),
                child: const Text('그만하기')),
            TextButton(
                onPressed: () => Navigator.pop(context, 'skip'),
                child: const Text('건너뛰기')),
            FilledButton(
                onPressed: () => Navigator.pop(context, 'send'),
                child: const Text('보내기')),
          ],
        ),
      );
      if (action == 'stop') return;
      if (action == 'skip') continue;
      await _sendTo(name, amount);
    }
  }

  // ───────────── 상세 보기 ─────────────

  void _showDetail(String name) {
    final res = _result;
    final lines = <Widget>[];
    for (final it in widget.items) {
      final targets = (it.assignedAll || it.assigned.isEmpty)
          ? widget.people
          : it.assigned.where(widget.people.contains).toList();
      if (!targets.contains(name) || it.total <= 0) continue;
      final share = it.total / targets.length;
      lines.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
                child: Text(it.name, overflow: TextOverflow.ellipsis)),
            Text(
              '${won(it.total)}원 ÷ ${targets.length} = ${won(share)}원',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      ));
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$name의 내역',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Flexible(child: ListView(shrinkWrap: true, children: lines)),
              if (res.baseTotal != res.itemsTotal)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '결제금액(${won(res.baseTotal)}원)에 맞춰 비율대로 조정했어요',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  const Text('최종 금액',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${won(res.perPerson[name] ?? 0)}원',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────── 화면 ─────────────

  @override
  Widget build(BuildContext context) {
    final res = _result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('정산 결과',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSummaryCard(res),
            const SizedBox(height: 10),
            for (final p in widget.people) _buildPersonTile(p, res),
            const SizedBox(height: 10),
            _buildAccountField(),
            const SizedBox(height: 90), // 하단 버튼에 가리지 않게 여백
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildSummaryCard(SettlementResult res) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.store != null)
            Text(widget.store!,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          if (widget.datetime != null)
            Text(widget.datetime!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          if (widget.store != null || widget.datetime != null)
            const SizedBox(height: 8),
          Text('총 금액', style: TextStyle(color: Colors.grey.shade700)),
          Text('${won(res.baseTotal)}원',
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('결제한 사람'),
              const Spacer(),
              DropdownButton<String>(
                value: _payer,
                underline: const SizedBox.shrink(),
                items: [
                  for (final p in widget.people)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) =>
                    setState(() => _payer = v ?? widget.people.first),
              ),
            ],
          ),
          Row(
            children: [
              const Text('원 단위'),
              const Spacer(),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('그대로')),
                  ButtonSegment(value: 10, label: Text('10원')),
                  ButtonSegment(value: 100, label: Text('100원')),
                ],
                selected: {_roundUnit},
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(
                      const TextStyle(fontSize: 12)),
                ),
                onSelectionChanged: (s) =>
                    setState(() => _roundUnit = s.first),
              ),
            ],
          ),
          if (res.diff > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '올림 때문에 합계보다 ${won(res.diff)}원 많아져요',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPersonTile(String name, SettlementResult res) {
    final amount = res.perPerson[name] ?? 0;
    final isPayer = name == _payer;
    final sent = _sentTo.contains(name);

    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => _showDetail(name), // 탭하면 내역 보기
        leading: CircleAvatar(
          backgroundColor: isPayer
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: isPayer ? Colors.white : null,
          child: Text(name.characters.first),
        ),
        title: Row(
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (isPayer)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('결제자',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
          ],
        ),
        subtitle: Text(isPayer ? '받는 사람이에요' : '탭하면 내역이 보여요',
            style: const TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${won(amount)}원',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            if (!isPayer) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: '보내기',
                icon: Icon(
                  sent ? Icons.check_circle : Icons.send,
                  color: sent ? Colors.green : null,
                  size: 22,
                ),
                onPressed: () => _sendTo(name, amount),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAccountField() {
    return TextField(
      controller: _accountController,
      decoration: const InputDecoration(
        labelText: '입금 계좌 (메시지에 함께 보내져요)',
        hintText: '예: ○○은행 123-456-789 홍길동',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.account_balance),
      ),
      onChanged: (v) => AppPrefs.saveAccount(v.trim()), // 다음에도 자동 입력
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.popUntil(context, (r) => r.isFirst),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('처음으로'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _sendAll,
                icon: const Icon(Icons.send),
                label: const Text('전체 보내기',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
