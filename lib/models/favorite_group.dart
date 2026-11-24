/// 즐겨찾기 그룹 (예: "대학동기" = [철수, 영희, 민수])
class FavoriteGroup {
  final String name;
  final List<String> members;

  const FavoriteGroup({required this.name, required this.members});

  Map<String, dynamic> toJson() => {'name': name, 'members': members};

  factory FavoriteGroup.fromJson(Map<String, dynamic> json) => FavoriteGroup(
        name: json['name'] as String,
        members: List<String>.from(json['members'] as List),
      );
}
