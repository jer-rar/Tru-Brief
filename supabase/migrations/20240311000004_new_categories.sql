-- Add Nature Brief, Pet Brief, Home Brief categories
INSERT INTO trl_categories (name, display_order, is_virtual) VALUES
('Nature Brief', 130, false),
('Pet Brief', 140, false),
('Home Brief', 150, false)
ON CONFLICT (name) DO UPDATE SET
    display_order = EXCLUDED.display_order,
    is_virtual = EXCLUDED.is_virtual;

-- Seed Sources for new categories
INSERT INTO trl_sources (name, url, type, category, requires_subscription, is_preset) VALUES

-- Nature Brief
('National Geographic Environment', 'https://www.nationalgeographic.com/environment/rss', 'rss', 'Nature Brief', false, true),
('The Guardian Environment', 'https://www.theguardian.com/environment/rss', 'rss', 'Nature Brief', false, true),
('BBC Earth', 'https://www.bbc.com/news/science_and_environment/rss.xml', 'rss', 'Nature Brief', false, true),
('Mongabay', 'https://news.mongabay.com/feed/', 'rss', 'Nature Brief', false, true),
('EcoWatch', 'https://www.ecowatch.com/rss', 'rss', 'Nature Brief', false, true),
('Yale Environment 360', 'https://e360.yale.edu/rss', 'rss', 'Nature Brief', false, true),
('Sierra Club', 'https://www.sierraclub.org/sierra/rss.xml', 'rss', 'Nature Brief', false, true),
('Nature Conservancy', 'https://www.nature.org/en-us/newsroom/feed/', 'rss', 'Nature Brief', false, true),
('Treehugger', 'https://www.treehugger.com/feeds/all', 'rss', 'Nature Brief', false, true),
('Smithsonian Nature', 'https://www.smithsonianmag.com/rss/nature/', 'rss', 'Nature Brief', false, true),

-- Pet Brief
('American Kennel Club', 'https://www.akc.org/rss/expert-advice/', 'rss', 'Pet Brief', false, true),
('PetMD', 'https://www.petmd.com/rss', 'rss', 'Pet Brief', false, true),
('The Bark', 'https://thebark.com/rss', 'rss', 'Pet Brief', false, true),
('Catster', 'https://www.catster.com/feed', 'rss', 'Pet Brief', false, true),
('Dogster', 'https://www.dogster.com/feed', 'rss', 'Pet Brief', false, true),
('Modern Dog Magazine', 'https://moderndogmagazine.com/feed', 'rss', 'Pet Brief', false, true),
('AVMA News', 'https://www.avma.org/rss', 'rss', 'Pet Brief', false, true),
('Rover Blog', 'https://www.rover.com/blog/feed/', 'rss', 'Pet Brief', false, true),
('Whole Dog Journal', 'https://www.whole-dog-journal.com/feed', 'rss', 'Pet Brief', false, true),
('Cat Fancy', 'https://www.catfancy.com/rss', 'rss', 'Pet Brief', false, true),

-- Home Brief
('This Old House', 'https://www.thisoldhouse.com/rss', 'rss', 'Home Brief', false, true),
('Architectural Digest', 'https://www.architecturaldigest.com/feed/rss', 'rss', 'Home Brief', false, true),
('Better Homes & Gardens', 'https://www.bhg.com/rss', 'rss', 'Home Brief', false, true),
('House Beautiful', 'https://www.housebeautiful.com/rss', 'rss', 'Home Brief', false, true),
('The Spruce', 'https://www.thespruce.com/rss', 'rss', 'Home Brief', false, true),
('Bob Vila', 'https://www.bobvila.com/feed', 'rss', 'Home Brief', false, true),
('Houzz', 'https://www.houzz.com/rss', 'rss', 'Home Brief', false, true),
('HGTV', 'https://www.hgtv.com/rss', 'rss', 'Home Brief', false, true),
('Martha Stewart Home', 'https://www.marthastewart.com/rss', 'rss', 'Home Brief', false, true),
('Apartment Therapy Home', 'https://www.apartmenttherapy.com/rss', 'rss', 'Home Brief', false, true)

ON CONFLICT (url) DO UPDATE SET
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    requires_subscription = EXCLUDED.requires_subscription,
    is_preset = EXCLUDED.is_preset;
