# TRUBRIEF MEMORY FILE
> Read this file at the start of every session. User will say "open tru brief" to load context.

---

## PROJECT OVERVIEW
- **App name:** TruBrief
- **Company:** Tru-Resolve LLC
- **Project path:** `D:\Tru-Developer\trubrief_app`
- **Main file:** `lib/main.dart` (single-file Flutter app, ~2750 lines)
- **Backend:** Supabase (PostgreSQL)
- **Platform:** Android (primary), iOS planned
- **Git repo:** `D:\Tru-Developer\trubrief_app\.git`
- **Backup method:** `git add -A && git commit -m "checkpoint"` — tell user commit hash to revert

---

## TECH STACK
- Flutter / Dart
- Supabase (auth, DB, preferences)
- `flutter_inappwebview` v6.1.5 (in-app browser)
- `geolocator` + `geocoding` (GPS location for Local Brief)
- RSS feeds via Supabase edge functions or direct fetch

---

## DATABASE TABLES (Supabase)
- **`trl_categories`** — columns: `name`, `display_order`, `is_virtual`
- **`trl_sources`** — columns: `id`, `name`, `category`, `url`, `type` (='rss'), `requires_subscription`, `created_at`, `is_active`, `is_featured`
- **`trl_user_preferences`** — stores per-user settings (selected categories, sources, location)
- **`trl_articles`** — cached articles, has `source_id` FK -> `trl_sources.id`

### Key DB notes
- `trl_sources.type` is NOT NULL — always include `'rss'` when inserting
- `trl_sources.url` has a unique constraint
- Foreign key `trl_articles_source_id_fkey` prevents deleting sources that have articles
- Location fields on `trl_user_preferences`: `city`, `state` (NOT `zip_code` — use city/state)

---

## CATEGORIES IN DB (as of last session)

| Category | display_order | Notes |
|---|---|---|
| Tru Brief | 0 | Virtual/pinned, always first |
| Local Brief | 20 | GPS-based Google News RSS |
| National Brief | 30 | |
| World Brief | 40 | |
| Tech Brief | 50 | Fixed: was duplicated as "Tech" |
| Science Brief | 60 | |
| Business Brief | 70 | |
| Finance Brief | 80 | |
| Health Brief | 90 | |
| Lifestyle Brief | 100 | |
| Travel Brief | 110 | |
| Entertainment Brief | 120 | |
| Nature Brief | 130 | |
| Food Brief | 130 | |
| Pet Brief | 140 | |
| Home Brief | 150 | |
| Sports Brief | 10 | Added this session |
| Space Brief | ~11 | Added this session |
| Weather Brief | 12 | Added this session |
| Politics Brief | ~13 | Added this session |
| Gaming Brief | ~14 | Added this session |
| Crypto Brief | 15 | Added this session |
| Weekly Top | 10 | Virtual |

---

## SOURCES SUMMARY
- Each non-virtual category has ~10 sources
- **Top 3 free sources** auto-selected by default
- **Subscription sources** shown at bottom with lock icon
- Space Brief: NASA, Space.com, Universe Today (top 3 free); SpaceNews, Sky & Telescope, The Planetary Society, Astronomy Magazine; Nature Astronomy, Science Alert (sub)
- Space.com was moved FROM Science Brief TO Space Brief
- Mashable was moved to Tech Brief (was under "Tech")
- Duplicate "Ars Technica" and "ZDNet" under old "Tech" category were deleted

---

## FEATURES IMPLEMENTED

### Article Feed
- RSS feed fetching from Supabase
- **Deduplication grouping** (Jaccard similarity, threshold 0.25, intersection >= 2):
  - Groups similar articles under one card
  - Shows "Reported by X sources >" orange pill chip
  - Tapping opens bottom sheet listing all sources with individual links
  - Bottom sheet has AI upsell: "Get an AI-combined summary of all sources — subscribe to TruBrief AI"
- **Image display:** articles show thumbnail if available; Local Brief images scraped from Google News
- **Interleaved sources:** articles interleaved so same source doesn't dominate feed

### Local Brief
- Uses GPS (exact location) or zip code
- Google News RSS URL: `https://news.google.com/rss/search?q={city}+{state}+local+news&hl=en-US&gl=US&ceid=US:en`
- Shows city/state label at top of feed
- Location set in Settings -> Location Settings

### Article Reader
- In-app browser (InAppWebView)
- **Paywall detection:** checks for paywall indicators; shows "Article Unavailable" screen with login option
- **Geo-restriction detection:** detects region-locked content (e.g. BBC iPlayer) — shows unavailable screen
- **Region-restricted articles filtered from feed** at fetch time
- Ad blocking via content blockers
- "Subscribe for AI Summary" banner at top (for non-premium users)

### Settings Screen (MAJOR REFACTOR - this session)
- **Location Settings** section (GPS or zip code)
- **My Feed Tabs** section:
  - ReorderableListView of active categories
  - Drag handles to reorder
  - Tru Brief pinned at top (push_pin icon)
  - Tap any row -> opens CategoryDetailScreen
  - No X remove button (removed to prevent accidents)
- **All Categories Grid** section:
  - 2-column grid cards
  - Shows category name + active source count
  - Orange = in feed; dark = not in feed
  - Tap -> opens CategoryDetailScreen
- **CategoryDetailScreen** (new dedicated screen per category):
  - "Show in feed" toggle at top (only way to add/remove from feed)
  - Top 3 News Sources (free, auto-selected)
  - More Sources (remaining free)
  - Sources Require Account (subscription, lock icon)
  - Login button per source (opens in-app browser)

---

## MONETIZATION PLAN
- **Free tier:** RSS feed access, basic features
- **Paid/Premium (TruBrief AI):** AI-generated article summaries
- AI upsell shown in: article reader banner + multi-source bottom sheet
- AI integration NOT yet implemented — planned for next phase

---

## KNOWN ISSUES / TODO
- [ ] Local Brief images: Google News often returns Google logo instead of article thumbnail — needs og:image scraping
- [ ] Weather Brief and Politics Brief RSS URLs need live verification
- [ ] No push notifications yet
- [ ] iOS not tested
- [ ] AI summary feature not built yet — OpenAI or similar, paid users only


---

## IMPORTANT CODE LOCATIONS (lib/main.dart)
- `_deduplicateByTopic()` — Jaccard dedup/grouping (~line 440)
- `_showSourcesBottomSheet()` — multi-source modal with AI upsell (~line 748)
- `SettingsScreen` class — full settings UI
- `CategoryDetailScreen` class — per-category source management (~line 2152)
- `ArticleReaderScreen` class — in-app browser + paywall detection (~line 2330)
- `_buildSourceTile()` — source checkbox row (~line 2113)
- Local Brief fetch uses `_userCity`, `_userState` to build Google News RSS URL

---

## GIT CHECKPOINTS
| Commit | Description |
|---|---|
| initial | First commit, 145 files |
| 87abdf3 | Settings UI refactor: My Feed Tabs + Grid + CategoryDetailScreen |

---

## USER PREFERENCES / DIRECTION
- Dark theme: black (#000000) background, orange (#FF6200) accent
- Keep UI clean — no redundant buttons or clutter
- Categories named "X Brief"
- Top 3 free sources auto-selected; subscription sources at bottom
- Article deduplication: group by topic, show "Reported by X sources", never hide/discard
- AI features reserved for paid subscribers
- User runs SQL directly in Supabase SQL editor — always provide exact SQL + order to run
- When DB changes needed: tell user the exact SQL statements clearly
