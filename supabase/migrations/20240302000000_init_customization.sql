-- 1. News Sources Table
CREATE TABLE IF NOT EXISTS trl_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    url TEXT NOT NULL UNIQUE,
    type TEXT NOT NULL CHECK (type IN ('rss', 'html', 'newsletter')),
    category TEXT DEFAULT 'Tech',
    is_preset BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. User Preferences Table (Personalized Sources/Categories)
CREATE TABLE IF NOT EXISTS trl_user_preferences (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    selected_sources UUID[] DEFAULT '{}',
    selected_categories TEXT[] DEFAULT '{}',
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Subscriptions & Trials Table
CREATE TABLE IF NOT EXISTS trl_subscriptions (
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    status TEXT DEFAULT 'trial' CHECK (status IN ('trial', 'active', 'expired', 'canceled')),
    trial_started_at TIMESTAMPTZ DEFAULT now(),
    subscription_ends_at TIMESTAMPTZ,
    is_ai_enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Update trl_articles to link to sources
ALTER TABLE trl_articles ADD COLUMN IF NOT EXISTS source_id UUID REFERENCES trl_sources(id);
ALTER TABLE trl_articles ADD COLUMN IF NOT EXISTS category TEXT;

-- 5. Seed default tech sources
INSERT INTO trl_sources (name, url, type, category, is_preset) VALUES
('TechCrunch', 'https://techcrunch.com/feed/', 'rss', 'Tech', true),
('The Verge', 'https://www.theverge.com/rss/index.xml', 'rss', 'Tech', true),
('Wired', 'https://www.wired.com/feed/rss', 'rss', 'Tech', true),
('Ars Technica', 'https://feeds.arstechnica.com/arstechnica/index', 'rss', 'Tech', true)
ON CONFLICT (url) DO NOTHING;
