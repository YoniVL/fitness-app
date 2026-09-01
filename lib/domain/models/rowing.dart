/// Summary of a rowing session, derived from the FTMS Rower Data stream.
///
/// The rowing UI/BLE link is a later iteratie; these models exist so the schema
/// is complete now (see plan). Absolute distance/pace from this trainer are
/// estimates — fine for trends, not lab precision.
class RowingSession {
  const RowingSession({
    required this.id,
    required this.sessionId,
    required this.totalDistanceM,
    required this.totalEnergyKcal,
    required this.avgStrokeRate,
    required this.avgPower,
    required this.durationSeconds,
    this.programDayId,
  });

  final int id;
  final int sessionId;
  final double totalDistanceM;
  final double totalEnergyKcal;
  final double avgStrokeRate;
  final double avgPower;
  final int durationSeconds;
  final int? programDayId;

  factory RowingSession.fromMap(Map<String, Object?> map) => RowingSession(
        id: map['id'] as int,
        sessionId: map['session_id'] as int,
        totalDistanceM: (map['total_distance_m'] as num?)?.toDouble() ?? 0,
        totalEnergyKcal: (map['total_energy_kcal'] as num?)?.toDouble() ?? 0,
        avgStrokeRate: (map['avg_stroke_rate'] as num?)?.toDouble() ?? 0,
        avgPower: (map['avg_power'] as num?)?.toDouble() ?? 0,
        durationSeconds: map['duration_seconds'] as int? ?? 0,
        programDayId: map['program_day_id'] as int?,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'session_id': sessionId,
        'total_distance_m': totalDistanceM,
        'total_energy_kcal': totalEnergyKcal,
        'avg_stroke_rate': avgStrokeRate,
        'avg_power': avgPower,
        'duration_seconds': durationSeconds,
        'program_day_id': programDayId,
      };
}

/// One time-stamped datapoint within a rowing session.
class RowingSample {
  const RowingSample({
    required this.id,
    required this.rowingSessionId,
    required this.tOffsetMs,
    this.strokeRate,
    this.strokeCount,
    this.distanceM,
    this.paceSec500m,
    this.powerW,
    this.energyKcal,
    this.heartRate,
  });

  final int id;
  final int rowingSessionId;
  final int tOffsetMs;
  final double? strokeRate;
  final int? strokeCount;
  final double? distanceM;
  final double? paceSec500m;
  final double? powerW;
  final double? energyKcal;
  final int? heartRate;

  factory RowingSample.fromMap(Map<String, Object?> map) => RowingSample(
        id: map['id'] as int,
        rowingSessionId: map['rowing_session_id'] as int,
        tOffsetMs: map['t_offset_ms'] as int,
        strokeRate: (map['stroke_rate'] as num?)?.toDouble(),
        strokeCount: map['stroke_count'] as int?,
        distanceM: (map['distance_m'] as num?)?.toDouble(),
        paceSec500m: (map['pace_sec_500m'] as num?)?.toDouble(),
        powerW: (map['power_w'] as num?)?.toDouble(),
        energyKcal: (map['energy_kcal'] as num?)?.toDouble(),
        heartRate: map['heart_rate'] as int?,
      );

  Map<String, Object?> toMap() => {
        if (id > 0) 'id': id,
        'rowing_session_id': rowingSessionId,
        't_offset_ms': tOffsetMs,
        'stroke_rate': strokeRate,
        'stroke_count': strokeCount,
        'distance_m': distanceM,
        'pace_sec_500m': paceSec500m,
        'power_w': powerW,
        'energy_kcal': energyKcal,
        'heart_rate': heartRate,
      };
}
