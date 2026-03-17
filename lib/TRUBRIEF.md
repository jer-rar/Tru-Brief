# TRUBRIEF MEMORY FILE
> Read this file at the start of every session. User will say "open tru brief" to load context.

---

## PROJECT OVERVIEW
- **App name:** TruBrief
- **Company:** Tru-Resolve LLC
- **Project path:** `D:\Tru-Developer\trubrief_app`
- **Main file:** `lib/main.dart` (single-file Flutter app, ~3400 lines)
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
- **`trl_sources`** — columns: `id`, `name`, `category`, `url`, `type` (='rss'), `requires_subscription`, `is_preset`, `is_custom`, `created_at`, `city`, `state`
- **`trl_user_preferences`** — stores per-user settings (selected categories, sources, location, hidden tabs)
- **`trl_articles`** — cached articles, has `source_id` FK -> `trl_sources.id`

### Key DB notes
- `trl_sources.type` is NOT NULL — always include `'rss'` when inserting
- `trl_sources.url` has a unique constraint
- Foreign key `trl_articles_source_id_fkey` prevents deleting sources that have articles
- Location fields on `trl_user_preferences`: `city`, `state`, `county` (NOT `zip_code` — use city/state/county)
- `hidden_tabs TEXT[] DEFAULT '{}'` — categories whose tab chips are hidden from main tab bar

### SQL migrations run so far
```sql
-- County field for GPS location
ALTER TABLE trl_user_preferences ADD COLUMN IF NOT EXISTS county TEXT;

-- Hidden tabs feature
ALTER TABLE trl_user_preferences ADD COLUMN IF NOT EXISTS hidden_tabs TEXT[] DEFAULT '{}';
```

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
| Sports Brief | 10 | |
| Space Brief | ~11 | |
| Weather Brief | 12 | |
| Politics Brief | ~13 | |
| Gaming Brief | ~14 | |
| Crypto Brief | 15 | |
| Astrology Brief | 160 | NEW — planned |
| Exploration Brief | 170 | NEW — planned |
| Weekly Top | 10 | Virtual |

### SQL to add new categories (run in Supabase SQL editor)
```sql
-- Astrology Brief
INSERT INTO trl_categories (name, display_order, is_virtual)
VALUES ('Astrology Brief', 160, false) ON CONFLICT DO NOTHING;

INSERT INTO trl_sources (name, category, url, type, requires_subscription, is_active, is_featured) VALUES
('Astrology Zone', 'Astrology Brief', 'https://www.astrologyzone.com/feed/', 'rss', false, true, true),
('Cafe Astrology', 'Astrology Brief', 'https://cafeastrology.com/feed/', 'rss', false, true, true),
('AstroStyle', 'Astrology Brief', 'https://astrostyle.com/feed/', 'rss', false, true, true),
('Chani Nicholas', 'Astrology Brief', 'https://chaninicholas.com/feed/', 'rss', false, true, false),
('ElsaElsa', 'Astrology Brief', 'https://elsaelsa.com/feed/', 'rss', false, true, false),
('The Astro Codex', 'Astrology Brief', 'https://theastrocodex.com/feed/', 'rss', false, true, false)
ON CONFLICT (url) DO NOTHING;

-- Exploration Brief
INSERT INTO trl_categories (name, display_order, is_virtual)
VALUES ('Exploration Brief', 170, false) ON CONFLICT DO NOTHING;

INSERT INTO trl_sources (name, category, url, type, requires_subscription, is_active, is_featured) VALUES
('Atlas Obscura', 'Exploration Brief', 'https://www.atlasobscura.com/feeds/latest', 'rss', false, true, true),
('Adventure Journal', 'Exploration Brief', 'https://www.adventure-journal.com/feed/', 'rss', false, true, true),
('Outside Online', 'Exploration Brief', 'https://www.outsideonline.com/feed/', 'rss', false, true, true),
('Expedition Portal', 'Exploration Brief', 'https://expeditionportal.com/feed/', 'rss', false, true, false),
('Explorers Web', 'Exploration Brief', 'https://www.explorersweb.com/feed/', 'rss', false, true, false),
('Condé Nast Traveler', 'Exploration Brief', 'https://www.cntraveler.com/feed/rss', 'rss', false, true, false),
('Lonely Planet', 'Exploration Brief', 'https://www.lonelyplanet.com/news/feed/', 'rss', false, true, false),
('National Geographic', 'Exploration Brief', 'https://www.nationalgeographic.com/travel/feed/', 'rss', true, true, false)
ON CONFLICT (url) DO NOTHING;
```

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
- Uses GPS (exact location) or postal code
- **Multi-query parallel fetch** (3 simultaneous RSS queries):
  - Query 1: Exact city + state (`"Riverview" "Florida" local news`)
  - Query 2: County-level (`"Hillsborough County" "Florida" local news`) — covers nearby cities
  - Query 3: County name without "County" (`"Hillsborough" "Florida" news`) — surfaces major city (Tampa)
