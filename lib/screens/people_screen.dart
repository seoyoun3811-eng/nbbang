import 'package:flutter/material.dart';

import '../models/favorite_group.dart';
import '../services/favorites_storage.dart';
import 'input_method_screen.dart';

/// 정산하는 본인. 항상 목록에 포함되고 삭제할 수 없음
const String kMe = '나';

/// ① 누구랑 정산할지 고르는 화면
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  final _storage = FavoritesStorage();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  final List<String> _people = [kMe];
  List<FavoriteGroup> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _controller.addListener(() => setState(() {})); // [추가] 버튼 활성/비활성 갱신
  }

  Future<void> _loadGroups() async {
    final groups = await _storage.loadGroups();
    if (!mounted) return;
    setState(() => _groups = groups);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ───────────── 인원 추가 / 삭제 ─────────────

  void _addPerson() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    if (_people.contains(name)) {
      _showSnack('"$name"은(는) 이미 추가되어 있어요');
      return;
    }
    setState(() => _people.add(name));
    _controller.clear();
    _focusNode.requestFocus(); // 키보드 유지해서 연속 입력
    _scrollToBottom();
  }

  void _removePerson(String name) {
    setState(() => _people.remove(name));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ───────────── 그룹 ─────────────

  /// 이 사람이 하나 이상의 그룹에 들어가 있는지 (별 색칠 여부)
  bool _isInAnyGroup(String name) =>
      _groups.any((g) => g.members.contains(name));

  /// [그룹 생성]: 이름만 정해서 빈 그룹을 만듦
  Future<FavoriteGroup?> _createGroup() async {
    final nameController = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('그룹 생성'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          maxLength: 10,
          decoration: const InputDecoration(hintText: '예: 대학동기'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, nameController.text),
              child: const Text('만들기')),
        ],
      ),
    );

    final name = input?.trim() ?? '';
    if (name.isEmpty) return null;
    if (_groups.any((g) => g.name == name)) {
      _showSnack('"$name" 그룹이 이미 있어요');
      return null;
    }

    final group = FavoriteGroup(name: name, members: <String>[]);
    setState(() => _groups.add(group));
    await _storage.saveGroups(_groups);
    _showSnack('"$name" 그룹을 만들었어요. 아래에서 ☆를 눌러 멤버를 넣어 보세요');
    return group;
  }

  /// 그룹 칩을 탭하면 그 그룹 멤버를 한 번에 추가
  void _applyGroup(FavoriteGroup group) {
    if (group.members.isEmpty) {
      _showSnack('"${group.name}"에 멤버가 없어요. 아래에서 ☆를 눌러 추가해 주세요');
      return;
    }
    final toAdd = group.members.where((m) => !_people.contains(m)).toList();
    if (toAdd.isEmpty) {
      _showSnack('"${group.name}" 멤버가 이미 모두 추가되어 있어요');
      return;
    }
    setState(() => _people.addAll(toAdd));
    _showSnack('"${group.name}"에서 ${toAdd.length}명을 추가했어요');
    _scrollToBottom();
  }

  /// 그룹 칩을 길게 누르면 삭제
  Future<void> _deleteGroup(FavoriteGroup group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('"${group.name}" 그룹을 삭제할까요?'),
        content: group.members.isEmpty
            ? null
            : Text('멤버: ${group.members.join(', ')}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _groups.remove(group));
    await _storage.saveGroups(_groups);
  }

  /// ☆를 누르면: 이 사람을 넣을 그룹을 고르는 바텀시트
  Future<void> _openGroupPicker(String person) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          Future<void> toggle(FavoriteGroup g, bool add) async {
            setState(() {
              if (add) {
                g.members.add(person);
              } else {
                g.members.remove(person);
              }
            });
            setSheetState(() {});
            await _storage.saveGroups(_groups);
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('"$person"을(를) 넣을 그룹',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (_groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Text('아직 그룹이 없어요. 먼저 그룹을 만들어 주세요.',
                        style: TextStyle(color: Colors.grey)),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final g in _groups)
                        CheckboxListTile(
                          value: g.members.contains(person),
                          title: Text(g.name),
                          subtitle: Text(g.members.isEmpty
                              ? '멤버 없음'
                              : g.members.join(', ')),
                          onChanged: (v) => toggle(g, v ?? false),
                        ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('새 그룹 만들기'),
                  onTap: () async {
                    final g = await _createGroup();
                    if (g != null) await toggle(g, true); // 새 그룹에 바로 넣기
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  // ───────────── 기타 ─────────────

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _goNext() async {
    FocusScope.of(context).unfocus();
    // 같은 목록을 넘겨서, 다음 화면에서 사람을 추가해도 여기에 반영되게 함
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InputMethodScreen(people: _people),
      ),
    );
    if (mounted) setState(() {}); // 돌아오면 추가된 사람 표시
  }

  // ───────────── 화면 ─────────────

  @override
  Widget build(BuildContext context) {
    final canProceed = _people.length >= 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text('누구랑 정산할까요?',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGroupArea(),
            _buildInputRow(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                '함께하는 사람 ${_people.length}명',
                style: TextStyle(
                    color: Colors.grey.shade700, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: _buildPeopleList()), // 사람이 많으면 여기만 스크롤
            _buildNextButton(canProceed), // 항상 하단 고정
          ],
        ),
      ),
    );
  }

  /// 맨 위: 그룹이 없으면 안내 문구, 있으면 그룹 칩 (가로 스크롤)
  Widget _buildGroupArea() {
    if (_groups.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8E1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.star_border, color: Colors.amber),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '즐겨찾기 그룹이 없어요.\n자주 정산하는 그룹을 만들어 보세요!',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
            TextButton(
              onPressed: _createGroup,
              child: const Text('그룹 생성'),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          for (final g in _groups)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onLongPress: () => _deleteGroup(g), // 길게 누르면 삭제
                child: ActionChip(
                  avatar: const Icon(Icons.star, size: 18, color: Colors.amber),
                  label: Text('${g.name} (${g.members.length})'),
                  onPressed: () => _applyGroup(g),
                ),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('그룹 생성'),
            onPressed: _createGroup,
          ),
        ],
      ),
    );
  }

  /// 이름 입력창 + 추가 버튼
  Widget _buildInputRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLength: 10,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addPerson(), // 키보드 엔터로 추가
              decoration: InputDecoration(
                hintText: '이름 입력',
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _controller.text.trim().isEmpty ? null : _addPerson,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('추가'),
            ),
          ),
        ],
      ),
    );
  }

  /// 추가된 사람 목록
  Widget _buildPeopleList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _people.length,
      itemBuilder: (context, i) {
        final name = _people[i];
        final isMe = name == kMe;
        final inGroup = _isInAnyGroup(name);

        return Card(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isMe
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: isMe ? Colors.white : null,
              child: Text(name.characters.first),
            ),
            title: Text(name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: isMe
                ? const Text('본인', style: TextStyle(color: Colors.grey))
                : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '그룹에 넣기',
                  icon: Icon(inGroup ? Icons.star : Icons.star_border,
                      color: inGroup ? Colors.amber : Colors.grey),
                  onPressed: () => _openGroupPicker(name),
                ),
                IconButton(
                  tooltip: '삭제',
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => _removePerson(name),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 하단 고정 [다음] 버튼
  Widget _buildNextButton(bool enabled) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: enabled ? _goNext : null,
          style: FilledButton.styleFrom(
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text(
            enabled ? '다음' : '함께할 사람을 1명 이상 추가해 주세요',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}