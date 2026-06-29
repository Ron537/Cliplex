-- Generic demo data for marketing screenshots. No real/confidential content.
BEGIN;

-- Snippet folders
INSERT INTO snippet_folders (name, sort_order, created_at) VALUES
 ('Email',    0, strftime('%s','now')*1000),
 ('Code',     1, strftime('%s','now')*1000),
 ('SQL',      2, strftime('%s','now')*1000),
 ('Personal', 3, strftime('%s','now')*1000);

-- Snippets
INSERT INTO snippets (folder_id, title, content, sort_order, created_at, updated_at) VALUES
 ((SELECT id FROM snippet_folders WHERE name='Email'), 'Meeting follow-up',
  'Hi {clipboard},' || char(10) || char(10) || 'Thanks for the great discussion today. I''ll send the notes and next steps shortly.' || char(10) || char(10) || 'Best,' || char(10) || 'Ron', 0, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM snippet_folders WHERE name='Email'), 'Out of office',
  'I''m currently out of the office with limited access to email and will reply when I''m back.', 1, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM snippet_folders WHERE name='Code'), 'React component',
  'export function Component() {' || char(10) || '  return <div />;' || char(10) || '}', 0, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM snippet_folders WHERE name='Code'), 'Try / catch',
  'try {' || char(10) || '  ' || char(10) || '} catch (error) {' || char(10) || '  console.error(error);' || char(10) || '}', 1, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM snippet_folders WHERE name='Code'), 'Console log',
  'console.log(''debug:'', );', 2, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM snippet_folders WHERE name='SQL'), 'Recent rows',
  'SELECT * FROM {clipboard}' || char(10) || 'WHERE created_at > now() - interval ''7 days'';', 0, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM snippet_folders WHERE name='SQL'), 'Count by day',
  'SELECT date(created_at) d, count(*)' || char(10) || 'FROM events GROUP BY d ORDER BY d DESC;', 1, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM snippet_folders WHERE name='Personal'), 'Email signature',
  'Ron Borysowski' || char(10) || 'Software Engineer' || char(10) || 'ron@example.com', 0, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM snippet_folders WHERE name='Personal'), 'Mailing address',
  '123 Market Street' || char(10) || 'San Francisco, CA 94103', 1, strftime('%s','now')*1000, strftime('%s','now')*1000);

-- Action folders
INSERT INTO action_folders (name, sort_order, created_at) VALUES
 ('Search',    0, strftime('%s','now')*1000),
 ('Dev tools', 1, strftime('%s','now')*1000);

-- Actions
INSERT INTO actions (folder_id, title, type, value, transform, sort_order, created_at, updated_at) VALUES
 ((SELECT id FROM action_folders WHERE name='Search'), 'Search Google', 'open_url', 'https://www.google.com/search?q={clipboard}', NULL, 0, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM action_folders WHERE name='Search'), 'Open GitHub repo', 'open_url', 'https://github.com/{clipboard}', NULL, 1, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM action_folders WHERE name='Search'), 'Translate', 'open_url', 'https://translate.google.com/?text={clipboard}', NULL, 2, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM action_folders WHERE name='Dev tools'), 'Base64 encode', 'transform', '', 'base64_encode', 0, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM action_folders WHERE name='Dev tools'), 'JSON prettify', 'transform', '', 'json_pretty', 1, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM action_folders WHERE name='Dev tools'), 'URL encode', 'transform', '', 'url_encode', 2, strftime('%s','now')*1000, strftime('%s','now')*1000),
 ((SELECT id FROM action_folders WHERE name='Dev tools'), 'UPPERCASE', 'transform', '', 'uppercase', 3, strftime('%s','now')*1000, strftime('%s','now')*1000);

-- Clipboard history (newest first via updated_at; a couple pinned)
INSERT INTO clips (content_hash, kind, preview, source_app, pinned, created_at, updated_at) VALUES
 ('demo01', 'text',     'Ship the v0.1.0 release notes', 'com.apple.Notes',     1, strftime('%s','now')*1000 - 60000,    strftime('%s','now')*1000 - 60000),
 ('demo02', 'text',     'https://github.com/Ron537/Cliplex', 'com.apple.Safari', 1, strftime('%s','now')*1000 - 120000,   strftime('%s','now')*1000 - 120000),
 ('demo03', 'text',     'git commit -m "fix: panel layout on retina"', 'com.apple.Terminal', 0, strftime('%s','now')*1000 - 300000, strftime('%s','now')*1000 - 300000),
 ('demo04', 'richtext', 'Thanks for the thorough review — merging now.', 'com.apple.mail', 0, strftime('%s','now')*1000 - 900000, strftime('%s','now')*1000 - 900000),
 ('demo05', 'text',     'export function ClipboardRow({ item }) {', 'com.microsoft.VSCode', 0, strftime('%s','now')*1000 - 1800000, strftime('%s','now')*1000 - 1800000),
 ('demo06', 'color',    '#2563EB', 'com.microsoft.VSCode', 0, strftime('%s','now')*1000 - 3600000, strftime('%s','now')*1000 - 3600000),
 ('demo07', 'text',     'The quick brown fox jumps over the lazy dog', 'com.apple.Notes', 0, strftime('%s','now')*1000 - 7200000, strftime('%s','now')*1000 - 7200000),
 ('demo08', 'files',    '~/Downloads/cliplex-icon.png', 'com.apple.finder', 0, strftime('%s','now')*1000 - 18000000, strftime('%s','now')*1000 - 18000000),
 ('demo09', 'text',     'https://news.ycombinator.com/newest', 'com.google.Chrome', 0, strftime('%s','now')*1000 - 90000000, strftime('%s','now')*1000 - 90000000),
 ('demo10', 'text',     'SELECT id, name FROM users ORDER BY created_at DESC;', 'com.microsoft.VSCode', 0, strftime('%s','now')*1000 - 93600000, strftime('%s','now')*1000 - 93600000),
 ('demo11', 'image',    '(Image)', 'com.apple.Safari', 0, strftime('%s','now')*1000 - 97200000, strftime('%s','now')*1000 - 97200000);

COMMIT;
