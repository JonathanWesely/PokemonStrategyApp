/// Held item data from the items pack. Pure Dart.
library;

class ItemData {
  final String id;
  final String name;
  final String desc;

  const ItemData({required this.id, required this.name, this.desc = ''});

  factory ItemData.fromJson(Map<String, dynamic> json) => ItemData(
        id: json['id'] as String,
        name: json['name'] as String,
        desc: (json['desc'] as String?) ?? '',
      );

  bool get isMegaStone => desc.startsWith('Mega Stone');
}
