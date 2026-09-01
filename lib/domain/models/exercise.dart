import '../taxonomy.dart';

/// An exercise in the library. Mostly used for strength training.
///
/// [mediaKey] is null for now — the schema and UI support a per-exercise
/// demonstration animation/illustration, but no media is bundled yet.
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.primaryMuscleGroupId,
    this.secondaryMuscleGroupIds = const [],
    this.equipmentTags = const [Equipment.bodyweight],
    this.pattern,
    this.mediaKey,
    this.isCustom = false,
    this.notes,
  });

  final int id;
  final String name;
  final int primaryMuscleGroupId;
  final List<int> secondaryMuscleGroupIds;

  /// Equipment required to perform this exercise (see [Equipment]).
  final List<String> equipmentTags;
  final MovementPattern? pattern;
  final String? mediaKey;
  final bool isCustom;
  final String? notes;

  /// True when the user's [owned] equipment covers everything this exercise
  /// needs. `bodyweight` is always available.
  bool canPerformWith(Set<String> owned) => equipmentTags
      .where((t) => t != Equipment.bodyweight)
      .every(owned.contains);

  factory Exercise.fromMap(Map<String, Object?> map) => Exercise(
        id: map['id'] as int,
        name: map['name'] as String,
        primaryMuscleGroupId: map['primary_muscle_group_id'] as int,
        secondaryMuscleGroupIds:
            _parseCsvInts(map['secondary_muscle_groups'] as String?),
        equipmentTags: _parseEquipment(map['equipment'] as String?),
        pattern: MovementPattern.fromName(map['pattern'] as String?),
        mediaKey: map['media_key'] as String?,
        isCustom: (map['is_custom'] as int? ?? 0) == 1,
        notes: map['notes'] as String?,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'name': name,
        'primary_muscle_group_id': primaryMuscleGroupId,
        'secondary_muscle_groups': secondaryMuscleGroupIds.join(','),
        'equipment': equipmentTags.join(','),
        'pattern': pattern?.name,
        'media_key': mediaKey,
        'is_custom': isCustom ? 1 : 0,
        'notes': notes,
      };

  static List<String> _parseEquipment(String? csv) {
    final tags = Equipment.parse(csv);
    return tags.isEmpty ? const [Equipment.bodyweight] : tags;
  }

  static List<int> _parseCsvInts(String? csv) {
    if (csv == null || csv.trim().isEmpty) return const [];
    return csv
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList(growable: false);
  }
}
