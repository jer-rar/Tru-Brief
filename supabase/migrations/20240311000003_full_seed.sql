-- 1. Schema Update (Add requires_subscription if not exists)
ALTER TABLE trl_sources ADD COLUMN IF NOT EXISTS requires_subscription BOOLEAN DEFAULT false;

-- 2. Cleanup (Truncate if you want to fresh start, or just UPSERT)
-- TRUNCATE trl_sources; -- Uncomment if you want to clear old sources

-- 3. Seed Categories
INSERT INTO trl_categories (name, display_order, is_virtual) VALUES
('Tru Brief', 0, true),
('Local Brief', 20, false),
('National Brief', 30, false),
('World Brief', 40, false),
('Tech Brief', 50, false),
('Science Brief', 60, false),
('Business Brief', 70, false),
('Finance Brief', 80, false),
('Health Brief', 90, false),
('Lifestyle Brief', 100, false),
('Travel Brief', 110, false),
('Entertainment Brief', 120, false)
ON CONFLICT (name) DO UPDATE SET 
    display_order = EXCLUDED.display_order,
    is_virtual = EXCLUDED.is_virtual;

-- 4. Seed Sources (UPSERT by URL)
INSERT INTO trl_sources (name, url, category, requires_subscription, is_preset) VALUES
-- Tech Brief
('TechCrunch', 'https://techcrunch.com/feed/', 'Tech Brief', false, true),
('The Verge', 'https://www.theverge.com/rss/index.xml', 'Tech Brief', false, true),
('Wired', 'https://www.wired.com/feed/rss', 'Tech Brief', false, true),
('Engadget', 'https://www.engadget.com/rss.xml', 'Tech Brief', false, true),
('Gizmodo', 'https://gizmodo.com/rss', 'Tech Brief', false, true),
('Ars Technica', 'https://arstechnica.com/feed/', 'Tech Brief', false, true),
('CNET', 'https://www.cnet.com/rss/', 'Tech Brief', false, true),
('Bloomberg Technology', 'https://feeds.bloomberg.com/technology/news.rss', 'Tech Brief', false, true),
('MIT Technology Review', 'https://www.technologyreview.com/feed/', 'Tech Brief', false, true),
('ZDNet', 'https://www.zdnet.com/topic/rss.xml', 'Tech Brief', false, true),

-- Science Brief
('Scientific American', 'https://www.scientificamerican.com/feed/', 'Science Brief', false, true),
('Nature', 'https://www.nature.com/nature.rss', 'Science Brief', true, true),
('Science Magazine', 'https://www.science.org/rss/current.xml', 'Science Brief', true, true),
('New Scientist', 'https://www.newscientist.com/feed/', 'Science Brief', false, true),
('National Geographic', 'https://www.nationalgeographic.com/science/rss', 'Science Brief', false, true),
('Popular Science', 'https://www.popsci.com/rss', 'Science Brief', false, true),
('Discover', 'https://www.discovermagazine.com/feed', 'Science Brief', false, true),
('Quanta Magazine', 'https://www.quantamagazine.org/feed/', 'Science Brief', false, true),
('BBC Science', 'https://www.bbc.com/news/science_and_environment/rss.xml', 'Science Brief', false, true),
('Smithsonian Magazine', 'https://www.smithsonianmag.com/rss/', 'Science Brief', false, true),

-- Business Brief
('Bloomberg', 'https://feeds.bloomberg.com/markets/news.rss', 'Business Brief', false, true),
('CNBC', 'https://www.cnbc.com/id/100003114/device/rss/rss.html', 'Business Brief', false, true),
('The Economist', 'https://www.economist.com/business/rss.xml', 'Business Brief', true, true),
('Wall Street Journal', 'https://feeds.a.dj.com/rss/RSSMarketsMain.xml', 'Business Brief', true, true),
('Financial Times', 'https://www.ft.com/rss/business', 'Business Brief', true, true),
('Forbes', 'https://www.forbes.com/business/feed/', 'Business Brief', false, true),
('Business Insider', 'https://www.businessinsider.com/rss', 'Business Brief', false, true),
('Reuters Business', 'https://www.reuters.com/rss/business', 'Business Brief', false, true),
('Fortune', 'https://fortune.com/feed/', 'Business Brief', false, true),
('Harvard Business Review', 'https://hbr.org/feed', 'Business Brief', false, true),

