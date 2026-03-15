import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 1. Fetch all RSS sources
    const { data: sources, error: sourcesError } = await supabase
      .from('trl_sources')
      .select('*')
      .eq('type', 'rss')

    if (sourcesError) throw sourcesError

    let totalArticlesAdded = 0

    for (const source of sources) {
      console.log(`Fetching RSS for: ${source.name} (${source.url})`)
      
      try {
        const response = await fetch(source.url)
        const xml = await response.text()
        
        // Manual basic extraction for better reliability across different RSS formats
        const itemMatches = xml.matchAll(/<item>([\s\S]*?)<\/item>/g);
        
        for (const match of itemMatches) {
          const item = match[1];
          const titleMatch = item.match(/<title><!\[CDATA\[([\s\S]*?)\]\]><\/title>/i) || item.match(/<title>([\s\S]*?)<\/title>/i);
          const linkMatch = item.match(/<link>([\s\S]*?)<\/link>/i);
          const pubDateMatch = item.match(/<pubDate>([\s\S]*?)<\/pubDate>/i);

          const title = titleMatch ? titleMatch[1].trim() : "No Title";
          const original_url = linkMatch ? linkMatch[1].trim() : null;
          
          if (!original_url) continue;

          // Duplicate check
          const { data: existing } = await supabase
            .from('trl_articles')
            .select('id')
            .eq('original_url', original_url)
            .limit(1)

          if (!existing || existing.length === 0) {
            console.log(`Adding new article: ${title}`)
            await supabase
              .from('trl_articles')
              .insert({
                title,
                original_url,
                source_name: source.name,
                source_id: source.id,
                category: source.category,
                created_at: pubDateMatch ? new Date(pubDateMatch[1]).toISOString() : new Date().toISOString()
              })
            totalArticlesAdded++
          }
        }
      } catch (err) {
        console.error(`Error processing ${source.name}:`, err.message)
      }
    }

    return new Response(
      JSON.stringify({ message: "Ingestion complete", added: totalArticlesAdded }), 
      { status: 200, headers: { "Content-Type": "application/json" } }
    )

  } catch (e) {
    console.error("Ingestion Function Error:", e.message)
    return new Response(
      JSON.stringify({ error: e.message }), 
      { status: 500, headers: { "Content-Type": "application/json" } }
    )
  }
})
