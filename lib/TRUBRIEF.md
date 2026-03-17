# TRUBRIEF MEMORY FILE
> Read this file at the start of every session. User will say "open tru brief" to load context.

---

## PROJECT OVERVIEW
- **App name:** TruBrief
- **Company:** Tru-Resolve LLC
- **Project path:** `D:\Tru-Developer\trubrief_app`
- **Main file:** `lib/main.dart` (single-file Flutter app, ~3650 lines)
- **Backend:** Supabase (PostgreSQL)
- **Platform:** Android (primary), iOS planned
- **Git repo:** `D:\Tru-Developer\trubrief_app\.git`
- **GitHub remote:** `https://github.com/jer-rar/Tru-Brief.git` (private)
- **Backup method:** `git add -A && git commit -m "checkpoint" && git push origin main`

---

## TECH STACK
- Flutter / Dart
- Supabase (auth, DB, preferences)
- `flutter_inappwebview` v6.1.5 (in-app browser)
- `geolocator` + `geocoding` (GPS location for Local Brief)
- `url_launcher` (open external URLs, update download links)
- RSS feeds fetched directly via `http` package

---

## DATABASE TABLES (Supabase)
- **`trl_categories`** — columns: `name`, `display_order`, `is_virtual`
- **`trl_sources`** — columns: `id`, `name`, `category`, `url`, `type` (='rss'), `requires_subscription`, `is_preset`, `is_custom`, `created_at`, `city`, `state`
- **`trl_user_preferences`** — stores per-user settings (selected categories, sources, location, hidden tabs)
- **`trl_articles`** — cached articles, has `source_id` FK -> `trl_sources.id`
- **`trl_app_version`** — OTA update control (see Alpha Distribution section)

### Key DB notes
- `trl_sources.type` is NOT NULL — always include `'rss'` when inserting
- `trl_sources.url` has a unique constraint — use `ON CONFLICT (url) DO NOTHING`
- `trl_sources` does NOT have `is_active` or `is_featured` columns — use `is_preset` instead
- Foreign key `trl_articles_source_id_fkey` prevents deleting sources that have articles
- Location fields on `trl_user_preferences`: `city`, `state`, `county` (NOT `zip_code`)
- `hidden_tabs TEXT[] DEFAULT '{}'` — categories whose tab chips are hidden from main tab bar

### SQL migrations run so far
```sql
-- County field for GPS location
ALTER TABLE trl_user_preferences ADD COLUMN IF NOT EXISTS county TEXT;

-- Hidden tabs feature
ALTER TABLE trl_user_preferences ADD COLUMN IF NOT EXISTS hidden_tabs TEXT[] DEFAULT '{}';

-- OTA update table
CREATE TABLE trl_app_version (
  id serial PRIMARY KEY,
  version_name TEXT NOT NULL,
  version_code INT NOT NULL,
  download_url TEXT NOT NULL,
  release_notes TEXT,
  force_update BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO trl_app_version (version_name, version_code, download_url, release_notes)
VALUES ('1.0.0', 1, '', 'Initial alpha');
```

---

## ALPHA DISTRIBUTION (current state)

### APK Details
- **applicationId:** `com.truresolve.trubrief`
- **App label:** `TruBrief`
- **Current version:** `1.0.0` (versionCode: 1) — defined as `_currentVersionCode = 1` in `_AppState`
- **Signed with:** debug key (fine for alpha, NOT for Play Store)
- **APK location:** `build/app/outputs/flutter-apk/app-release.apk` (52.1 MB)
- **Build command:** `flutter build apk --release`

### OTA Update System
- On app launch, `_checkForUpdate()` queries `trl_app_version` for latest row
- If `version_code > _currentVersionCode`, shows an update dialog
- `force_update = true` makes dialog non-dismissible
- Dialog has **Download** button that opens `download_url` in external browser
- **To push an update:** build new APK → host it → insert new row in `trl_app_version`

### GitHub Releases
- Private repo: `https://github.com/jer-rar/Tru-Brief`
- Upload APK as a release asset → copy direct download URL → put in `trl_app_version.download_url`

### ⚠️ NEXT SESSION — Play Store Setup
When user says "open tru brief" next session, start with:
1. Generate a release keystore: `keytool -genkey -v -keystore trubrief-release.jks -keyalias trubrief -keyalg RSA -keysize 2048 -validity 10000`
2. Configure `android/app/build.gradle.kts` with signing config
3. Build AAB: `flutter build appbundle --release`
4. Upload to Google Play Console (Internal Testing track first)

---

## CATEGORIES IN DB

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
| Astrology Brief | 160 | Added this session |
| Exploration Brief | 170 | Added this session |
| Wildlife Brief | 180 | Added this session |
| Weekly Top | 10 | Virtual |