-- Finance Brief
('Financial Times Markets', 'https://www.ft.com/rss/markets', 'Finance Brief', true, true),
('Reuters Finance', 'https://www.reuters.com/rss/markets', 'Finance Brief', false, true),
('Yahoo Finance', 'https://finance.yahoo.com/rss/topstories', 'Finance Brief', false, true),
('MarketWatch', 'https://www.marketwatch.com/rss', 'Finance Brief', false, true),
('Investopedia', 'https://www.investopedia.com/rss', 'Finance Brief', false, true),
('Barron’s', 'https://www.barrons.com/rss', 'Finance Brief', true, true),
('Morningstar', 'https://www.morningstar.com/rss', 'Finance Brief', false, true),

-- Health Brief
('Mayo Clinic', 'https://newsnetwork.mayoclinic.org/feed/', 'Health Brief', false, true),
('WebMD', 'https://rssfeeds.webmd.com/rss/rss.aspx?RSSSource=RSS_PUBLIC', 'Health Brief', false, true),
('Harvard Health', 'https://www.health.harvard.edu/feed', 'Health Brief', false, true),
('The Lancet', 'https://www.thelancet.com/rss', 'Health Brief', true, true),
('New England Journal of Medicine', 'https://www.nejm.org/rss', 'Health Brief', true, true),
('Kaiser Health News', 'https://khn.org/feed/', 'Health Brief', false, true),
('BBC Health', 'https://www.bbc.com/news/health/rss.xml', 'Health Brief', false, true),
('NPR Health', 'https://www.npr.org/rss/podcast.php?id=510298', 'Health Brief', false, true),
('CDC', 'https://www.cdc.gov/rss', 'Health Brief', false, true),
('WHO', 'https://www.who.int/rss', 'Health Brief', false, true),

-- Lifestyle Brief
('Vogue', 'https://www.vogue.com/feed/rss', 'Lifestyle Brief', false, true),
('GQ', 'https://www.gq.com/feed/rss', 'Lifestyle Brief', false, true),
('The New York Times Style', 'https://rss.nytimes.com/services/xml/rss/nyt/Style.xml', 'Lifestyle Brief', true, true),
('Elle', 'https://www.elle.com/rss', 'Lifestyle Brief', false, true),
('Harper’s Bazaar', 'https://www.harpersbazaar.com/rss', 'Lifestyle Brief', false, true),
('Vanity Fair', 'https://www.vanityfair.com/feed/rss', 'Lifestyle Brief', false, true),
('Refinery29', 'https://www.refinery29.com/rss', 'Lifestyle Brief', false, true),
('Bon Appétit', 'https://www.bonappetit.com/feed', 'Lifestyle Brief', false, true),
('Apartment Therapy', 'https://www.apartmenttherapy.com/rss', 'Lifestyle Brief', false, true),
('Travel + Leisure Lifestyle', 'https://www.travelandleisure.com/feed', 'Lifestyle Brief', false, true),

-- Travel Brief
('Lonely Planet', 'https://www.lonelyplanet.com/feed', 'Travel Brief', false, true),
('National Geographic Travel', 'https://www.nationalgeographic.com/travel/rss', 'Travel Brief', false, true),
('Travel + Leisure', 'https://www.travelandleisure.com/feed', 'Travel Brief', false, true),
('Condé Nast Traveler', 'https://www.cntraveler.com/feed/rss', 'Travel Brief', false, true),
('AFAR', 'https://www.afar.com/rss', 'Travel Brief', false, true),
('BBC Travel', 'https://www.bbc.com/travel/rss', 'Travel Brief', false, true),
('The Points Guy', 'https://thepointsguy.com/feed/', 'Travel Brief', false, true),
('Rough Guides', 'https://www.roughguides.com/feed/', 'Travel Brief', false, true),
('Rick Steves', 'https://www.ricksteves.com/rss', 'Travel Brief', false, true),
('Frommer’s', 'https://www.frommers.com/rss', 'Travel Brief', false, true),

