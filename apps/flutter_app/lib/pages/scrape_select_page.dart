import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/game_info.dart';
import '../models/game_metadata_candidate.dart';
import '../services/cover_downloader.dart';
import '../services/game_manager.dart';
import '../services/game_metadata_scraper.dart';

/// Step 2 of scrape flow: show search results, let user select one, then apply.
class ScrapeSelectPage extends StatefulWidget {
  const ScrapeSelectPage({
    super.key,
    required this.candidates,
    required this.game,
    required this.gameManager,
    required this.scraper,
  });

  final List<GameMetadataCandidate> candidates;
  final GameInfo game;
  final GameManager gameManager;
  final GameMetadataScraper scraper;

  @override
  State<ScrapeSelectPage> createState() => _ScrapeSelectPageState();
}

class _ScrapeSelectPageState extends State<ScrapeSelectPage> {
  GameMetadataCandidate? _selected;
  bool _applying = false;

  List<GameMetadataCandidate> get candidates => widget.candidates;
  GameInfo get game => widget.game;
  GameManager get gameManager => widget.gameManager;
  GameMetadataScraper get scraper => widget.scraper;

  Widget _buildCandidateLeading(GameMetadataCandidate c) {
    // 列表默认用缩略图，加载快且避免 R18 主图 403
    final displayUrl = (c.thumbnailUrl != null && c.thumbnailUrl!.isNotEmpty)
        ? c.thumbnailUrl!
        : c.coverImageUrl;
    if (displayUrl.isEmpty) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Icon(Icons.image_not_supported_outlined),
      );
    }
    return SizedBox(
      width: 48,
      height: 48,
      child: Image.network(
        displayUrl,
        fit: BoxFit.cover,
        headers: CoverDownloader.imageRequestHeaders,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_outlined,
          size: 48,
        ),
        loadingBuilder: (_, child, progress) =>
            progress == null
                ? child
                : const SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
      ),
    );
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context)!;
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.scrapeMetadataSelectOne)),
      );
      return;
    }
    setState(() => _applying = true);

    final candidate = _selected!;
    final localPath = await scraper.downloadCover(candidate);
    await gameManager.renameGame(game.path, candidate.title);
    if (localPath != null) {
      await gameManager.setCoverImage(game.path, localPath);
    }
    if (candidate.developer != null && candidate.developer!.isNotEmpty) {
      await gameManager.setDeveloper(game.path, candidate.developer);
    }

    if (!mounted) return;
    setState(() => _applying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localPath != null
            ? l10n.scrapeMetadataSuccess
            : l10n.scrapeMetadataCoverFailed),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.scrapeMetadataSelectTitle),
        leading: _applying
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(false),
              ),
      ),
      body: candidates.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.scrapeMetadataNoResults,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(l10n.back),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final c = candidates[index];
                      final isSelected = _selected == c;
                      return ListTile(
                        leading: _buildCandidateLeading(c),
                        title: Text(c.title),
                        subtitle: c.sourceLabel != null
                            ? Text(
                                c.sourceLabel!,
                                style: theme.textTheme.bodySmall,
                              )
                            : null,
                        selected: isSelected,
                                        onTap: () => setState(() => _selected = c),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: _applying
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: Text(l10n.back),
                        ),
                        const SizedBox(width: 16),
                        FilledButton(
                          onPressed: _applying ? null : _confirm,
                          child: _applying
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.scrapeMetadataConfirm),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
