/// Vocabulary for generated rowing plans: the training goal, the session
/// archetypes a plan is built from, and the technique drills woven into them.
library;

/// What the rower is training for. Drives the weekly session mix and the
/// intensity distribution in [RowingPlanGenerator].
enum RowingGoal {
  vetverlies,
  uithouding,
  kracht,
  techniek,
  algemeen;

  String get label => switch (this) {
        RowingGoal.vetverlies => 'Vetverlies',
        RowingGoal.uithouding => 'Uithouding',
        RowingGoal.kracht => 'Kracht & vermogen',
        RowingGoal.techniek => 'Techniek',
        RowingGoal.algemeen => 'Algemene conditie',
      };

  String get description => switch (this) {
        RowingGoal.vetverlies =>
          'Veel rustig duurwerk met een wekelijkse intervalsessie.',
        RowingGoal.uithouding =>
          'Aerobe basis: lange rustige stukken en drempeltraining.',
        RowingGoal.kracht =>
          'Korte harde intervallen en lage-slag krachthalen, met veel rust.',
        RowingGoal.techniek =>
          'Oefeningen (alleen armen/benen, pauzehalen) op een lage slag.',
        RowingGoal.algemeen => 'Een gebalanceerde mix van alles.',
      };

  static RowingGoal? fromName(String? value) {
    for (final g in values) {
      if (g.name == value) return g;
    }
    return null;
  }
}

/// One session archetype. The generator turns each into a list of segments.
enum RowSessionType {
  endurance,
  drempel,
  intervalKort,
  intervalLang,
  piramide,
  krachtStroken,
  techniek,
  herstel;

  String get label => switch (this) {
        RowSessionType.endurance => 'Endurance',
        RowSessionType.drempel => 'Drempel',
        RowSessionType.intervalKort => 'Korte intervallen',
        RowSessionType.intervalLang => 'Lange intervallen',
        RowSessionType.piramide => 'Piramide',
        RowSessionType.krachtStroken => 'Krachthalen',
        RowSessionType.techniek => 'Techniek',
        RowSessionType.herstel => 'Herstel',
      };
}

/// A technique drill used inside a segment. [key] is stored in
/// `program_row_segments.drill_key`; [label] shows in the UI.
enum RowDrill {
  armenOnly('armen', 'Alleen armen',
      'Benen en romp stil — haal alleen met de armen.'),
  benenOnly('benen', 'Alleen benen',
      'Armen gestrekt en romp vast — duw alleen met de benen.'),
  armenRomp('armen_romp', 'Armen + romp',
      'Geen beenwerk; zwaai vanuit de heup en trek met de armen.'),
  pauzeHaal('pauze', 'Pauzehaal',
      'Pauzeer twee tellen met de handen net voorbij de knieën.'),
  opbouwHaal('opbouw', 'Opbouwhaal',
      'Benen, dan romp, dan armen — apart, daarna vloeiend samen.'),
  omgekeerdeRatio('omg_ratio', 'Omgekeerde ratio',
      'Haal even lang als de recover; nadruk op controle.'),
  krachtHaal('kracht', 'Krachthaal',
      'Lage slag (18–20), maximale druk per haal.');

  const RowDrill(this.key, this.label, this.tip);

  final String key;
  final String label;
  final String tip;

  static RowDrill? fromKey(String? key) {
    if (key == null) return null;
    for (final d in values) {
      if (d.key == key) return d;
    }
    return null;
  }
}
