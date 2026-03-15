import 'package:supabase/supabase.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  print('🚀 Starting Local News Ingestion...');
  
  final client = SupabaseClient(
    'https://kusvloreaakrvwsdhqhj.supabase.co',
    'sb_publishable_eHuAUb_bxcu8mi5ZL8u9XA_k4iQjeCW', // Note: For writing from a script, service_role is usually better, but we will try with this.
  );

  try {
    // 1. Fetch sources
    final List<dynamic> sources = await client.from('trl_sources').select();
    print('Found ${sources.length} sources.');

    for (var source in sources) {
      final String name = source['name'];
      final String url = source['url'];
      print('📥 Fetching $name...');

      try {
        final response = await http.get(Uri.parse(url));
        final xml = response.body;

        final itemMatches = RegExp(r'<item>([\s\S]*?)<\/item>').allMatches(xml);
        int added = 0;

        for (var match in itemMatches) {
          final item = match.group(1)!;
          
          final titleMatch = RegExp(r'<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/title>', caseSensitive: false).firstMatch(item);
          final linkMatch = RegExp(r'<link>([\s\S]*?)<\/link>', caseSensitive: false).firstMatch(item);
          
          final title = titleMatch?.group(1)?.trim() ?? 'No Title';
          final originalUrl = linkMatch?.group(1)?.trim();

          if (originalUrl == null) continue;

          // Simple duplicate check
          final existing = await client
              .from('trl_articles')
              .select('id')
              .eq('original_url', originalUrl)
              .limit(1)
              .maybeSingle();

          if (existing == null) {
            await client.from('trl_articles').insert({
              'title': title,
              'original_url': originalUrl,
              'source_name': name,
              'source_id': source['id'],
              'category': source['category'],
              'city': source['city'],
              'state': source['state'],
            });
            added++;
          }
        }
        print('✅ Added $added new articles from $name.');
      } catch (e) {
        print('❌ Error fetching $name: $e');
      }
    }
    print('🏁 Ingestion Complete!');
  } catch (e) {
    print('💥 Critical Error: $e');
  }
}
