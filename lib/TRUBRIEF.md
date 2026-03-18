# TRUBRIEF MEMORY FILE
> Read this file at the start of every session. User will say "review your memory on tru brief" to load context.

---

## PROJECT OVERVIEW
- **App name:** TruBrief
- **Company:** Tru-Resolve LLC
- **Project path:** `D:\Tru-Developer\trubrief_app`
- **Main file:** `lib/main.dart` (single-file Flutter app, ~4150 lines)
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

## DEV ENVIRONMENT
- **Flutter:** `D:\Tru-Developer\flutter\bin\flutter`
- **Android SDK:** `D:\Tru-Developer\AndroidSDK`
- **AVD:** `Medium_Phone_API_36.1` — stored at `D:\Tru-Developer\.android\avd\`
- **AVD config fixes applied:** `hw.ramSize=4096`, `fastboot.forceColdBoot=yes`, `hw.gpu.mode=auto`
- **Emulator launch:** Use Android Studio Device Manager (NOT command line — path env issues)
- **Cold boot takes 3–5 min** on first launch — "Not Responding" title is normal during init
- **Run command:** `flutter run -d emulator-5556` (from `D:\Tru-Developer\trubrief_app`)
- **⚠️ Both emulators have NO internet** — Supabase calls will hang/fail from emulator. Account creation must be done via Supabase dashboard.

## DEV ACCOUNT
- **Email:** `jdr6382@gmail.com`
- **Password:** `Jerd6382!`
- **Auto-filled in debug mode** via `kDebugMode` in `_LoginScreenState` — just tap Sign In
- **Premium SQL** (run in Supabase SQL editor if needed):
```sql
INSERT INTO trl_subscriptions (user_id, status, trial_started_at)
SELECT id, 'active', NOW() FROM auth.users WHERE email = 'jdr6382@gmail.com'
ON CONFLICT (user_id) DO UPDATE SET status = 'active';
```

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

### Auth & Session
- Supabase email/password auth — sessions auto-persist via SharedPreferences
- Alpha testers log in ONCE — session saved, auto-restored on subsequent launches
- No "Remember Me" needed — it's the default Supabase Flutter behavior
- RLS (Row Level Security) should be enabled before production release

### ⚠️ NEXT SESSION — Play Store Setup
When ready for Play Store:
1. Generate a release keystore: `keytool -genkey -v -keystore trubrief-release.jks -keyalias trubrief -keyalg RSA -keysize 2048 -validity 10000`
2. Configure `android/app/build.gradle.kts` with signing config
3. Build AAB: `flutter build appbundle --release`
4. Upload to Google Play Console (Internal Testing track first)

---

## SESSION LOG

### Session 2026-03-18 (first session with auth + emulator setup)
- **Auth system**: Added `_AuthGate`, `LoginScreen` (email/password + signup), persistent Supabase session. Sign out in Settings AppBar.
- **Category feeds fix**: `_selectedSources` filter removed from category tabs. Category tabs show ALL articles; `_selectedSources` only applies to Tru Brief.
- **Tutorial overlay**: 4-step first-time tutorial (`tutorial_seen` in SharedPreferences). Steps: Feed Tabs, Reading Articles, Multiple Sources, Customize.

### Session 2026-03-18 (second session — UI polish + emulator fixes)
- **Emulator fix**: API 36.1 AVD was stuck booting. Fixed by setting `hw.ramSize=4096`, `fastboot.forceColdBoot=yes`, `hw.gpu.mode=auto`. Cold boot takes 3–5 min.
- **New working emulator**: Created second AVD (API 36.0 Pixel 9) running on `emulator-5556`. **Both emulators have no internet** — Supabase calls hang. Use Supabase dashboard to create accounts.
- **Dev account auto-fill**: `kDebugMode` pre-fills `jdr6382@gmail.com` / `Jerd6382!` in LoginScreen. Just tap Sign In.
- **Tutorial redesign**: Full visual overhaul — `Material` wrapper fixes text underlines, orange gradient progress bar at top, gradient icon badge, `AnimatedSwitcher` fade+slide between steps, animated dots (completed = faded orange), gradient Next button with glow + arrow icon.
- **Default tabs changed**: New user default tabs → `['Tru Brief', 'Local Brief', 'Weather Brief']` (was National/World/Food). Updated in 3 locations in code.
- **Grid icon always visible + orange**: Changed `hasMore` from `visibleTabs.length > 3` to `const hasMore = true`. Grid icon styled orange with orange border/tint.
- **Available Feeds tap fix**: Added `behavior: HitTestBehavior.opaque` to `GestureDetector` in Available Feeds grid — cards were only tappable on text pixels, not full card area.
- **Close button orange**: "My Feeds" overlay Close button updated to orange theme.
- **county column**: Run this SQL if not done yet: `ALTER TABLE trl_user_preferences ADD COLUMN IF NOT EXISTS county TEXT;`

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
| Astrology Brief | 160 | |
| Exploration Brief | 170 | |
| Wildlife Brief | 180 | |
| Weekly Top | 10 | Virtual |

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
  - `HitTestBehavior.opaque` on card GestureDetector — full card area tappable
- **CategoryDetailScreen** per category:
  - Toggle 1: "Show in feed" — independent
  - Toggle 2: "Display Tab" — independent (does NOT auto-off when Show in feed is turned off)

### Main Tab Bar
- Shows first 3 visible tabs only
- **Grid icon (⊞)** always visible, orange-themed → opens `DraggableScrollableSheet` overlay
- Overlay shows "My Feeds" grid of all tabs, Close button orange-themed
- Tapping a feed in overlay navigates to it and closes overlay
- Default visible tabs for new users: `Tru Brief`, `Local Brief`, `Weather Brief`

### Tutorial Overlay
- 4-step first-launch tutorial (SharedPreferences key: `tutorial_seen`)
- Orange gradient progress bar, gradient icon badge, AnimatedSwitcher transitions
- Dots animate: active=orange, past=faded orange, future=white12
- Next button: gradient + glow shadow + arrow icon; last step shows "Get Started"
- X dismiss button closes and marks seen

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
- [ ] **Pet Brief subcategories**: Dogs, Cats, Reptiles, Aquarium, Small Animals
- [ ] **Gaming Brief subcategories**: Video Games, Tabletop (distinguish from gambling)

### Phase 2 — International Support
- [ ] National News auto-adapts to user's country based on postal code
- [ ] Fallback for invalid postal codes
- [ ] Support multi-format postal codes (Canada, UK)

### Phase 3 — Quality / QA
- [ ] Fix emulator internet (Windows Firewall — allow `qemu-system-x86_64.exe` private+public)
- [ ] Blank tabs root cause fix
- [ ] Verify all RSS source URLs are live
- [ ] Cross-reference DB sources vs. expected list
- [ ] Enable RLS on Supabase tables before production

### Phase 4 — AI / Monetization
- [ ] AI summary feature (OpenAI integration, paid users only)
- [ ] Push notifications
- [ ] iOS testing

---

## KNOWN ISSUES
- [ ] **Emulator has no internet** — Supabase calls hang. Fix: Windows Firewall → allow `qemu-system-x86_64.exe`
- [ ] Local Brief images: Google News returns Google logo — needs og:image scraping
- [ ] Weather Brief and Politics Brief RSS URLs need live verification
- [ ] International news: country-aware API not yet implemented
- [ ] `trubrief-release.jks` keystore not yet created (needed for Play Store)
- [ ] RLS not yet enabled on Supabase tables

---

## IMPORTANT CODE LOCATIONS (lib/main.dart)
- `_currentVersionCode` — static const int, increment each release (~line 88)
- `_checkForUpdate()` — OTA update checker (~line 90)
- `_LoginScreenState` — `kDebugMode` pre-fill for dev credentials (~line 79)
- `_fetchGoogleNewsLocal()` — multi-query parallel Local Brief fetch (~line 625)
- `_fetchGoogleNewsQuery()` — single RSS query helper (~line 675)
- `_deduplicateByTopic()` — Jaccard dedup/grouping (~line 804)
- `_buildTutorialOverlay()` — redesigned tutorial (~line 1258)
- `_tabChip()` + grid icon — main tab bar builder (~line 1583)
- `SourceSettingsScreen` class — full settings UI (~line 2084)
- `CategoryDetailScreen` class — per-category source management (~line 3521)
- `ArticleReaderScreen` class — in-app browser + paywall detection (~line 3764)

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
| pending | Auth, tutorial, emulator fixes, UI polish, default tabs, grid icon, card tap fix |

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
