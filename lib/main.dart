import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:html_character_entities/html_character_entities.dart';
import 'package:cached_network_image/cached_network_image.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://kusvloreaakrvwsdhqhj.supabase.co',
    anonKey: 'sb_publishable_eHuAUb_bxcu8mi5ZL8u9XA_k4iQjeCW',
  );

  runApp(const TruBriefApp());
}

class TruBriefApp extends StatelessWidget {
  const TruBriefApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TruBrief',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        cardColor: const Color(0xFF1C1C1E),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black, elevation: 0),
      ),
      home: const ArticlesScreen(),
    );
  }
}

class ArticlesScreen extends StatefulWidget {
  const ArticlesScreen({super.key});

  @override
  State<ArticlesScreen> createState() => _ArticlesScreenState();
}

class _ArticlesScreenState extends State<ArticlesScreen> {
  // Bypasses null auth for development/admin persistence
  // Uses a valid UUID string format for database compatibility
  String? get _effectiveUserId => Supabase.instance.client.auth.currentUser?.id ?? '00000000-0000-4000-a000-000000000000';

  List<dynamic> _articles = [];
  List<dynamic> _allSources = [];
  bool _loading = true;
  bool _isPremium = false;
  bool _isTrialActive = false;
  bool _isIngesting = false;
  bool _isDisposed = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _savedArticleIds = {};
  