- Results merged, deduplicated by URL, sorted newest-first
- Time window: 72h (extended from 48h for small cities)
- County stored in `trl_user_preferences.county` — set when GPS is used
- Google News RSS URL template: `https://news.google.com/rss/search?q=when:72h+{query}&hl=en-US&gl=US&ceid=US:en`
- Shows city/state label at top of feed
- Location set in Settings -> Location Settings

### Article Reader
- In-app browser (InAppWebView)
- **Paywall detection:** checks for paywall indicators; shows "Article Unavailable" screen with login option
- **Geo-restriction detection:** detects region-locked content (e.g. BBC iPlayer) — shows unavailable screen
- **Region-restricted articles filtered from feed** at fetch time
- Ad blocking via content blockers
- "Subscribe for AI Summary" banner at top (for non-premium users)

### Settings Screen
- All three sections are **polished collapsible buttons** (collapsed by default, animated chevron):
  - **Location Settings** — green-tinted, shows current location status in subtitle, GPS/postal code editor expands below
  - **My Feed** — orange-tinted gradient, ReorderableListView of active categories
  - **Available Feeds** — blue-tinted, 2-column grid of all categories
- **Newsletters** button (purple) navigates to NewslettersScreen
- **CategoryDetailScreen** (per category):
  - Toggle 1: "Show in feed" — adds category to Tru Brief aggregated feed + makes tab visible
  - Toggle 2: "Display Tab" — controls whether the category's tab chip shows in the main tab bar (independent of feed inclusion)

### Display Tab Feature (NEW)
- Each category has two independent controls:
  - **Show in feed**: sources included in Tru Brief combined feed
  - **Display Tab**: tab chip visible in horizontal tab bar on main screen
- `hidden_tabs TEXT[]` column in `trl_user_preferences` stores categories whose tabs are hidden
- Allows users to include sources in Tru Brief without cluttering the tab bar

### Newsletters Screen
- Accessible from Settings via purple "Newsletters" button
- **How it works** explainer card with 6-step overview
- **My Newsletters** section — shows added newsletters with delete
- **Popular Newsletters** list (12 curated: Morning Brew, TLDR, The Hustle, 1440, Axios AM, The Pour Over, NextDraft, Milk Road, Dense Discovery, Politico Playbook, The Rundown AI, Finimize)
- Tapping a curated newsletter opens bottom sheet with:
  - 4-step guided instructions (Kill the Newsletter flow)
  - "Step 1 — Open Kill the Newsletter" button (purple, opens browser)
  - "Step 2 — Go to [Newsletter] to Subscribe" button (opens newsletter signup)
  - Clearly labels EMAIL ADDRESS (1st field) vs ATOM FEED URL (2nd field)
  - RSS URL input + "Add to Tru Brief" button
- **Add Custom Newsletter** button at bottom for unlisted newsletters
- Saved to `trl_sources` with `category = 'Tru Brief'` and `is_custom = true`
- Requires `is_custom BOOLEAN DEFAULT false` column on `trl_sources` (already added)

---

