/// Metres in one foot (exact, by definition of the international foot).
const double metresPerFoot = 0.3048;

/// [feet] in metres.
double feetToMetres(double feet) => feet * metresPerFoot;

/// [metres] in feet.
double metresToFeet(double metres) => metres / metresPerFoot;