  List<String> _categories = [];
  List<String> _virtualCategories = [];
  List<String> _selectedCategories = [];
  List<String> _selectedSources = [];
  String _selectedCategory = 'Tru Brief';
  String? _zipCode;
  String? _locationType; // 'exact', 'zip', 'none'
  String? _city;
  String? _state;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _fetchSavedArticles();
    _ensureDefaultSourcesExist();
    _fetchArticles();
    _fetchNewArticlesFromSources();
    _archiveOldArticles();
  }

  Future<void> _fetchSavedArticles() async {
    final userId = _effectiveUserId;
    if (userId == null) return;
    try {
      final saved = await Supabase.instance.client
          .from('trl_saved_articles')
          .select('article_id')
          .eq('user_id', userId);
      if (mounted) {
        setState(() {
          _savedArticleIds.clear();
          for (var item in saved) {
            _savedArticleIds.add(item['article_id'].toString());
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching saved: $e');
    }
  }

  Future<void> _toggleSaveArticle(String articleId) async {
    final userId = _effectiveUserId;
    if (userId == null) return;
    
    final isSaved = _savedArticleIds.contains(articleId);
    try {
      if (isSaved) {
        await Supabase.instance.client
            .from('trl_saved_articles')
            .delete()
            .eq('user_id', userId)
            .eq('article_id', articleId);
        if (mounted) setState(() => _savedArticleIds.remove(articleId));
      } else {
        await Supabase.instance.client
            .from('trl_saved_articles')
            .insert({'user_id': userId, 'article_id': articleId});
        if (mounted) setState(() => _savedArticleIds.add(articleId));
      }
    } catch (e) {
      debugPrint('Error toggling save: $e');
    }
  }

  Future<void> _archiveOldArticles() async {
    try {
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      
      // 1. Find articles older than 7 days
      final oldArticles = await Supabase.instance.client
          .from('trl_articles')
          .select()
          .lt('created_at', sevenDaysAgo)
          .limit(100); // Process in batches to avoid timeouts

      if (oldArticles.isEmpty) return;

      // 2. Insert into archive
      await Supabase.instance.client.from('trl_articles_archive').insert(oldArticles);

      // 3. Delete from active
      final List<String> oldIds = oldArticles.map((a) => a['id'].toString()).toList();
      await Supabase.instance.client.from('trl_articles').delete().inFilter('id', oldIds);
      
      debugPrint('Archived ${oldIds.length} old articles');

      // --- SMART PURGE: Delete 30d+ archive unless saved ---
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();
      
      // 1. Get all saved article IDs to protect them
      final savedArticles = await Supabase.instance.client
          .from('trl_saved_articles')
          .select('article_id');
      final List<String> protectedIds = savedArticles.map((s) => s['article_id'].toString()).toList();

      // 2. Delete anything older than 30 days that is NOT in the protected list
      var purgeQuery = Supabase.instance.client
          .from('trl_articles_archive')
          .delete()
          .lt('created_at', thirtyDaysAgo);

      if (protectedIds.isNotEmpty) {
        purgeQuery = purgeQuery.not('id', 'in', '(${protectedIds.join(",")})');
      }
      
      await purgeQuery;
      debugPrint('Smart Purge completed.');
    } catch (e) {
      debugPrint('Archive error: $e');
    }
  }

  Future<void> _ensureDefaultSourcesExist() async {
    // Sources are now seeded via SQL migrations. 
    // This method remains as a placeholder or for dynamic runtime checks.
    try {
      final List<dynamic> dbSources = await Supabase.instance.client.from('trl_sources').select();
      debugPrint('Found ${dbSources.length} sources in database.');
    } catch (e) {
      debugPrint('Error checking sources: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    final userId = _effectiveUserId;
    if (userId == null) return;

    try {
      // 1. Fetch Categories from DB (Dynamic)
      final catData = await Supabase.instance.client
          .from('trl_categories')
          .select()
          .order('display_order', ascending: true);
      
      if (catData != null && catData.isNotEmpty && mounted) {
        setState(() {
          _virtualCategories = List<String>.from(catData.where((c) => c['is_virtual'] == true && c['name'] != 'Weekly Top').map((c) => c['name']));
          
          // Default all categories from DB first
          final List<String> dbCats = List<String>.from(catData.map((c) => c['name'])).where((c) => c != 'Weekly Top').toList();
          _categories = dbCats;
          debugPrint('Fetched ${_categories.length} categories from DB');
        });
      } else {
        debugPrint('Warning: No categories found in DB or empty response');
      }

      // 2. Fetch all sources (for paywall detection) — non-fatal if it fails
      try {
        final sourcesData = await Supabase.instance.client
            .from('trl_sources')
            .select('id, name, category, requires_subscription');
        if (mounted) {
          setState(() => _allSources = List<dynamic>.from(sourcesData));
        }
      } catch (e) {
        debugPrint('Sources fetch error: $e');
      }

      // 3. Fetch User Preferences
      final prefs = await Supabase.instance.client
          .from('trl_user_preferences')
          .select()
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      
      if (prefs != null && mounted) {
        setState(() {
          _locationType = prefs['location_type'] ?? 'none';
          _zipCode = prefs['zip_code'];
          _city = prefs['city'];
          _state = prefs['state'];
          _selectedSources = List<String>.from(prefs['selected_sources'] ?? []);
          
          final List<String> savedOrder = List<String>.from(prefs['selected_categories'] ?? []);
          
          // Reconstruct _categories based on saved order, then add any NEW categories from DB at the end
          final List<String> orderedCats = [];
          for (var catName in savedOrder) {
            if (_categories.contains(catName)) {
              orderedCats.add(catName);
            }
          }
          
          // Add remaining categories from DB that weren't in the saved order
          for (var dbCat in _categories) {
            if (!orderedCats.contains(dbCat)) {
              orderedCats.add(dbCat);
            }
          }

          _categories = orderedCats.where((c) => c != 'Weekly Top').toList();
          
          // Ensure Tru Brief is ALWAYS first
          if (_categories.contains('Tru Brief')) {
            _categories.remove('Tru Brief');
            _categories.insert(0, 'Tru Brief');
          }

          _selectedCategories = List<String>.from(savedOrder).where((c) => c != 'Weekly Top').toList();
          
          if (_selectedCategories.isEmpty) {
            _selectedCategories = ['Tru Brief', 'Local Brief', 'National Brief', 'World Brief', 'Food Brief'];
          }
        });
      }

      // 3. Fetch Subscription
      final sub = await Supabase.instance.client
          .from('trl_subscriptions')
          .select()
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      
      if (sub != null && mounted) {
        setState(() {
          _isPremium = sub['status'] == 'active';
          // Check if trial is within 7 days
          if (sub['trial_started_at'] != null) {
            final trialStart = DateTime.parse(sub['trial_started_at']);
            _isTrialActive = DateTime.now().difference(trialStart).inDays < 7;
          }
        });
      }

      _fetchArticles(); // Re-fetch now that we know the user's selected categories
    } catch (e) {
      debugPrint('User data error: $e');
    }
  }

  Future<List<dynamic>> _fetchGoogleNewsLocal() async {
    String locationQuery;
    if (_city != null && _city!.isNotEmpty && _state != null && _state!.isNotEmpty) {
      locationQuery = Uri.encodeComponent('"$_city" "$_state"');
    } else if (_zipCode != null && _zipCode!.isNotEmpty) {
      locationQuery = Uri.encodeComponent('"$_zipCode"');
    } else {
      return [];
    }

    final url = 'https://news.google.com/rss/search?q=when:48h+$locationQuery+local+news&hl=en-US&gl=US&ceid=US:en';
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final xml = res.body;
      final items = RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml);
      final List<dynamic> articles = [];
      for (var match in items) {
        final item = match.group(1)!;
        final rawTitle = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(item)?.group(1) ?? '';
        final link = RegExp(r'<link>(.*?)</link>', dotAll: true).firstMatch(item)?.group(1)?.trim() ?? '';
        final pubDateStr = RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true).firstMatch(item)?.group(1)?.trim();
        final sourceMatch = RegExp(r'<source[^>]*>(.*?)</source>', dotAll: true).firstMatch(item);
        final sourceName = sourceMatch?.group(1)?.trim() ?? 'Local News';
        // Don't use Google News RSS thumbnails — they're Google's placeholder logo.
        // _repairMissingImages will scrape the real article OG image instead.
        const imageUrl = null;

        final title = _cleanXmlContent(rawTitle);
        final titleParts = title.split(' - ');
        final cleanTitle = titleParts.length > 1 ? titleParts.sublist(0, titleParts.length - 1).join(' - ') : title;

        if (link.isEmpty || cleanTitle.isEmpty) continue;

        articles.add({
          'id': link.hashCode.toString(),
          'title': cleanTitle,
          'original_url': link,
          'image_url': imageUrl,
          'summary_brief': null,
          'category': 'Local Brief',
          'source_name': sourceName,
          'source_id': null,
          'created_at': pubDateStr != null ? (DateTime.tryParse(pubDateStr) ?? DateTime.now()).toIso8601String() : DateTime.now().toIso8601String(),
        });
      }
      return articles;
    } catch (e) {
      debugPrint('Google News local fetch error: $e');
      return [];
    }
  }

  Future<void> _fetchArticles() async {
    try {
      if (mounted) setState(() => _loading = true);

      var query = Supabase.instance.client.from('trl_articles').select();

      final search = _searchController.text.trim();
      if (search.isNotEmpty) {
        query = query.ilike('title', '%$search%');
      } else {
        if (_selectedCategory == 'Local Brief' && _locationType != 'none') {
          final localArticles = _deduplicateByTopic(_filterGeoRestricted(await _fetchGoogleNewsLocal()));
          if (mounted) {
            setState(() {
              _articles = localArticles;
              _loading = false;
            });
            _repairMissingImages();
          }
          return;
        } else if (_selectedCategory == 'Tru Brief') {
          // TRU BRIEF: Fetch articles from ALL selected sources
          if (_selectedSources.isNotEmpty) {
            query = query.inFilter('source_id', _selectedSources);
          }
        } else {
          final shortCat = _selectedCategory.replaceAll(' Brief', '').replaceAll(' News', '').trim();
          // Filter by multiple name variations to ensure we catch all articles
          query = query.or('category.eq."$_selectedCategory",category.eq."$shortCat",category.eq."$shortCat Brief",category.eq."$shortCat News"');
          
          // Only show sources the user has selected
          if (_selectedSources.isNotEmpty) {
            query = query.inFilter('source_id', _selectedSources);
          }
        }
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(150)
          .timeout(const Duration(seconds: 10));

      final interleaved = _deduplicateByTopic(_filterGeoRestricted(_interleaveBySource(List<dynamic>.from(response))));

      if (mounted) {
        setState(() {
          _articles = interleaved;
        });
        _repairMissingImages();
      }
    } catch (e) {
      debugPrint('Fetch error: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<dynamic> _filterGeoRestricted(List<dynamic> articles) {
    final countryCode = WidgetsBinding.instance.platformDispatcher.locale.countryCode?.toUpperCase() ?? '';
    return articles.where((article) {
      final url = (article['original_url'] ?? '').toString().toLowerCase();
      if (countryCode != 'GB' && url.contains('/iplayer/')) return false;
      if (countryCode != 'US' && url.contains('//www.hulu.com')) return false;
      if (countryCode != 'US' && url.contains('//www.espn.com/watch')) return false;
      return true;
    }).toList();
  }

  static const _stopWords = {
    'a','an','the','and','or','but','in','on','at','to','for','of','with',
    'is','are','was','were','be','been','being','have','has','had','do','does',
    'did','will','would','could','should','may','might','can','it','its',
    'this','that','these','those','by','from','as','up','about','into',
    'after','before','during','over','under','not','no','new','two','one',
    'man','woman','men','women','says','said','than','more','what',
    'how','who','when','where','why','he','she','they','we','his','her',
    'their','our','us','him','them','my','your','i','you','all','also','just',
  };

  Set<String> _titleKeywords(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !_stopWords.contains(w))
        .toSet();
  }

  List<dynamic> _deduplicateByTopic(List<dynamic> articles, {double threshold = 0.25}) {
    final List<Map<String, dynamic>> result = [];
    final List<Set<String>> seenKeywordSets = [];

    for (final article in articles) {
      final title = (article['title'] ?? '').toString();
      final keywords = _titleKeywords(title);
      if (keywords.isEmpty) {
        result.add(Map<String, dynamic>.from(article as Map));
        continue;
      }
      bool found = false;
      for (int i = 0; i < seenKeywordSets.length; i++) {
        final intersection = keywords.intersection(seenKeywordSets[i]).length;
        final union = keywords.union(seenKeywordSets[i]).length;
        if (union > 0 && intersection >= 2 && intersection / union >= threshold) {
          final related = List<dynamic>.from(result[i]['_related_articles'] as List? ?? []);
          related.add(article);
          result[i] = {...result[i], '_related_articles': related};
          found = true;
          break;
        }
      }
      if (!found) {
        result.add({...Map<String, dynamic>.from(article as Map), '_related_articles': <dynamic>[]});
        seenKeywordSets.add(keywords);
      }
    }
    return result;
  }

  List<dynamic> _interleaveBySource(List<dynamic> articles) {
    final Map<String, List<dynamic>> bySource = {};
    for (final article in articles) {
      final key = article['source_id']?.toString() ?? article['source_name']?.toString() ?? 'unknown';
      bySource.putIfAbsent(key, () => []).add(article);
    }

    final List<List<dynamic>> buckets = bySource.values.toList();
    final List<dynamic> result = [];
    int i = 0;
    while (result.length < 50) {
      bool anyLeft = false;
      for (final bucket in buckets) {
        if (i < bucket.length) {
          result.add(bucket[i]);
          anyLeft = true;
          if (result.length == 50) break;
        }
      }
      if (!anyLeft) break;
      i++;
    }
    return result;
  }

  Future<void> _repairMissingImages() async {
    final limit = _articles.length < 30 ? _articles.length : 30;
    for (var i = 0; i < limit; i++) {
      final article = _articles[i];
      if (article['image_url'] == null || article['image_url'].toString().isEmpty) {
        final url = _cleanXmlContent(article['original_url']);
        if (url.isEmpty) continue;

        try {
          // For Google News redirect URLs, follow redirects to get the real article URL
          String resolvedUrl = url;
          if (Uri.tryParse(url)?.host.contains('google.com') == true) {
            try {
              final redirect = await http.get(
                Uri.parse(url),
                headers: {'User-Agent': 'Mozilla/5.0 (compatible; Googlebot/2.1)'},
              ).timeout(const Duration(seconds: 5));
              final finalUrl = redirect.request?.url.toString() ?? '';
              if (finalUrl.isNotEmpty && !(Uri.tryParse(finalUrl)?.host.contains('google.com') ?? true)) {
                resolvedUrl = finalUrl;
              } else {
                continue;
              }
            } catch (_) {
              continue;
            }
          }

          final imageUrl = await _scrapeImageUrl(resolvedUrl);
          
          if (imageUrl != null && imageUrl.isNotEmpty) {
            final isInMemoryOnly = article['source_id'] == null;
            if (!isInMemoryOnly) {
              await Supabase.instance.client
                  .from('trl_articles')
                  .update({'image_url': imageUrl})
                  .eq('id', article['id']);
            }
            _articles[i] = Map<String, dynamic>.from(article)..['image_url'] = imageUrl;
            if (mounted) setState(() {});
          }
        } catch (e) {
          debugPrint('Repair error for ${article['id']}: $e');
        }
      }
    }
  }

  /// PROACTIVE INGESTION: Fetches new articles directly from the app
  /// This ensures the app stays updated even without a backend worker.
  Future<void> _fetchNewArticlesFromSources() async {
    if (_isIngesting || _isDisposed) return;
    _isIngesting = true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fetching new Briefs...'), duration: Duration(seconds: 2)),
      );
    }
    try {
      final List<dynamic> dbSources = await Supabase.instance.client.from('trl_sources').select();
      final List<Map<String, dynamic>> sources = List<Map<String, dynamic>>.from(dbSources);

      // FORCE FIX: Sweep 200 "Tech" articles and correct them to their source's category
      final techArticles = await Supabase.instance.client
          .from('trl_articles')
          .select('id, source_id')
          .eq('category', 'Tech')
          .limit(200);
      
      for (var art in techArticles) {
        final parentSource = sources.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['id'] == art['source_id'], 
          orElse: () => null
        );
        if (parentSource != null) {
          await Supabase.instance.client
              .from('trl_articles')
              .update({'category': parentSource['category']})
              .eq('id', art['id']);
        }
      }

      int newArticlesCount = 0;
      for (var source in sources) {
        if (_isDisposed) break;
        if (source['requires_subscription'] == true) continue;
        final res = await http.get(Uri.parse(source['url'])).timeout(const Duration(seconds: 10));
        final xml = res.body;

        final items = RegExp(r'<item>(.*?)</item>', dotAll: true).allMatches(xml);
        for (var match in items) {
          final item = match.group(1)!;
          final title = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(item)?.group(1);
          final link = RegExp(r'<link>(.*?)</link>', dotAll: true).firstMatch(item)?.group(1);
          final description = RegExp(r'<description>(.*?)</description>', dotAll: true).firstMatch(item)?.group(1);
          final pubDateStr = RegExp(r'<pubDate>(.*?)</pubDate>', dotAll: true).firstMatch(item)?.group(1);
          
          if (title == null || link == null) continue;

          final originalUrl = _cleanXmlContent(link);
          final existing = await Supabase.instance.client
              .from('trl_articles')
              .select()
              .eq('original_url', originalUrl)
              .maybeSingle();

          if (existing == null) {
            String? imageUrl = _extractRssImage(item) ?? await _scrapeImageUrl(originalUrl);
            DateTime pubDate;
            try {
              // Note: This is a simple RSS date parse. Real RSS may need intl package.
              pubDate = pubDateStr != null ? DateTime.tryParse(pubDateStr) ?? DateTime.now() : DateTime.now();
            } catch (_) {
              pubDate = DateTime.now();
            }

            await Supabase.instance.client.from('trl_articles').insert({
              'title': _cleanXmlContent(title),
              'original_url': originalUrl,
              'image_url': imageUrl,
              'summary_brief': _cleanXmlContent(description),
              'category': source['category'],
              'source_name': source['name'],
              'source_id': source['id'],
              'created_at': pubDate.toIso8601String(),
            });
            newArticlesCount++;
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $newArticlesCount new Briefs'), backgroundColor: Colors.green),
        );
      }
      // Re-fetch local list once background ingestion completes
      if (mounted && !_isDisposed) _fetchArticles(); 
    } catch (e) {
      debugPrint('Background ingestion failed: $e');
    } finally {
      _isIngesting = false;
    }
  }

  String? _extractRssImage(String itemXml) {
    // 1. media:content url
    final mediaContent = RegExp(r'<media:content[^>]+url="([^"]+)"', caseSensitive: false).firstMatch(itemXml);
    if (mediaContent != null) return _cleanXmlContent(mediaContent.group(1));

    // 2. media:thumbnail url
    final mediaThumbnail = RegExp(r'<media:thumbnail[^>]+url="([^"]+)"', caseSensitive: false).firstMatch(itemXml);
    if (mediaThumbnail != null) return _cleanXmlContent(mediaThumbnail.group(1));

    // 3. enclosure (image type)
    final enclosure = RegExp(r'<enclosure[^>]+url="([^"]+)"[^>]+type="image/[^"]*"', caseSensitive: false).firstMatch(itemXml) ??
                      RegExp(r'<enclosure[^>]+type="image/[^"]*"[^>]+url="([^"]+)"', caseSensitive: false).firstMatch(itemXml);
    if (enclosure != null) return _cleanXmlContent(enclosure.group(1));

    // 4. <img src="..."> or src='...' inside description/content
    final imgTag = RegExp(r'''<img[^>]+src=["'](https?://[^"']+)["']''', caseSensitive: false).firstMatch(itemXml);
    if (imgTag != null) return _cleanXmlContent(imgTag.group(1));

    return null;
  }

  Future<String?> _scrapeImageUrl(String? rawUrl) async {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final url = _cleanXmlContent(rawUrl);
    // Skip Google-owned pages — they return the Google News logo, not article images
    if (Uri.tryParse(url)?.host.contains('google.com') == true) return null;
    try {
      final res = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 5));
      
      final html = res.body;
      
      // 1. OG Image
      final ogMatch = RegExp(r'<meta[^>]*property="og:image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html) ??
                      RegExp(r'<meta[^>]*content="([^"]*)"[^>]*property="og:image"', caseSensitive: false).firstMatch(html);
      if (ogMatch != null) return _cleanXmlContent(ogMatch.group(1));

      // 2. Twitter Image
      final twMatch = RegExp(r'<meta[^>]*name="twitter:image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html) ??
                      RegExp(r'<meta[^>]*content="([^"]*)"[^>]*name="twitter:image"', caseSensitive: false).firstMatch(html);
      if (twMatch != null) return _cleanXmlContent(twMatch.group(1));

      // 3. Schema.org itemprop
      final itemPropMatch = RegExp(r'<meta[^>]*itemprop="image"[^>]*content="([^"]*)"', caseSensitive: false).firstMatch(html);
      if (itemPropMatch != null) return _cleanXmlContent(itemPropMatch.group(1));

      // 4. JSON-LD structured data (used by Forbes, NYT, many publishers)
      final jsonLdMatch = RegExp(r'"image"\s*:\s*\{\s*"[^"]*"\s*:\s*"[^"]*"\s*,\s*"url"\s*:\s*"([^"]+)"', caseSensitive: false).firstMatch(html) ??
                          RegExp(r'"image"\s*:\s*"(https?://[^"]+)"', caseSensitive: false).firstMatch(html) ??
                          RegExp(r'"thumbnailUrl"\s*:\s*"(https?://[^"]+)"', caseSensitive: false).firstMatch(html) ??
                          RegExp(r'"url"\s*:\s*"(https?://[^"]*(?:\.jpg|\.jpeg|\.png|\.webp)[^"]*)"', caseSensitive: false).firstMatch(html);
      if (jsonLdMatch != null) return _cleanXmlContent(jsonLdMatch.group(1));

      // 5. First large <img> in article body
      final imgMatch = RegExp(r'<img[^>]+src="(https?://[^"]+\.(?:jpg|jpeg|png|webp)[^"]*)"', caseSensitive: false).firstMatch(html);
      if (imgMatch != null) return _cleanXmlContent(imgMatch.group(1));

      return null;
    } catch (e) {
      debugPrint('Scrape error for $url: $e');
      return null;
    }
  }

  String _cleanXmlContent(String? text) {
    if (text == null) return '';
    String cleaned = text.trim();
    if (cleaned.startsWith('<![CDATA[')) {
      cleaned = cleaned.substring(9);
    }
    if (cleaned.endsWith(']]>')) {
      cleaned = cleaned.substring(0, cleaned.length - 3);
    }
    return cleaned.trim();
  }

  String _unescapeHtml(String? text) {
    if (text == null) return '';
    return HtmlCharacterEntities.decode(text);
  }

  String _getTimeAgo(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'Just now';
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      
      if (diff.inDays > 365) return '${(diff.inDays / 365).floor()}y ago';
      if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (e) {
      return 'Just now';
    }
  }

  void _showRelatedSources(BuildContext context, Map<String, dynamic> primaryArticle, List<dynamic> related) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Covered by ${related.length + 1} sources',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _unescapeHtml(primaryArticle['title'] ?? ''),
                  style: const TextStyle(fontSize: 13, color: Colors.white60, height: 1.4),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _openArticle(primaryArticle);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: Color(0xFFFF6200)),
                      const SizedBox(width: 12),
                      Text(
                        _unescapeHtml(primaryArticle['source_name'] ?? 'Unknown'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
                    ],
                  ),
                ),
              ),
              ...related.map((a) => InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _openArticle(Map<String, dynamic>.from(a as Map));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: Colors.white24),
                      const SizedBox(width: 12),
                      Text(
                        _unescapeHtml((a as Map)['source_name']?.toString() ?? 'Unknown'),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
                    ],
                  ),
                ),
              )),
              const Divider(color: Colors.white12, height: 1),
              if (!_isPremium && !_isTrialActive)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFFF6200)),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Get an AI-combined summary of all sources — subscribe to TruBrief AI.',
                          style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
            ),
          ),
        );
      },
    );
  }

  void _openArticle(Map<String, dynamic> article) {
    final url = _cleanXmlContent(article['original_url']);
    if (url.isEmpty) return;
    String? sourceLoginUrl;
    try {
      final uri = Uri.parse(url);
      String host = uri.host;
      const hostRemap = {
        'feeds.a.dj.com': 'www.wsj.com',
        'feeds.bloomberg.com': 'www.bloomberg.com',
        'feeds.apnews.com': 'apnews.com',
        'feeds.washingtonpost.com': 'www.washingtonpost.com',
        'feeds.npr.org': 'www.npr.org',
        'rss.nytimes.com': 'www.nytimes.com',
        'rss.cnn.com': 'www.cnn.com',
        'feeds.bbci.co.uk': 'www.bbc.co.uk',
        'newsnetwork.mayoclinic.org': 'www.mayoclinic.org',
        'rssfeeds.webmd.com': 'www.webmd.com',
      };
      host = hostRemap[host] ?? host.replaceFirst(RegExp(r'^(feeds?\d*|rss)\.'), 'www.');
      sourceLoginUrl = 'https://$host';
    } catch (_) {}
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArticleReaderScreen(
          url: url,
          sourceName: _unescapeHtml(article['source_name'] ?? 'The news source'),
          aiSummary: _unescapeHtml(article['summary_brief']),
          isSubscribed: _isPremium || _isTrialActive,
          sourceLoginUrl: sourceLoginUrl,
        ),
      ),
    );
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SourceSettingsScreen()),
    ).then((_) {
      if (mounted) {
        _fetchUserData();
        _fetchArticles();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        centerTitle: false,
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Search TruBrief...',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _fetchArticles(),
            )
          : const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Tru', 
                    style: TextStyle(
                      fontWeight: FontWeight.w900, 
                      fontSize: 28, 
                      letterSpacing: -1.0,
                    )
                  ),
                  TextSpan(
                    text: 'Brief',
                    style: TextStyle(
                      fontWeight: FontWeight.w900, 
                      fontSize: 28, 
                      color: Color(0xFFFF6200),
                      letterSpacing: -1.0,
                    ),
                  ),
                ],
              ),
            ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search_rounded, size: 26),
            color: Colors.white,
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _fetchArticles();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 26),
              color: Colors.white,
              onPressed: () {
                _fetchArticles();
                _fetchNewArticlesFromSources();
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings_rounded, size: 26),
              color: Colors.white,
              onPressed: _navigateToSettings,
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchArticles,
        color: const Color(0xFFFF6200),
        backgroundColor: const Color(0xFF1C1C1E),
        child: Column(
          children: [
            Container(
              height: 48,
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _selectedCategories.length,
                itemBuilder: (context, index) {
                  final cat = _selectedCategories[index];
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategory = cat;
                          _loading = true;
                        });
                        _fetchArticles();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? const Color(0xFFFF6200) : Colors.white24,
                            width: 1.5,
                          ),
                        ),
                        child: () {
                          final parts = cat.split(' ');
                          if (parts.length >= 2) {
                            return RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: parts[0],
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white38,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' ${parts.skip(1).join(' ')}',
                                    style: TextStyle(
                                      color: isSelected ? const Color(0xFFFF6200) : const Color(0xFFFF6200).withValues(alpha: 0.4),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return Text(
                            cat.toUpperCase(),
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white60,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 0.8,
                            ),
                          );
                        }(),
                      ),
                    ),
                  );
                },
              ),
            ),
            if ((_selectedCategory == 'Local Brief' || _selectedCategory == 'National Brief') && _locationType == 'none')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: InkWell(
                  onTap: _navigateToSettings,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6200).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.location_on, size: 16, color: Color(0xFFFF6200)),
                        SizedBox(width: 8),
                        Text(
                          'SET LOCATION FOR LOCAL BRIEF',
                          style: TextStyle(
                            color: Color(0xFFFF6200),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_selectedCategory == 'Local Brief' && _city != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Color(0xFFFF6200)),
                    const SizedBox(width: 4),
                    Text(
                      '$_city, $_state',
                      style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
                  : _articles.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                            if ((_selectedCategory == 'Local Brief' || _selectedCategory == 'National Brief') && _locationType == 'none') ...[
                              const Center(
                                child: Icon(Icons.location_off_outlined, size: 64, color: Colors.white24),
                              ),
                              const SizedBox(height: 16),
                              const Center(
                                child: Text(
                                  'Location Not Set',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Center(
                                child: Text(
                                  'Set your location to see news from your area.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Center(
                                child: ElevatedButton(
                                  onPressed: _navigateToSettings,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF6200),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  child: const Text('Set Location'),
                                ),
                              ),
                            ] else ...[
                              const Center(
                                child: Icon(Icons.newspaper, size: 64, color: Colors.white24),
                              ),
                              const SizedBox(height: 16),
                              const Center(child: Text('No articles yet', style: TextStyle(fontSize: 16, color: Colors.grey))),
                            ],
                          ],
                        )
                      : ListView.builder(
                          itemCount: _articles.length + 1,
                          itemBuilder: (context, index) {
                    if (index == _articles.length) {
                      // Local Brief uses Google News — subscription source notices don't apply
                      if (_selectedCategory == 'Local Brief') return const SizedBox.shrink();
                      final shortCat = _selectedCategory.replaceAll(' Brief', '').replaceAll(' News', '').trim();
                      final paywallSources = _allSources.where((s) {
                        if (s['requires_subscription'] != true) return false;
                        final sCat = s['category'].toString();
                        return sCat == _selectedCategory || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News' || _selectedCategory == 'Tru Brief';
                      }).toList();
                      if (paywallSources.isEmpty) return const SizedBox.shrink();
                      final names = paywallSources.map((s) => s['name'].toString()).join(', ');
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.lock_outline, size: 16, color: Colors.grey),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '$names require${paywallSources.length == 1 ? 's' : ''} an account to view full articles.',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final article = Map<String, dynamic>.from(_articles[index] as Map);
                    final String? imageUrl = article['image_url'];
                    final String title = _unescapeHtml(article['title'] ?? 'No title');
                    final String source = _unescapeHtml(article['source_name'] ?? 'Unknown Source');
                    final String? summary = _unescapeHtml(article['summary_brief']);
                    final bool isFeatured = index == 0;
                    final List<dynamic> relatedArticles = List<dynamic>.from(article['_related_articles'] as List? ?? []);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      clipBehavior: Clip.antiAlias,
                      color: const Color(0xFF1C1C1E),
                      child: InkWell(
                        onTap: () => _openArticle(article),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty)
                              Stack(
                                children: [
                                  CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    height: isFeatured ? 240 : 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      height: isFeatured ? 240 : 180,
                                      color: const Color(0xFF2A2A2A),
                                    ),
                                    errorWidget: (context, url, error) => const SizedBox.shrink(),
                                  ),
                                  if (isFeatured)
                                    Positioned(
                                      top: 12,
                                      left: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6200),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'LATEST',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: 1.1,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        source.toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFFF6200),
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: Icon(
                                          _savedArticleIds.contains(article['id'].toString())
                                              ? Icons.bookmark
                                              : Icons.bookmark_border,
                                          size: 20,
                                          color: const Color(0xFFFF6200),
                                        ),
                                        onPressed: () => _toggleSaveArticle(article['id'].toString()),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        _getTimeAgo(article['created_at']),
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: isFeatured ? 22 : 18,
                                      fontWeight: FontWeight.w700,
                                      height: 1.2,
                                    ),
                                  ),
                                  if (relatedArticles.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    GestureDetector(
                                      onTap: () => _showRelatedSources(context, article, relatedArticles),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF6200).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: const Color(0xFFFF6200).withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.source_outlined, size: 13, color: Color(0xFFFF6200)),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Reported by ${relatedArticles.length + 1} sources',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFFFF6200),
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            const Icon(Icons.chevron_right, size: 13, color: Color(0xFFFF6200)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (summary != null && summary.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    if (_isPremium || _isTrialActive)
                                      Text(
                                        summary,
                                        style: TextStyle(
                                          fontSize: 15,
                                          color: Colors.white.withValues(alpha: 0.7),
                                          height: 1.5,
                                        ),
                                        maxLines: isFeatured ? 4 : 3,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              'AI Summary Locked',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white.withValues(alpha: 0.5),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            const Text(
                                              'Start your 7-day free trial to read AI briefs.',
                                              style: TextStyle(fontSize: 12, color: Colors.grey),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ),
          ],
        ),
      ),
    );
  }
}

