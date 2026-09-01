/// A muscle group used to categorise exercises (e.g. "Borst", "Rug").
///
/// [iconKey] is a stable identifier that the UI maps to an [IconData]; the
/// exercise-demo media is not bundled yet, so a muscle-group icon is shown as
/// placeholder (see plan iteratie 1).
class MuscleGroup {
  const MuscleGroup({
    required this.id,
    required this.name,
    required this.iconKey,
  });

  final int id;
  final String name;
  final String iconKey;

  factory MuscleGroup.fromMap(Map<String, Object?> map) => MuscleGroup(
        id: map['id'] as int,
        name: map['name'] as String,
        iconKey: map['icon_key'] as String,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'icon_key': iconKey,
      };
}