### SQL to add Astrology, Exploration, Wildlife (use correct columns: no is_active/is_featured)
```sql
-- Astrology Brief
INSERT INTO trl_categories (name, display_order, is_virtual)
VALUES ('Astrology Brief', 160, false) ON CONFLICT DO NOTHING;

INSERT INTO trl_sources (name, category, url, type, requires_subscription, is_preset) VALUES
('Astrology Zone', 'Astrology Brief', 'https://www.astrologyzone.com/feed/', 'rss', false, true),
('Cafe Astrology', 'Astrology Brief', 'https://cafeastrology.com/feed/', 'rss', false, true),
('AstroStyle', 'Astrology Brief', 'https://astrostyle.com/feed/', 'rss', false, true),
('Chani Nicholas', 'Astrology Brief', 'https://chaninicholas.com/feed/', 'rss', false, false),
('ElsaElsa', 'Astrology Brief', 'https://elsaelsa.com/feed/', 'rss', false, false),
('The Astro Codex', 'Astrology Brief', 'https://theastrocodex.com/feed/', 'rss', false, false)
ON CONFLICT (url) DO NOTHING;

-- Exploration Brief
INSERT INTO trl_categories (name, display_order, is_virtual)
VALUES ('Exploration Brief', 170, false) ON CONFLICT DO NOTHING;

INSERT INTO trl_sources (name, category, url, type, requires_subscription, is_preset) VALUES
('Atlas Obscura', 'Exploration Brief', 'https://www.atlasobscura.com/feeds/latest', 'rss', false, true),
('Adventure Journal', 'Exploration Brief', 'https://www.adventure-journal.com/feed/', 'rss', false, true),
('Outside Online', 'Exploration Brief', 'https://www.outsideonline.com/feed/', 'rss', false, true),
('Expedition Portal', 'Exploration Brief', 'https://expeditionportal.com/feed/', 'rss', false, false),
('Explorers Web', 'Exploration Brief', 'https://www.explorersweb.com/feed/', 'rss', false, false),
('Condé Nast Traveler', 'Exploration Brief', 'https://www.cntraveler.com/feed/rss', 'rss', false, false),
('Lonely Planet', 'Exploration Brief', 'https://www.lonelyplanet.com/news/feed/', 'rss', false, false),
('National Geographic Travel', 'Exploration Brief', 'https://www.nationalgeographic.com/travel/feed/', 'rss', true, false)
ON CONFLICT (url) DO NOTHING;

-- Wildlife Brief
INSERT INTO trl_categories (name, display_order, is_virtual)
VALUES ('Wildlife Brief', 180, false) ON CONFLICT DO NOTHING;

INSERT INTO trl_sources (name, category, url, type, requires_subscription, is_preset) VALUES
('National Geographic Animals', 'Wildlife Brief', 'https://www.nationalgeographic.com/animals/feed/', 'rss', false, true),
('Mongabay', 'Wildlife Brief', 'https://mongabay.com/feed/', 'rss', false, true),
('Discover Wildlife', 'Wildlife Brief', 'https://www.discoverwildlife.com/feed/', 'rss', false, true),
('Wildlife Conservation Society', 'Wildlife Brief', 'https://newsroom.wcs.org/News-Releases.aspx?feed=rss', 'rss', false, false),
('WWF News', 'Wildlife Brief', 'https://www.worldwildlife.org/blog.rss', 'rss', false, false),
('Defenders of Wildlife', 'Wildlife Brief', 'https://defenders.org/feed/', 'rss', false, false),
('African Wildlife Foundation', 'Wildlife Brief', 'https://www.awf.org/blog/feed', 'rss', false, false),
('The Wildlife Society', 'Wildlife Brief', 'https://wildlife.org/feed/', 'rss', false, false),
('iNaturalist Blog', 'Wildlife Brief', 'https://www.inaturalist.org/blog.atom', 'rss', false, false),
('Nature.com Wildlife', 'Wildlife Brief', 'https://www.nature.com/subjects/animal-behaviour.rss', 'rss', false, false)
ON CONFLICT (url) DO NOTHING;
```

---

## FEATURES IMPLEMENTED

### Article Feed
- RSS feed fetching from Supabase
- **Deduplication grouping** (Jaccard similarity, threshold 0.25, intersection >= 2)
- **Image display:** articles show thumbnail if available
- **Interleaved sources:** articles interleaved so same source doesn't dominate feed

### Local Brief
- Uses GPS (exact location) or postal code
- **Multi-query parallel fetch** (3 simultaneous Google News RSS queries):
  - Query 1: Exact city + state
  - Query 2: County-level — covers nearby cities
  - Query 3: County name without "County" — surfaces major city (e.g., Tampa for Hillsborough)
- Results merged, deduplicated by URL, sorted newest-first
- Time window: 72h
- County stored in `trl_user_preferences.county`

### Settings Screen
- Three collapsible sections: Location Settings, My Feed, Available Feeds
- **Available Feeds grid:** 2-column, alphabetically sorted, eye open/closed icons
  - Eye icon (right sliver): quick-toggle tab visibility without opening the detail screen
  - Unselected feed: tapping eye instantly quick-adds with top 3 free sources
  - Selected feed: tapping eye toggles tab visibility
- **CategoryDetailScreen** per category:
  - Toggle 1: "Show in feed" — independent
  - Toggle 2: "Display Tab" — independent (does NOT auto-off when Show in feed is turned off)

