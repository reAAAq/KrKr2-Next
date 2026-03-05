/// A single scraping result candidate (e.g. from VNDB).
/// Used for search list display and cover download.
class GameMetadataCandidate {
  const GameMetadataCandidate({
    required this.title,
    required this.coverImageUrl,
    this.thumbnailUrl,
    this.developer,
    this.sourceId,
    this.sourceLabel,
  });

  final String title;
  final String coverImageUrl;
  /// Optional thumbnail URL. Used as fallback when full cover fails (e.g. 403 for R18).
  final String? thumbnailUrl;
  /// Developer / producer name (e.g. from VNDB).
  final String? developer;
  final String? sourceId;
  final String? sourceLabel;
}