-- Entertainment Brief
('Variety', 'https://variety.com/feed/', 'Entertainment Brief', false, true),
('The Hollywood Reporter', 'https://www.hollywoodreporter.com/feed/', 'Entertainment Brief', false, true),
('Entertainment Weekly', 'https://ew.com/feed/', 'Entertainment Brief', false, true),
('Deadline', 'https://deadline.com/feed/', 'Entertainment Brief', false, true),
('TMZ', 'https://www.tmz.com/rss.xml', 'Entertainment Brief', false, true),
('People', 'https://people.com/rss', 'Entertainment Brief', false, true),
('Rolling Stone', 'https://www.rollingstone.com/feed/', 'Entertainment Brief', false, true),
('Billboard', 'https://www.billboard.com/rss', 'Entertainment Brief', false, true),
('E! Online', 'https://www.eonline.com/rss', 'Entertainment Brief', false, true),
('IMDb News', 'https://www.imdb.com/news/rss', 'Entertainment Brief', false, true),

-- World Brief
('BBC News', 'https://feeds.bbci.co.uk/news/rss.xml', 'World Brief', false, true),
('Reuters', 'https://www.reuters.com/tools/rss', 'World Brief', false, true),
('Al Jazeera', 'https://www.aljazeera.com/xml/rss/all.xml', 'World Brief', false, true),
('The Guardian', 'https://www.theguardian.com/world/rss', 'World Brief', false, true),
('The New York Times World', 'https://rss.nytimes.com/services/xml/rss/nyt/World.xml', 'World Brief', true, true),
('Associated Press', 'https://feeds.apnews.com/ap/rss', 'World Brief', false, true),
('France 24', 'https://www.france24.com/en/rss', 'World Brief', false, true),
('DW', 'https://www.dw.com/en/rss', 'World Brief', false, true),
('South China Morning Post', 'https://www.scmp.com/rss', 'World Brief', false, true),
('NPR International', 'https://www.npr.org/rss/podcast.php?id=510298', 'World Brief', false, true),

-- National Brief
('The New York Times', 'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml', 'National Brief', true, true),
('Washington Post', 'https://feeds.washingtonpost.com/rss/national', 'National Brief', true, true),
('CNN', 'https://rss.cnn.com/rss/cnn_topstories.rss', 'National Brief', false, true),
('Wall Street Journal World', 'https://feeds.a.dj.com/rss/RSSWorldNews.xml', 'National Brief', true, true),
('USA Today', 'https://www.usatoday.com/rss', 'National Brief', false, true),
('NPR', 'https://feeds.npr.org/1001/rss.xml', 'National Brief', false, true),
('CBS News', 'https://www.cbsnews.com/rss', 'National Brief', false, true),
('ABC News', 'https://abcnews.go.com/abcnews/topstoriesrss', 'National Brief', false, true),
('NBC News', 'https://www.nbcnews.com/rss', 'National Brief', false, true),
('Axios', 'https://www.axios.com/rss', 'National Brief', false, true),

-- Local Brief
('New York Times (NY)', 'https://rss.nytimes.com/services/xml/rss/nyt/NYRegion.xml', 'Local Brief', true, true),
('LA Times (LA)', 'https://www.latimes.com/rss', 'Local Brief', false, true),
('Chicago Tribune', 'https://www.chicagotribune.com/rss', 'Local Brief', false, true),
('Boston Globe', 'https://www.bostonglobe.com/rss', 'Local Brief', true, true),
('SF Chronicle', 'https://www.sfchronicle.com/rss', 'Local Brief', false, true),
('Houston Chronicle', 'https://www.houstonchronicle.com/rss', 'Local Brief', false, true),
('Miami Herald', 'https://www.miamiherald.com/rss', 'Local Brief', false, true),
('Seattle Times', 'https://www.seattletimes.com/rss', 'Local Brief', false, true),
('Atlanta Journal-Constitution', 'https://www.ajc.com/rss', 'Local Brief', false, true),
('Dallas Morning News', 'https://www.dallasnews.com/rss', 'Local Brief', false, true)

ON CONFLICT (url) DO UPDATE SET 
    category = EXCLUDED.category,
    name = EXCLUDED.name,
    requires_subscription = EXCLUDED.requires_subscription,
    is_preset = EXCLUDED.is_preset;