## MONETIZATION PLAN
- **Free tier:** RSS feed access, basic features
- **Paid/Premium (TruBrief AI):** AI-generated article summaries
- AI upsell shown in: article reader banner + multi-source bottom sheet
- AI integration NOT yet implemented — planned for next phase

---

## ROADMAP (from planning session)

### Phase 1 — Category Expansion
- [ ] **Astrology Brief** — horoscopes, zodiac content (SQL above)
- [ ] **Exploration Brief** — adventure, travel, discovery (SQL above)
- [ ] **Pet Brief subcategories**: Dogs, Cats, Reptiles, Aquarium (Fish), Small Animals
- [ ] **Gaming Brief subcategories**: Video Games, Tabletop Games (distinguish from gambling)

### Phase 2 — International Support
- [ ] Rename "Zip Code" → "Postal Code" globally (for international users) ✅ DONE
- [ ] Show resolved city/region name next to entered postal code ✅ DONE
- [ ] National News auto-adapts to user's country based on postal code (French code → French news)
- [ ] Fallback for invalid postal codes (prompt re-entry or default to IP-based location)
- [ ] Support multi-format postal codes (Canada: A1A 1A1, UK: SW1A 1AA)

### Phase 3 — UX Improvements
- [ ] **Display Tab toggle** in CategoryDetailScreen ✅ DONE
- [ ] Blank tabs root cause fix (ensure content loads on all tabs)
- [ ] Verify all RSS source URLs are live and returning content
- [ ] Cross-reference DB sources vs. expected list (run audit queries)

### Phase 4 — Subcategories
- [ ] Schema changes to support subcategories in DB
- [ ] "All" checkbox for subcategories (default selected; unchecking deselects all)
- [ ] Per-subcategory toggles in category settings

### Phase 5 — Deployment & Monitoring
- [ ] Analytics for category usage, tab visibility, location adoption
- [ ] Push notifications
- [ ] iOS testing
- [ ] AI summary feature (OpenAI integration, paid users only)

---

## KNOWN ISSUES / TODO
- [ ] Local Brief images: Google News often returns Google logo instead of article thumbnail — needs og:image scraping
- [ ] Weather Brief and Politics Brief RSS URLs need live verification
- [ ] No push notifications yet
- [ ] iOS not tested
- [ ] AI summary feature not built yet — OpenAI or similar, paid users only
- [ ] Gizmodo still in Tech Brief — consider replacing with The Register or ExtremeTech
- [ ] The Next Web still in Tech Brief — occasionally runs off-topic content
- [ ] International news: French postal code 38950 showed US news — needs country-aware API

---

## IMPORTANT CODE LOCATIONS (lib/main.dart)
- `_deduplicateByTopic()` — Jaccard dedup/grouping (~line 440)
- `_showSourcesBottomSheet()` — multi-source modal with AI upsell (~line 748)
- `_fetchGoogleNewsLocal()` — multi-query parallel Local Brief fetch (~line 306)
- `_fetchGoogleNewsQuery()` — single RSS query helper (~line 358)
- `SourceSettingsScreen` class — full settings UI (~line 1427)
- `NewslettersScreen` class — newsletters feature (~line 2380)
- `CategoryDetailScreen` class — per-category source management + two toggles (~line 2840)
- `ArticleReaderScreen` class — in-app browser + paywall detection (~line 3020)
- Local Brief fetch uses `_city`, `_state`, `_county` to build parallel Google News RSS queries
- `_hiddenTabs` — Set of categories hidden from tab bar but still active in feed

---

## GIT CHECKPOINTS
| Commit | Description |
|---|---|
| initial | First commit, 145 files |
| 87abdf3 | Settings UI refactor: My Feed Tabs + Grid + CategoryDetailScreen |
| 5fb9509 | Newsletters screen, collapsible settings sections, Tech Brief source cleanup, UI polish |
| 9670b68 | Local Brief multi-query parallel fetch (city + county + metro) |

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
- International inclusivity: use "Postal Code" not "Zip Code" in UI
