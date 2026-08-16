/// Ability data from the abilities pack. Pure Dart.
library;

class AbilityData {
  final String id;
  final String name;
  final String desc;

  const AbilityData({required this.id, required this.name, this.desc = ''});

  factory AbilityData.fromJson(Map<String, dynamic> json) => AbilityData(
        id: json['id'] as String,
        name: json['name'] as String,
        desc: (json['desc'] as String?) ?? '',
      );
}