class SourceSettingsScreen extends StatefulWidget {
  const SourceSettingsScreen({super.key});

  @override
  State<SourceSettingsScreen> createState() => _SourceSettingsScreenState();
}

class _SourceSettingsScreenState extends State<SourceSettingsScreen> {
  String? get _effectiveUserId => Supabase.instance.client.auth.currentUser?.id ?? '00000000-0000-4000-a000-000000000000';

  bool _loading = true;
  List<String> _categories = [];
  List<String> _virtualCategories = [];
  List<String> _selectedCategories = [];
  List<dynamic> _sources = [];
  List<String> _selectedSources = [];
  final Set<String> _expandedCategories = {};

  String _locationType = 'none'; // 'exact', 'zip', 'none'
  String? _zipCode;
  final TextEditingController _zipController = TextEditingController();
  bool _showLocationEditor = false;

  bool _briefSourcesExpanded = false;
  bool _addChannelTabsExpanded = false;

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    final userId = _effectiveUserId;
    try {
      // 1. Fetch Categories dynamically
      final catData = await Supabase.instance.client
          .from('trl_categories')
          .select()
          .order('display_order', ascending: true);
      
      final sources = await Supabase.instance.client
          .from('trl_sources')
          .select()
          .timeout(const Duration(seconds: 10));
      
      List<String> selectedSources = [];
      List<String> selectedCategories = [];
      List<String> allCategories = List<String>.from(catData.map((c) => c['name'])).where((c) => c != 'Weekly Top').toList();
      List<String> virtuals = List<String>.from(catData.where((c) => c['is_virtual'] == true && c['name'] != 'Weekly Top').map((c) => c['name']));

      if (userId != null) {
        final prefs = await Supabase.instance.client
            .from('trl_user_preferences')
            .select()
            .eq('user_id', userId)
            .limit(1)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));
        
