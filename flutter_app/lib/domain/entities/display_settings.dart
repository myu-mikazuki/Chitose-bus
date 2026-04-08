class DisplaySettings {
  const DisplaySettings({this.showLectureTags = true});

  final bool showLectureTags;

  DisplaySettings copyWith({bool? showLectureTags}) {
    return DisplaySettings(
      showLectureTags: showLectureTags ?? this.showLectureTags,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DisplaySettings && showLectureTags == other.showLectureTags;

  @override
  int get hashCode => showLectureTags.hashCode;
}
