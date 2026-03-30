import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  try {
    const body = await req.json()
    const record = body.record

    if (!record) {
      return new Response(JSON.stringify({ error: "No record in payload" }), { status: 400 })
    }

    const resendApiKey = Deno.env.get('RESEND_API_KEY')!
    const toEmail = Deno.env.get('DEV_EMAIL') ?? 'contact@tru-resolve.com'

    const typeLabel: Record<string, string> = {
      bug: '🐛 Bug Report',
      feature: '💡 Feature Request',
      contact: '✉️ Contact',
    }

    const subject = `[TruBrief] ${typeLabel[record.type] ?? record.type ?? 'Feedback'}`

    const screenshotLine = record.screenshot_url
      ? `<p><strong>Screenshot:</strong> <a href="${record.screenshot_url}">${record.screenshot_url}</a></p>`
      : ''

    const html = `
      <div style="font-family:sans-serif;max-width:560px;margin:0 auto;background:#111;color:#fff;border-radius:12px;padding:28px;border:1px solid #333">
        <div style="display:flex;align-items:center;margin-bottom:20px">
          <div style="background:#FF6200;width:36px;height:36px;border-radius:8px;display:inline-flex;align-items:center;justify-content:center;font-size:18px;margin-right:12px">📨</div>
          <h2 style="margin:0;color:#FF6200;font-size:20px">TruBrief Feedback</h2>
        </div>
        <table style="width:100%;border-collapse:collapse;font-size:14px">
          <tr>
            <td style="color:#aaa;padding:6px 0;width:90px"><strong>Type</strong></td>
            <td style="color:#fff">${typeLabel[record.type] ?? record.type ?? '—'}</td>
          </tr>
          <tr>
            <td style="color:#aaa;padding:6px 0"><strong>From</strong></td>
            <td style="color:#fff">${record.user_email ?? 'Unknown'}</td>
          </tr>
          <tr>
            <td style="color:#aaa;padding:6px 0"><strong>User ID</strong></td>
            <td style="color:#999;font-size:12px">${record.user_id ?? '—'}</td>
          </tr>
          <tr>
            <td style="color:#aaa;padding:6px 0"><strong>Submitted</strong></td>
            <td style="color:#fff">${new Date(record.created_at).toLocaleString('en-US', { timeZone: 'America/New_York' })} ET</td>
          </tr>
        </table>
        <div style="margin-top:20px;background:#1C1C1E;border-radius:10px;padding:16px;border:1px solid #333">
          <p style="color:#aaa;font-size:12px;margin:0 0 8px 0;text-transform:uppercase;letter-spacing:0.8px">Message</p>
          <p style="margin:0;color:#fff;font-size:15px;line-height:1.6;white-space:pre-wrap">${record.message ?? ''}</p>
        </div>
        ${screenshotLine}
        <p style="margin-top:24px;color:#555;font-size:11px;text-align:center">Sent automatically by TruBrief · Tru-Resolve LLC</p>
      </div>
    `

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'TruBrief <noreply@tru-resolve.com>',
        to: [toEmail],
        subject,
        html,
      }),
    })

    const resBody = await res.json()

    if (!res.ok) {
      console.error('Resend error:', resBody)
      return new Response(JSON.stringify({ error: resBody }), { status: 500 })
    }

    console.log('Email sent:', resBody.id)
    return new Response(JSON.stringify({ success: true, id: resBody.id }), { status: 200 })

  } catch (e) {
    console.error('Function error:', e.message)
    return new Response(JSON.stringify({ error: e.message }), { status: 500 })
  }
})