        if (prefs != null) {
          selectedSources = List<String>.from(prefs['selected_sources'] ?? []);
          final List<String> savedOrder = List<String>.from(prefs['selected_categories'] ?? []);
          
          // Reconstruct _categories based on saved order, then add any NEW categories from DB at the end
          final List<String> orderedCats = [];
          for (var catName in savedOrder) {
            if (allCategories.contains(catName)) {
              orderedCats.add(catName);
            }
          }
          
          for (var dbCat in allCategories) {
            if (!orderedCats.contains(dbCat)) {
              orderedCats.add(dbCat);
            }
          }
          allCategories = orderedCats.where((c) => c != 'Weekly Top').toList();

          // Ensure Tru Brief is ALWAYS first
          if (allCategories.contains('Tru Brief')) {
            allCategories.remove('Tru Brief');
            allCategories.insert(0, 'Tru Brief');
          }

          selectedCategories = List<String>.from(savedOrder).where((c) => c != 'Weekly Top').toList();
          
          if (selectedCategories.isEmpty) {
            selectedCategories = ['Tru Brief', 'Local Brief', 'National Brief', 'World Brief', 'Food Brief'];
          }

          // Normalize selections: strip any subscription sources that aren't explicitly connected,
          // and ensure top 3 free sources are selected for every category
          bool autoSelectionsAdded = false;
          final allSourceIds = sources.map((s) => s['id'].toString()).toSet();
          final subSourceIds = sources.where((s) => s['requires_subscription'] == true).map((s) => s['id'].toString()).toSet();

          // Remove stale IDs and any subscription sources (they must be re-added manually by logging in)
          selectedSources.removeWhere((id) => !allSourceIds.contains(id) || subSourceIds.contains(id));

          for (var cat in allCategories) {
            final shortCat = cat.replaceAll(' Brief', '').replaceAll(' News', '').trim();
            final catSources = sources.where((s) {
              final sCat = s['category'].toString();
              return sCat == cat || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News';
            }).toList();
            final freeCatSources = catSources.where((s) => s['requires_subscription'] != true).toList();
            final freeCatSourceIds = freeCatSources.map((s) => s['id'].toString()).toSet();
            final selectedFreeForCat = selectedSources.where((id) => freeCatSourceIds.contains(id)).toList();

            if (selectedFreeForCat.isEmpty && freeCatSources.isNotEmpty) {
              // No free sources selected for this category — add top 3 free
              for (var i = 0; i < freeCatSources.length && i < 3; i++) {
                selectedSources.add(freeCatSources[i]['id'].toString());
              }
              autoSelectionsAdded = true;
            }
          }

          _locationType = prefs['location_type'] ?? 'none';
          _zipCode = prefs['zip_code'];
          _zipController.text = _zipCode ?? '';
          _showLocationEditor = _locationType == 'none';

          if (autoSelectionsAdded && mounted) {
            setState(() {
              _categories = allCategories;
              _virtualCategories = virtuals;
              _sources = sources;
              _selectedSources = selectedSources;
              _selectedCategories = selectedCategories;
              _loading = false;
            });
            _savePreferences();
            return;
          }
        } else {
          // If no prefs exist, highlight the defaults and select top 3 FREE sources per category
          selectedCategories = ['Tru Brief', 'Local Brief', 'National Brief', 'World Brief', 'Food Brief'];
          _showLocationEditor = true;

          for (var cat in allCategories) {
            final shortCat = cat.replaceAll(' Brief', '').replaceAll(' News', '').trim();
            final freeCatSources = sources.where((s) {
              final sCat = s['category'].toString();
              final matchesCat = sCat == cat || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News';
              return matchesCat && s['requires_subscription'] != true;
            }).toList();
            for (var i = 0; i < freeCatSources.length && i < 3; i++) {
              selectedSources.add(freeCatSources[i]['id'].toString());
            }
          }
        }
      }

      if (catData != null && catData.isNotEmpty && mounted) {
        setState(() {
          _categories = allCategories;
          _virtualCategories = virtuals;
          _sources = sources;
          _selectedSources = selectedSources;
          _selectedCategories = selectedCategories;
          _loading = false;
        });
      } else {
        debugPrint('Warning: No categories found during settings load');
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      debugPrint('Load settings error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _zipController.dispose();
    super.dispose();
  }

  Future<void> _savePreferences({String? city, String? state}) async {
    final userId = _effectiveUserId;
    if (userId == null) return;

    try {
      // Preserve order by filtering _categories based on what is in _selectedCategories
      final List<String> orderedSelections = _categories
          .where((cat) => _selectedCategories.contains(cat))
          .toList();

      final Map<String, dynamic> data = {
        'user_id': userId,
        'selected_sources': _selectedSources,
        'selected_categories': orderedSelections,
        'location_type': _locationType,
        'zip_code': _zipCode,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (city != null) data['city'] = city;
      if (state != null) data['state'] = state;

      await Supabase.instance.client.from('trl_user_preferences').upsert(
        data,
        onConflict: 'user_id',
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6200)))
          : LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- LOCATION SETTINGS ---
                            const Text('Location Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.gps_fixed, color: Color(0xFFFF6200), size: 20),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _locationType == 'exact' ? 'Using exact location' : (_locationType == 'zip' ? 'Zip: $_zipCode' : 'Not set'),
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => setState(() => _showLocationEditor = !_showLocationEditor),
                                        child: Text(_showLocationEditor ? 'Cancel' : 'Change', style: const TextStyle(color: Color(0xFFFF6200))),
                                      ),
                                    ],
                                  ),
                                  if (_showLocationEditor) ...[
                                    const Divider(color: Colors.white10, height: 24),
                                    ListTile(
                                      leading: const Icon(Icons.my_location, color: Colors.white70),
                                      title: const Text('Use GPS Location'),
                                      subtitle: const Text('Most accurate for local news'),
                                      onTap: () async {
                                        setState(() => _loading = true);
                                        try {
                                          LocationPermission permission = await Geolocator.checkPermission();
                                          if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
                                          
                                          if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
                                            Position position = await Geolocator.getCurrentPosition();
                                            List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
                                            if (placemarks.isNotEmpty) {
                                              Placemark place = placemarks[0];
                                              setState(() {
                                                _locationType = 'exact';
                                                _zipCode = place.postalCode;
                                                _showLocationEditor = false;
                                              });
                                              _savePreferences(
                                                city: place.locality,
                                                state: place.administrativeArea,
                                              );
                                            }
                                          }
                                        } catch (e) {
                                          debugPrint('GPS error: $e');
                                        } finally {
                                          setState(() => _loading = false);
                                        }
                                      },
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 16),
                                      child: Row(
                                        children: [
                                          Expanded(child: Divider(color: Colors.white10)),
                                          Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 12),
                                            child: Text('OR', style: TextStyle(color: Colors.white24, fontSize: 10)),
                                          ),
                                          Expanded(child: Divider(color: Colors.white10)),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _zipController,
                                              decoration: const InputDecoration(
                                                hintText: 'Enter Zip Code',
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              keyboardType: TextInputType.number,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          ElevatedButton(
                                            onPressed: () {
                                              if (_zipController.text.length == 5) {
                                                setState(() {
                                                  _locationType = 'zip';
                                                  _zipCode = _zipController.text;
                                                  _showLocationEditor = false;
                                                });
                                                _savePreferences();
                                              }
                                            },
                                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6200)),
                                            child: const Text('Save'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),

                          // --- TRU BRIEF SOURCES (COLLAPSIBLE) ---
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6200),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => setState(() => _briefSourcesExpanded = !_briefSourcesExpanded),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Tru Brief', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Icon(_briefSourcesExpanded ? Icons.expand_less : Icons.expand_more),
                              ],
                            ),
                          ),
                          
                          if (_briefSourcesExpanded)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                children: _categories.where((cat) => !_virtualCategories.contains(cat)).map((cat) {
                                  final shortCat = cat.replaceAll(' Brief', '').replaceAll(' News', '').trim();
                                  final catSources = _sources.where((s) {
                                    final sCat = s['category']?.toString() ?? '';
                                    return sCat == cat || sCat == shortCat || sCat == '$shortCat Brief' || sCat == '$shortCat News';
                                  }).toList();

                                  final isCatExpanded = _expandedCategories.contains(cat);
                                  final catSourceIds = catSources.map((s) => s['id'].toString()).toSet();
                                  final defaultTop3Ids = catSources.where((s) => s['requires_subscription'] != true).take(3).map((s) => s['id'].toString()).toSet();
                                  final hasCustom = _selectedSources.any((id) => catSourceIds.contains(id) && !defaultTop3Ids.contains(id));

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: Column(
                                      children: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFFF6200).withValues(alpha: isCatExpanded ? 1.0 : 0.8),
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(double.infinity, 44),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            elevation: 0,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              if (isCatExpanded) {
                                                _expandedCategories.remove(cat);
                                              } else {
                                                _expandedCategories.add(cat);
                                              }
                                            });
                                          },
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(cat, style: const TextStyle(fontWeight: FontWeight.bold)),
                                              Row(
                                                children: [
                                                  if (hasCustom)
                                                    const Padding(
                                                      padding: EdgeInsets.only(right: 8),
                                                      child: Text('custom', style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.white70)),
                                                    ),
                                                  Icon(isCatExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isCatExpanded)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Builder(builder: (context) {
                                                  final freeSources = catSources.where((s) => s['requires_subscription'] != true).toList();
                                                  final subSources = catSources.where((s) => s['requires_subscription'] == true).toList();
                                                  final connectedSubs = subSources.where((s) => _selectedSources.contains(s['id'].toString())).toList();
                                                  final unconnectedSubs = subSources.where((s) => !_selectedSources.contains(s['id'].toString())).toList();
                                                  final topSources = [...freeSources.take(3), ...connectedSubs];
                                                  final moreFree = freeSources.skip(3).toList();
                                                  return Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        connectedSubs.isEmpty ? 'Top 3 News Sources' : 'Your Top Sources',
                                                        style: const TextStyle(fontSize: 12, color: Color(0xFFFF6200), fontWeight: FontWeight.bold),
                                                      ),
                                                      ...topSources.map((src) => _buildSourceTile(src, isSubscription: src['requires_subscription'] == true)),
                                                      if (moreFree.isNotEmpty) ...[
                                                        const Divider(color: Colors.white10),
                                                        const Text('More Sources', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                                        ...moreFree.map((src) => _buildSourceTile(src)),
                                                      ],
                                                      if (unconnectedSubs.isNotEmpty) ...[
                                                        const Divider(color: Colors.white24),
                                                        Row(
                                                          children: const [
                                                            Icon(Icons.lock_outline, size: 12, color: Colors.orange),
                                                            SizedBox(width: 4),
                                                            Text('Sources Require Account', style: TextStyle(fontSize: 12, color: Colors.orange)),
                                                          ],
                                                        ),
                                                        ...unconnectedSubs.map((src) => _buildSourceTile(src, isSubscription: true)),
                                                      ],
                                                    ],
                                                  );
                                                }),
                                                const Divider(color: Colors.white10),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.person_outline, size: 12, color: Colors.white38),
                                                    const SizedBox(width: 4),
                                                    const Text('Have an account? Tap', style: TextStyle(fontSize: 11, color: Colors.white38)),
                                                    const SizedBox(width: 4),
                                                    const Icon(Icons.login, size: 12, color: Colors.white38),
                                                    const Text(' on any source to sign in', style: TextStyle(fontSize: 11, color: Colors.white38)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          const SizedBox(height: 32),

                          // --- ADD CHANNEL TABS (COLLAPSIBLE) ---
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6200),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => setState(() => _addChannelTabsExpanded = !_addChannelTabsExpanded),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Show Channel Tabs', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Icon(_addChannelTabsExpanded ? Icons.expand_less : Icons.expand_more),
                              ],
                            ),
                          ),

                          if (_addChannelTabsExpanded)
                            Container(
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: ReorderableListView(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                buildDefaultDragHandles: false,
                                onReorder: (oldIndex, newIndex) {
                                  setState(() {
                                    if (newIndex > oldIndex) newIndex -= 1;
                                    if (newIndex == 0) newIndex = 1;
                                    if (oldIndex == 0) return;
                                    final String item = _categories.removeAt(oldIndex);
                                    _categories.insert(newIndex, item);
                                  });
                                  _savePreferences();
                                },
                                children: _categories.map((cat) {
                                  final bool isTruBrief = cat == 'Tru Brief';
                                  final bool isSelected = _selectedCategories.contains(cat);

                                  return Padding(
                                    key: ValueKey(cat),
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: InkWell(
                                      onTap: isTruBrief ? null : () {
                                        setState(() {
                                          if (isSelected) {
                                            _selectedCategories.remove(cat);
                                          } else {
                                            _selectedCategories.add(cat);
                                          }
                                        });
                                        _savePreferences();
                                      },
                                      child: Container(
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFF2C1C16) : const Color(0xFF000000),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isSelected ? const Color(0xFFFF6200).withValues(alpha: 0.5) : Colors.white10,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const SizedBox(width: 12),
                                            if (isTruBrief)
                                              const Icon(Icons.push_pin, color: Color(0xFFFF6200), size: 18)
                                            else
                                              ReorderableDragStartListener(
                                                index: _categories.indexOf(cat),
                                                child: const Icon(Icons.drag_handle, color: Colors.white24, size: 20),
                                              ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                cat,
                                                style: TextStyle(
                                                  color: isSelected ? Colors.white : Colors.white54,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                            ),
                                            if (isSelected)
                                              const Padding(
                                                padding: EdgeInsets.only(right: 12),
                                                child: Icon(Icons.check, color: Color(0xFFFF6200), size: 18),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            
                          const SizedBox(height: 32),
                          const Divider(color: Colors.white10, height: 40),
                          Center(
                            child: Column(
                              children: [
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 0,
                                  children: [
                                    _buildLegalLink('Disclaimer',
                                      'DISCLAIMER — TruBrief by Tru-Resolve LLC\n\n'
                                      'TruBrief is a news aggregator that curates publicly available RSS feed content and provides AI-generated summaries for quick, informed reading.\n\n'
                                      'CONTENT OWNERSHIP\n'
                                      'All articles, images, and original content remain the exclusive property of their respective publishers and journalists. Tru-Resolve LLC does not claim ownership of any news content. Full credit and attribution belong to the original creators. We display brief summaries only; full articles open directly on the publisher\'s website.\n\n'
                                      'AI-GENERATED SUMMARIES\n'
                                      'Article summaries in TruBrief are generated by artificial intelligence. These summaries may contain errors, omissions, or inaccuracies. They are provided for informational convenience only and do not constitute professional, legal, medical, financial, or any other form of advice. Always refer to the original article for complete and accurate information.\n\n'
                                      'NO ENDORSEMENT\n'
                                      'The inclusion of any news source or article does not imply endorsement by Tru-Resolve LLC. We are not responsible for the accuracy, legality, completeness, or content of any third-party source.\n\n'
                                      'AS IS / NO WARRANTIES\n'
                                      'TruBrief is provided "AS IS" and "AS AVAILABLE" without warranties of any kind, either express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, or non-infringement. We do not guarantee uninterrupted, error-free, or secure access to the service.\n\n'
                                      'LIMITATION OF LIABILITY\n'
                                      'To the fullest extent permitted by applicable law, Tru-Resolve LLC, its officers, directors, employees, and agents shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of or inability to use TruBrief. Our total liability shall not exceed the greater of the amount you paid us in the preceding 12 months or \$50 USD.\n\n'
                                      'AGE REQUIREMENT\n'
                                      'TruBrief is intended for users 13 years of age or older. By using this app, you confirm that you are at least 13 years old. Users under 18 should have parental or guardian consent. We do not knowingly collect personal information from children under 13. If you believe a child under 13 has provided us with personal information, contact us at contact@tru-resolve.com and we will delete it promptly.\n\n'
                                      'By continuing to use TruBrief, you agree to respect all copyrights, support the original publishers, and accept this disclaimer in full.'
                                    ),
                                    _buildLegalLink('Terms of Service',
                                      'TERMS OF SERVICE — Tru-Resolve LLC\n'
                                      'Effective Date: January 1, ${DateTime.now().year}\n\n'
                                      '1. ACCEPTANCE OF TERMS\n'
                                      'By downloading, installing, or using TruBrief, you agree to be bound by these Terms of Service ("Terms"). If you do not agree, do not use the app. We reserve the right to update these Terms at any time; continued use constitutes acceptance.\n\n'
                                      '2. ELIGIBILITY\n'
                                      'You must be at least 13 years old to use TruBrief. By using the app, you represent and warrant that you meet this age requirement. Users under 18 must have parental or guardian consent.\n\n'
                                      '3. PERMITTED USE\n'
                                      'TruBrief is licensed for personal, non-commercial use only. You may not: (a) scrape, copy, or redistribute content; (b) use automated systems to access the service; (c) reverse engineer or decompile the app; (d) use the app for unlawful purposes; or (e) circumvent any access controls or security features.\n\n'
                                      '4. INTELLECTUAL PROPERTY\n'
                                      'Tru-Resolve LLC owns all rights to the TruBrief app, its design, code, and branding. We do not claim ownership of third-party news content. All such content remains the property of its respective publishers.\n\n'
                                      '5. THIRD-PARTY CONTENT\n'
                                      'All news content is sourced from publicly available third-party RSS feeds. We do not endorse, verify, or take responsibility for any third-party content. Your access to third-party websites is governed by those sites\' own terms and privacy policies.\n\n'
                                      '6. AI-GENERATED SUMMARIES\n'
                                      'Article summaries are generated by AI and may contain inaccuracies. They are for informational purposes only and do not constitute professional advice of any kind.\n\n'
                                      '7. IN-APP BROWSER & THIRD-PARTY LOGINS\n'
                                      'When you use TruBrief\'s in-app browser to access news sources or log in to third-party accounts (e.g., NYT, WSJ), you are subject to those sites\' own terms of service and privacy policies. Tru-Resolve LLC is not responsible for the content, conduct, cookies, or data practices of any third-party site accessed through the app.\n\n'
                                      '8. DISCLAIMER OF WARRANTIES\n'
                                      'The service is provided "AS IS" and "AS AVAILABLE" without any warranties, express or implied. We do not warrant accuracy, completeness, availability, or fitness for a particular purpose.\n\n'
                                      '9. LIMITATION OF LIABILITY\n'
                                      'To the fullest extent permitted by law, Tru-Resolve LLC shall not be liable for any indirect, incidental, special, consequential, or punitive damages. Our maximum liability shall not exceed \$50 USD or amounts paid by you in the prior 12 months.\n\n'
                                      '10. INDEMNIFICATION\n'
                                      'You agree to defend, indemnify, and hold harmless Tru-Resolve LLC and its officers, directors, employees, and agents from any claims, liabilities, damages, or expenses (including attorneys\' fees) arising from: (a) your use of the app; (b) your violation of these Terms; or (c) your violation of any third-party rights.\n\n'
                                      '11. DISPUTE RESOLUTION & ARBITRATION\n'
                                      'Any dispute arising from these Terms or your use of TruBrief shall be resolved by binding individual arbitration under the rules of the American Arbitration Association (AAA), not in court. YOU WAIVE YOUR RIGHT TO A JURY TRIAL AND TO PARTICIPATE IN CLASS ACTION LAWSUITS. You may opt out of arbitration within 30 days of first use by emailing contact@tru-resolve.com with "Arbitration Opt-Out" in the subject line.\n\n'
                                      '12. CLASS ACTION WAIVER\n'
                                      'You may only bring claims against Tru-Resolve LLC in your individual capacity. You may not bring or participate in any class, collective, or representative action or proceeding.\n\n'
                                      '13. TERMINATION\n'
                                      'We reserve the right to suspend or terminate your access to TruBrief at any time, for any reason, without notice, including for violation of these Terms. We also reserve the right to modify, suspend, or discontinue the service at any time.\n\n'
                                      '14. REPEAT INFRINGER POLICY\n'
                                      'We reserve the right to terminate accounts of users who are found to repeatedly infringe third-party intellectual property rights.\n\n'
                                      '15. GOVERNING LAW\n'
                                      'These Terms are governed by the laws of the State of Florida, United States, without regard to conflict of law principles. Any disputes not subject to arbitration shall be brought exclusively in the state or federal courts located in Florida.\n\n'
                                      'Contact: contact@tru-resolve.com'
                                    ),
                                    _buildLegalLink('Privacy Policy',
                                      'PRIVACY POLICY — Tru-Resolve LLC\n'
                                      'Last Updated: January 1, ${DateTime.now().year}\n\n'
                                      'This Privacy Policy explains how Tru-Resolve LLC ("we," "us," or "our") collects, uses, and protects your information when you use TruBrief.\n\n'
                                      '1. INFORMATION WE COLLECT\n'
                                      'We collect only what is necessary to operate TruBrief:\n'
                                      '• Account data: email address and authentication credentials (if you sign in)\n'
                                      '• Preferences: your selected news categories and sources\n'
                                      '• Saved articles: articles you bookmark within the app\n'
                                      '• Location data: zip code or city (only if you enable Local Brief and grant permission)\n\n'
                                      '2. INFORMATION WE DO NOT COLLECT\n'
                                      'We do not collect: contacts, precise GPS location, payment information, browsing history outside the app, device identifiers for advertising, or any data we do not need to operate the service.\n\n'
                                      '3. HOW WE USE YOUR DATA\n'
                                      'Your data is used solely to: provide and personalize the TruBrief experience, maintain your preferences across sessions, and improve the app. We do not sell, rent, or share your personal data with third parties for marketing purposes.\n\n'
                                      '4. CHILDREN\'S PRIVACY (COPPA COMPLIANCE)\n'
                                      'TruBrief is not directed to children under 13. We do not knowingly collect personal information from children under 13. If we become aware that a child under 13 has provided personal information, we will delete it immediately. Parents or guardians who believe their child has submitted information may contact us at contact@tru-resolve.com.\n\n'
                                      '5. IN-APP BROWSER & THIRD-PARTY COOKIES\n'
                                      'When you access news sources or log in to third-party accounts through TruBrief\'s in-app browser, those sites may set cookies or collect data independently. We have no access to or control over third-party cookies or their data practices. Please review each source\'s privacy policy separately.\n\n'
                                      '6. THIRD-PARTY SERVICES\n'
                                      'We use Supabase to store account and preference data securely. Supabase\'s privacy practices are described at supabase.com/privacy.\n\n'
                                      '7. DATA RETENTION\n'
                                      'We retain your data for as long as your account is active. You may request deletion of your account and associated data at any time by contacting contact@tru-resolve.com.\n\n'
                                      '8. SECURITY\n'
                                      'We implement industry-standard security measures including encrypted data transmission (TLS) and secure cloud storage. However, no method of internet transmission is 100% secure, and we cannot guarantee absolute security.\n\n'
                                      '9. YOUR RIGHTS\n'
                                      'Depending on your location, you may have rights including:\n'
                                      '• Access: request a copy of data we hold about you\n'
                                      '• Correction: request correction of inaccurate data\n'
                                      '• Deletion: request deletion of your data ("Right to be Forgotten")\n'
                                      '• Opt-out: opt out of any data sharing\n'
                                      'To exercise any right, contact: contact@tru-resolve.com\n\n'
                                      '10. CALIFORNIA RESIDENTS (CCPA)\n'
                                      'California residents have the right to know what personal information is collected, to opt out of the sale of personal information (we do not sell your data), and to request deletion. To submit a request, email contact@tru-resolve.com with "CCPA Request" in the subject.\n\n'
                                      '11. EUROPEAN USERS (GDPR)\n'
                                      'If you are in the European Economic Area, our legal basis for processing your data is: (a) your consent, and (b) legitimate interest in providing the service. You have the right to lodge a complaint with your local data protection authority.\n\n'
                                      '12. CHANGES TO THIS POLICY\n'
                                      'We may update this Privacy Policy periodically. We will notify you of material changes through the app. Your continued use of TruBrief after changes constitutes acceptance.\n\n'
                                      'Contact: contact@tru-resolve.com'
                                    ),
                                    _buildLegalLink('DMCA / Copyright',
                                      'DMCA & COPYRIGHT POLICY — Tru-Resolve LLC\n\n'
                                      'OVERVIEW\n'
                                      'TruBrief aggregates publicly available RSS feed content that publishers make available for distribution. We display AI-generated summaries only; all full articles open directly on the original publisher\'s website. We respect intellectual property rights and comply fully with the Digital Millennium Copyright Act (17 U.S.C. § 512).\n\n'
                                      'DMCA SAFE HARBOR\n'
                                      'Tru-Resolve LLC qualifies for DMCA safe harbor protection as a service provider under 17 U.S.C. § 512(c). We have designated a Copyright Agent to receive infringement notices.\n\n'
                                      'TO FILE A TAKEDOWN NOTICE\n'
                                      'If you believe content in TruBrief infringes your copyright, please send a written notice to our Copyright Agent at:\n\n'
                                      'Copyright Agent — Tru-Resolve LLC\n'
                                      'Email: contact@tru-resolve.com\n'
                                      'Subject: DMCA Takedown Notice\n\n'
                                      'Your notice must include ALL of the following:\n'
                                      '• Your full legal name and contact information (address, phone, email)\n'
                                      '• Identification of the copyrighted work you claim has been infringed\n'
                                      '• Identification of the specific content in TruBrief you believe infringes (including URL or description)\n'
                                      '• A statement that you have a good faith belief that the use is not authorized by the copyright owner, its agent, or the law\n'
                                      '• A statement, made under penalty of perjury, that the information in your notice is accurate and that you are the copyright owner or authorized to act on their behalf\n'
                                      '• Your physical or electronic signature\n\n'
                                      'REPEAT INFRINGER POLICY\n'
                                      'In accordance with 17 U.S.C. § 512(i), we maintain a policy of terminating, in appropriate circumstances, users who are repeat infringers of intellectual property rights.\n\n'
                                      'COUNTER-NOTIFICATION\n'
                                      'If you believe content was removed in error, you may submit a counter-notification to contact@tru-resolve.com including: your name and contact info, identification of the removed content, a statement under penalty of perjury that the content was removed by mistake, and your consent to jurisdiction of the Federal District Court for Florida.\n\n'
                                      'We will process all valid notices promptly in accordance with applicable law.'
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  '© ${DateTime.now().year} Tru-Resolve LLC',
                                  style: const TextStyle(color: Colors.white24, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
              );
            },
          ),
    );
  }

  Widget _buildLegalLink(String title, String content) {
    return TextButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LegalContentScreen(title: title, content: content),
          ),
        );
      },
      style: TextButton.styleFrom(
        foregroundColor: Colors.white38,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12, decoration: TextDecoration.underline),
      ),
    );
  }

  String _getSourceHomepage(dynamic src) {
    final rssUrl = src['url']?.toString() ?? '';
    try {
      final uri = Uri.parse(rssUrl);
      String host = uri.host;
      const hostRemap = {
        'feeds.a.dj.com': 'www.wsj.com',
        'feeds.bloomberg.com': 'www.bloomberg.com',
        'feeds.apnews.com': 'apnews.com',
        'feeds.washingtonpost.com': 'www.washingtonpost.com',
        'feeds.npr.org': 'www.npr.org',
        'rss.nytimes.com': 'www.nytimes.com',
        'rss.cnn.com': 'www.cnn.com',
        'feeds.bbci.co.uk': 'www.bbc.co.uk',
        'newsnetwork.mayoclinic.org': 'www.mayoclinic.org',
        'rssfeeds.webmd.com': 'www.webmd.com',
      };
      host = hostRemap[host] ?? host.replaceFirst(RegExp(r'^(feeds?\d*|rss)\.'), 'www.');
      return 'https://$host';
    } catch (_) {
      return rssUrl;
    }
  }

  void _openSourceLogin(dynamic src) {
    final homepage = _getSourceHomepage(src);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleReaderScreen(
          url: homepage,
          sourceName: src['name'] ?? 'Source',
          isSubscribed: true,
        ),
      ),
    );
  }

  Widget _buildSourceTile(dynamic src, {bool isSubscription = false}) {
    final isSelected = _selectedSources.contains(src['id'].toString());
    return Row(
      children: [
        Expanded(
          child: CheckboxListTile(
            title: Text(src['name'], style: const TextStyle(fontSize: 14)),
            subtitle: Text(src['url'], style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
            value: isSelected,
            activeColor: const Color(0xFFFF6200),
            contentPadding: EdgeInsets.zero,
            dense: true,
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _selectedSources.add(src['id'].toString());
                  if (isSubscription) {
                    _openSourceLogin(src);
                  }
                } else {
                  _selectedSources.remove(src['id'].toString());
                }
              });
              _savePreferences();
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.login, size: 16, color: Colors.white38),
          tooltip: 'Sign in to ${src['name']}',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          onPressed: () => _openSourceLogin(src),
        ),
      ],
    );
  }
}

