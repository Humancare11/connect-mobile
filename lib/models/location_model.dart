class Country {
  const Country({required this.name, this.iso2 = '', this.iso3 = ''});

  final String name;
  final String iso2;
  final String iso3;

  factory Country.fromJson(Map<String, dynamic> json) {
    return Country(
      name: json['name']?.toString() ?? '',
      iso2: json['iso2']?.toString() ?? '',
      iso3: json['iso3']?.toString() ?? '',
    );
  }
}

class StateItem {
  const StateItem({required this.name, this.stateCode = ''});

  final String name;
  final String stateCode;

  factory StateItem.fromJson(Map<String, dynamic> json) {
    return StateItem(
      name: json['name']?.toString() ?? '',
      stateCode: json['state_code']?.toString() ?? '',
    );
  }
}
