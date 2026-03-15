import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    // 1. Parse the Webhook payload
    const body = await req.json()
    const record = body.record // Webhooks wrap the data in a 'record' object

    if (!record || !record.id) {
      throw new Error("No record found in the webhook payload.")
    }

    console.log(`Processing article: ${record.title}`)

    // 2. Initialize Supabase Client
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // 3. Request summary from xAI (Grok)
    const response = await fetch('https://api.x.ai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('GROK_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: "grok-2-latest",
        messages: [
          { 
            role: "user", 
            content: `Summarize this news title in exactly 2 sentences: ${record.title}` 
          }
        ]
      })
    })

    const data = await response.json()

    // 4. Handle API Errors (Prevents silent 500s)
    if (!data.choices || data.choices.length === 0) {
      console.error("xAI Error Response:", data)
      throw new Error(data.error?.message || "Grok failed to return a summary.")
    }

    const summary = data.choices[0].message.content

    // 5. Try to fetch a thumbnail if it doesn't already have one
    let imageUrl = record.image_url;
    if (!imageUrl && record.original_url) {
      try {
        console.log(`Fetching metadata for: ${record.original_url}`);
        // Quick extraction of metadata using a simple regex on the HTML
        // Alternatively, use an external service or a library
        const metaRes = await fetch(record.original_url);
        const html = await metaRes.text();
        
        // Extract og:image
        const ogMatch = html.match(/<meta[^>]*property="og:image"[^>]*content="([^"]*)"/i) ||
                        html.match(/<meta[^>]*content="([^"]*)"[^>]*property="og:image"/i);
        
        if (ogMatch && ogMatch[1]) {
          imageUrl = ogMatch[1];
          console.log(`Found image: ${imageUrl}`);
        }
      } catch (err) {
        console.error("Image scraping error:", err.message);
      }
    }

    // 6. Update the Database
    const { error: updateError } = await supabase
      .from('trl_articles')
      .update({ 
        summary_brief: summary,
        image_url: imageUrl
      })
      .eq('id', record.id)

    if (updateError) throw updateError

    return new Response(
      JSON.stringify({ message: "Success", summary }), 
      { status: 200, headers: { "Content-Type": "application/json" } }
    )

  } catch (e) {
    // 6. Detailed logging for the Dashboard
    console.error("Function Error:", e.message)
    return new Response(
      JSON.stringify({ error: e.message }), 
      { status: 500, headers: { "Content-Type": "application/json" } }
    )
  }
})