// Full-screen in-app browser with AI summary overlay
class ArticleReaderScreen extends StatefulWidget {
  final String url;
  final String sourceName;
  final String? aiSummary;
  final bool isSubscribed;
  final String? sourceLoginUrl;

  const ArticleReaderScreen({
    super.key,
    required this.url,
    required this.sourceName,
    this.aiSummary,
    this.isSubscribed = false,
    this.sourceLoginUrl,
  });

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  bool _showOriginal = false;
  bool _isError = false;
  bool _isGeoRestricted = false;
  double _progress = 0;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _showOriginal = !widget.isSubscribed || widget.aiSummary == null || widget.aiSummary!.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSummary = widget.aiSummary != null && widget.aiSummary!.isNotEmpty;
    
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_showOriginal ? 'Reading Article' : 'AI Summary'),
        backgroundColor: Colors.black,
        actions: [
          if (_showOriginal) ...[
            IconButton(
              icon: const Icon(Icons.open_in_browser),
              tooltip: 'Open in Browser',
              onPressed: () async {
                final uri = Uri.parse(widget.url);
                // Simple attempt to launch via platform
                await http.get(uri); // This is just to check connectivity
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _webViewController?.reload(),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          // Browser view (Original Article)
          if (_showOriginal)
            SafeArea(
              child: Stack(
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      isFraudulentWebsiteWarningEnabled: true,
                      safeBrowsingEnabled: true,
                      allowsBackForwardNavigationGestures: true,
                      contentBlockers: [
                        for (final domain in const [
                          'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
                          'adservice.google.com', 'pagead2.googlesyndication.com',
                          'amazon-adsystem.com', 'ads.twitter.com', 'ads.linkedin.com',
                          'outbrain.com', 'taboola.com', 'pubmatic.com', 'openx.net',
                          'rubiconproject.com', 'criteo.com', 'moatads.com', 'adtech.de',
                          'scorecardresearch.com', 'quantserve.com', 'casalemedia.com',
                          'adsymptotic.com', 'advertising.com', 'adnxs.com', 'ads.yahoo.com',
                          'media.net', 'adsafeprotected.com', 'sharethrough.com',
                          'smartadserver.com', 'sovrn.com', 'indexexchange.com',
                          'lijit.com', 'tidaltv.com', 'turn.com', 'tremorhub.com',
                          'spotxchange.com', 'springserve.com', 'contextweb.com',
                          'oath.com', 'yldbt.com', 'bidswitch.net', 'rlcdn.com',
                        ])
                          ContentBlocker(
                            trigger: ContentBlockerTrigger(urlFilter: '.*$domain.*'),
                            action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
                          ),
                      ],
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                    onProgressChanged: (controller, progress) {
                      setState(() {
                        _progress = progress / 100;
                      });
                    },
                    onLoadStop: (controller, url) async {
                      const adCssJs = '''
                        (function() {
                          var style = document.createElement('style');
                          style.textContent = `
                            ins.adsbygoogle, [id*="google_ads"], [class*="google-ad"],
                            [class*="adsbygoogle"], [data-ad-unit], [data-ad-slot],
                            [class*=" ad-"], [class*="-ad "], [class*="-ads "],
                            [class*=" ads-"], [id*="-ad-"], [id*="_ad_"],
                            .advertisement, .sponsored, .sponsored-content,
                            [class*="sponsor"], [class*="outbrain"], [class*="taboola"],
                            [id*="outbrain"], [id*="taboola"], [class*="dfp-ad"],
                            [class*="prebid"], [class*="banner-ad"], [id*="banner-ad"],
                            iframe[src*="doubleclick"], iframe[src*="googlesyndication"],
                            iframe[src*="adnxs"], iframe[src*="taboola"],
                            iframe[src*="outbrain"] { display: none !important; }
                          `;
                          document.head.appendChild(style);
                        })();
                      ''';
                      const cleanupJs = '''
                        (function() {
                          document.documentElement.style.overflow = 'auto';
                          document.body.style.overflow = 'auto';
                          document.body.style.position = 'relative';
                          var els = document.querySelectorAll('*');
                          for (var i = 0; i < els.length; i++) {
                            var style = window.getComputedStyle(els[i]);
                            var zIndex = parseInt(style.zIndex);
                            if (
                              (style.position === 'fixed' || style.position === 'sticky') &&
                              zIndex > 1000 &&
                              (els[i].scrollHeight > window.innerHeight * 0.4 ||
                               els[i].offsetWidth > window.innerWidth * 0.8)
                            ) {
                              els[i].style.display = 'none';
                            }
                          }
                        })();
                      ''';
                      await controller.evaluateJavascript(source: adCssJs);
                      await controller.evaluateJavascript(source: cleanupJs);

                      const geoCheckJs = '''
                        (function() {
                          var t = (document.body && document.body.innerText || '').toLowerCase();
                          var phrases = [
                            'not available in your region',
                            'not available in your country',
                            'only available in the uk',
                            'not available outside',
                            'geo-restricted',
                            'geo restricted',
                            'available only in',
                            'not available where you are',
                            'content is not available in your location',
                            'this video is not available',
                            'iplayer isn',
                          ];
                          for (var p of phrases) { if (t.includes(p)) return true; }
                          return false;
                        })()
                      ''';
                      final isGeoBlocked = await controller.evaluateJavascript(source: geoCheckJs);
                      if (isGeoBlocked == true && mounted) {
                        setState(() {
                          _isGeoRestricted = true;
                          _isError = true;
                        });
                        return;
                      }

                      await Future.delayed(const Duration(seconds: 2));
                      if (mounted) {
                        await controller.evaluateJavascript(source: adCssJs);
                        await controller.evaluateJavascript(source: cleanupJs);
                      }
                      await Future.delayed(const Duration(seconds: 3));
                      if (mounted) await controller.evaluateJavascript(source: cleanupJs);
                    },
                    onLoadError: (controller, url, code, message) {
                      if (code == -999) return;
                      if (mounted) {
                        setState(() => _isError = true);
                      }
                    },
                    onLoadHttpError: (controller, url, statusCode, description) {
                      if (statusCode == 404 || statusCode >= 500) {
                        if (mounted) {
                          setState(() => _isError = true);
                        }
                      }
                    },
                  ),
                  if (_isError)
                    Container(
                      color: Colors.black,
                      width: double.infinity,
                      height: double.infinity,
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isGeoRestricted ? Icons.location_off : Icons.error_outline,
                            size: 64,
                            color: const Color(0xFFFF6200),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _isGeoRestricted ? 'Not Available in Your Region' : 'Article Unavailable',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _isGeoRestricted
                                ? 'This content from ${widget.sourceName} is restricted to certain regions and cannot be viewed from your location.'
                                : widget.sourceLoginUrl != null
                                    ? 'This article may require a ${widget.sourceName} account to view.'
                                    : '${widget.sourceName} has removed this article or changed its location, and it is no longer accessible.',
                            style: const TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          if (!_isGeoRestricted && widget.sourceLoginUrl != null)
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() => _isError = false);
                                _webViewController?.loadUrl(
                                  urlRequest: URLRequest(url: WebUri(widget.sourceLoginUrl!)),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6200),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              ),
                              icon: const Icon(Icons.login, size: 18),
                              label: Text('Log In to ${widget.sourceName}'),
                            ),
                          if (!_isGeoRestricted && widget.sourceLoginUrl != null) const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white12,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            child: const Text('Go Back'),
                          ),
                        ],
                      ),
                    ),
                  if (_progress < 1.0 && !_isError)
                    LinearProgressIndicator(
                      value: _progress,
                      color: const Color(0xFFFF6200),
                      backgroundColor: Colors.black,
                    ),
                ],
              ),
            ),
          
          // Non-subscriber call-to-action bar
          if (!widget.isSubscribed && _showOriginal)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  // In a real app, this would navigate to a subscription/payment page
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Subscription coming soon!')),
                  );
                },
                child: Container(
                  height: 40,
                  color: const Color(0xFFFF6200),
                  child: const Center(
                    child: Text(
                      'SUBSCRIBE FOR AI SUMMARY',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),

          // Subscriber AI Summary View
          if (widget.isSubscribed && !_showOriginal && hasSummary)
            Container(
              color: Colors.black,
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TRUBRIEF SUMMARY',
                      style: TextStyle(
                        color: Color(0xFFFF6200),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.aiSummary!,
                      style: const TextStyle(
                        fontSize: 19,
                        height: 1.6,
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      
      // Floating button for subscribers to toggle between summary and original article
      floatingActionButton: (widget.isSubscribed && hasSummary)
          ? FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  _showOriginal = !_showOriginal;
                });
              },
              backgroundColor: const Color(0xFFFF6200),
              label: Text(_showOriginal ? 'View AI Brief' : 'Read Original Article'),
              icon: Icon(_showOriginal ? Icons.summarize : Icons.article),
            )
          : null,
    );
  }
}

class LegalContentScreen extends StatelessWidget {
  final String title;
  final String content;

  const LegalContentScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFFFF6200),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),
            Text(
              content,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.6,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 64),
            const Center(
              child: Opacity(
                opacity: 0.2,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: 'Tru', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      TextSpan(
                        text: 'Brief',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFFF6200), fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Professional News Curation',
                style: TextStyle(color: Colors.white10, fontSize: 10, fontStyle: FontStyle.italic),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
