-- Create table for managing Categories
CREATE TABLE IF NOT EXISTS trl_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    display_order INT NOT NULL DEFAULT 0,
    is_virtual BOOLEAN DEFAULT false, -- True for things like 'Just Now' and 'Weekly Top'
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Seed Categories
INSERT INTO trl_categories (name, display_order, is_virtual) VALUES
('Just Now', 0, true),
('Weekly Top', 10, true),
('Local Brief', 20, false),
('National Brief', 30, false),
('World Brief', 40, false),
('Tech Brief', 50, false),
('Science Brief', 60, false),
('Business Brief', 70, false),
('Finance Brief', 80, false),
('Lifestyle Brief', 90, false),
('Health Brief', 100, false),
('Travel Brief', 110, false),
('Entertainment Brief', 120, false)
ON CONFLICT (name) DO UPDATE SET 
    display_order = EXCLUDED.display_order,
    is_virtual = EXCLUDED.is_virtual;

-- Optional: Add a config table for global app settings (like archival periods)
CREATE TABLE IF NOT EXISTS trl_app_config (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO trl_app_config (key, value) VALUES
('archival_days', '7'),
('purge_days', '30'),
('trending_days', '7')
ON CONFLICT (key) DO NOTHING;
