import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_group.dart';

/// 즐겨찾기 그룹을 폰에 저장하고 불러오는 클래스
class FavoritesStorage {
  static const _groupsKey = 'favorite_groups';

  Future<List<FavoriteGroup>> loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_groupsKey) ?? [];
    return raw
        .map((s) => FavoriteGroup.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveGroups(List<FavoriteGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _groupsKey,
      groups.map((g) => jsonEncode(g.toJson())).toList(),
    );
  }
}