### Main Tab Bar
- Shows first 3 visible tabs only
- **Grid icon (⊞)** to the right of 3rd tab → opens `DraggableScrollableSheet` overlay
- Overlay shows "My Feeds" grid of remaining tabs (4+), all orange-tinted
- **Close button** (top right) or tap outside dismisses overlay (`isDismissible: true`)
- Tapping a feed in overlay navigates to it and closes overlay

### Display Tab Feature
- `hidden_tabs TEXT[]` in `trl_user_preferences`
- Two independent toggles per category in CategoryDetailScreen
- Available Feeds grid eye icon reflects hidden state

### OTA Update Checker
- `_checkForUpdate()` called in `initState` via `addPostFrameCallback`
- Checks `trl_app_version` table, compares `version_code` to `_currentVersionCode = 1`
- Shows update dialog with optional "Later" button and "Download" button

---

## MONETIZATION PLAN
- **Free tier:** RSS feed access, basic features
- **Paid/Premium (TruBrief AI):** AI-generated article summaries
- AI upsell shown in: article reader banner + multi-source bottom sheet
- AI integration NOT yet implemented — planned for next phase

---

## ROADMAP

### IMMEDIATE NEXT — Play Store Release
- [ ] Generate release keystore (`trubrief-release.jks`) — store safely, NEVER commit to git
- [ ] Configure `android/app/build.gradle.kts` with signingConfigs for release
- [ ] Build AAB: `flutter build appbundle --release`
- [ ] Create app in Google Play Console
- [ ] Upload to Internal Testing track
- [ ] Fill store listing: icon (512x512), feature graphic (1024x500), screenshots, privacy policy

### Phase 1 — Category Expansion
- [ ] **Astrology Brief** SQL (above) — run when ready
- [ ] **Exploration Brief** SQL (above) — run when ready
- [ ] **Wildlife Brief** SQL (above) — run when ready
- [ ] **Pet Brief subcategories**: Dogs, Cats, Reptiles, Aquarium, Small Animals
- [ ] **Gaming Brief subcategories**: Video Games, Tabletop (distinguish from gambling)

### Phase 2 — International Support
- [ ] National News auto-adapts to user's country based on postal code
- [ ] Fallback for invalid postal codes
- [ ] Support multi-format postal codes (Canada, UK)

### Phase 3 — Quality / QA
- [ ] Blank tabs root cause fix
- [ ] Verify all RSS source URLs are live
- [ ] Cross-reference DB sources vs. expected list

### Phase 4 — AI / Monetization
- [ ] AI summary feature (OpenAI integration, paid users only)
- [ ] Push notifications
- [ ] iOS testing

---

## KNOWN ISSUES
- [ ] Local Brief images: Google News returns Google logo — needs og:image scraping
- [ ] Weather Brief and Politics Brief RSS URLs need live verification
- [ ] International news: country-aware API not yet implemented
- [ ] `trubrief-release.jks` keystore not yet created (needed for Play Store)

---

## IMPORTANT CODE LOCATIONS (lib/main.dart)
- `_currentVersionCode` — static const int, increment each release (~line 87)
- `_checkForUpdate()` — OTA update checker (~line 89)
- `_fetchGoogleNewsLocal()` — multi-query parallel Local Brief fetch (~line 365)
- `_fetchGoogleNewsQuery()` — single RSS query helper (~line 417)
- `_deduplicateByTopic()` — Jaccard dedup/grouping (~line 495)
- `_showSourcesBottomSheet()` — multi-source modal with AI upsell (~line 800)
- `SourceSettingsScreen` class — full settings UI (~line 1480)
- `CategoryDetailScreen` class — per-category source management + two independent toggles (~line 3030)
- `ArticleReaderScreen` class — in-app browser + paywall detection (~line 3380)
- `_hiddenTabs` — Set of categories hidden from tab bar

---

## GIT CHECKPOINTS
| Commit | Description |
|---|---|
| initial | First commit |
| 87abdf3 | Settings UI refactor |
| 5fb9509 | Newsletters screen, collapsible settings, Tech Brief cleanup |
| 9670b68 | Local Brief multi-query parallel fetch |
| 9d35669 | Postal code rename, display tab, hidden tabs, TRUBRIEF.md overhaul |
| 1764bbf | Fix overlay dismiss (removed GestureDetector wrapper) |
| 61cf59c | applicationId → com.truresolve.trubrief, OTA update checker, alpha APK built |

---

## USER PREFERENCES / DIRECTION
- Dark theme: black (#000000) background, orange (#FF6200) accent
- Keep UI clean — no redundant buttons or clutter
- Categories named "X Brief"
- Top 3 free sources auto-selected; subscription sources at bottom
- Article deduplication: group by topic, show "Reported by X sources", never hide/discard
- AI features reserved for paid subscribers
- User runs SQL directly in Supabase SQL editor — always provide exact SQL
- `trl_sources` correct columns: `name, category, url, type, requires_subscription, is_preset` (NO `is_active`, NO `is_featured`)
- International inclusivity: use "Postal Code" not "Zip Code" in UI
- **NEVER commit the release keystore file** (`trubrief-release.jks`) to git
