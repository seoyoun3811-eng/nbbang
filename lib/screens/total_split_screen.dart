import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/settle_item.dart';
import '../utils/format.dart';
import 'result_screen.dart';

/// 총액만 입력해서 바로 N빵 하는 화면
class TotalSplitScreen extends StatefulWidget {
  final List<String> people;

  const TotalSplitScreen({super.key, required this.people});

  @override
  State<TotalSplitScreen> createState() => _TotalSplitScreenState();
}

class _TotalSplitScreenState extends State<TotalSplitScreen> {
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();

  int get _amount => int.tryParse(_amountController.text) ?? 0;

  @override
  void dispose() {
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _goResult() {
    final memo = _memoController.text.trim();
    final item = SettleItem(
      name: memo.isEmpty ? '전체' : memo,
      price: _amount,
      qty: 1,
      assignedAll: true,
    );
    FocusScope.of(context).unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(people: widget.people, items: [item]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.people.length;
    final per = _amount > 0 ? (_amount / count).ceil() : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('총액만 나누기',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.people.join(', ')} ($count명)',
                  style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 20),
              TextField(
                controller: _amountController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  labelText: '총 금액',
                  suffixText: '원',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _memoController,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '내용 (선택)',
                  hintText: '예: 저녁 회식',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              if (_amount > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '1인당 약 ${won(per)}원',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: _amount > 0 ? _goResult : null,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('결과 보기',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
