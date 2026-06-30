#!/usr/bin/env node
// Build-time CHANGELOG renderer (zero dependencies — node: builtins only).
//
// Reads CHANGELOG.md and renders the changelog section of the GitHub Pages site
// into site/changelog.html.template -> _site/changelog/index.html, and emits
// _site/sitemap.xml. Run indirectly via scripts/build-site.mjs.
//
// Grammar (the subset CHANGELOG.md uses):
//   ## [x.y.z] - YYYY-MM-DD      release heading (date optional; -–— allowed)
//   ### Features|Improvements|Bug Fixes|Performance
//   - bullet with inline `code` and **bold**
// Anything else (the [Unreleased] placeholder when empty, the link-reference
// block at the bottom) is skipped gracefully.

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const SITE_URL = 'https://ron537.github.io/Cliplex'

const HEADING_RE = /^##\s+\[([^\]]+)\](?:\s+[-–—]\s+(.+))?\s*$/
const SUBHEADING_RE = /^###\s+(.+?)\s*$/
const BULLET_RE = /^[-*]\s+(.+)$/

export function escapeHtml(input) {
  return String(input)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

// Render inline markdown for a bullet: `code` -> <code>, **bold** -> <strong>.
// Input is HTML-escaped first so untrusted text can't inject markup.
export function renderInline(input) {
  const codeSpans = []
  let s = String(input).replace(/`([^`]+)`/g, (_, code) => {
    codeSpans.push(escapeHtml(code))
    return `\u0000${codeSpans.length - 1}\u0000`
  })
  s = escapeHtml(s)
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
  s = s.replace(/\u0000(\d+)\u0000/g, (_, i) => `<code>${codeSpans[Number(i)]}</code>`)
  return s
}

// Parse CHANGELOG.md text into [{ version, date, sections: [{ title, items }] }].
export function parseChangelog(text) {
  const releases = []
  let release = null
  let section = null
  for (const raw of text.split('\n')) {
    const heading = raw.match(HEADING_RE)
    if (heading) {
      release = { version: heading[1], date: heading[2] || '', sections: [] }
      section = null
      releases.push(release)
      continue
    }
    if (!release) continue
    const sub = raw.match(SUBHEADING_RE)
    if (sub) {
      section = { title: sub[1], items: [] }
      release.sections.push(section)
      continue
    }
    const bullet = raw.match(BULLET_RE)
    if (bullet && section) section.items.push(bullet[1].trim())
  }
  // Drop releases with no content (e.g. an empty [Unreleased]).
  return releases.filter((r) => r.sections.some((s) => s.items.length > 0))
}

export function renderChangelogHtml(releases) {
  const sectionClass = (title) =>
    'sec-' + title.toLowerCase().replace(/[^a-z]+/g, '-').replace(/^-|-$/g, '')
  return releases
    .map((r) => {
      const meta = r.date ? `<time>${escapeHtml(r.date)}</time>` : ''
      const body = r.sections
        .filter((s) => s.items.length > 0)
        .map(
          (s) => `
        <div class="cl-section ${sectionClass(s.title)}">
          <h3>${escapeHtml(s.title)}</h3>
          <ul>${s.items.map((i) => `<li>${renderInline(i)}</li>`).join('')}</ul>
        </div>`
        )
        .join('')
      return `
      <article class="release">
        <header><h2 id="v${escapeHtml(r.version)}">${escapeHtml(r.version)}</h2>${meta}</header>
        ${body}
      </article>`
    })
    .join('\n')
}

function renderSitemap() {
  const today = new Date().toISOString().slice(0, 10)
  const pages = ['/', '/changelog/']
  const urls = pages
    .map((p) => `  <url><loc>${SITE_URL}${p}</loc><lastmod>${today}</lastmod></url>`)
    .join('\n')
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${urls}\n</urlset>\n`
}

function main() {
  const __dirname = dirname(fileURLToPath(import.meta.url))
  const root = resolve(__dirname, '..')
  const out = resolve(root, '_site')

  const changelog = readFileSync(resolve(root, 'CHANGELOG.md'), 'utf8')
  const releases = parseChangelog(changelog)
  const html = renderChangelogHtml(releases)

  const template = readFileSync(resolve(root, 'site/changelog.html.template'), 'utf8')
  const page = template
    .replace('{{CHANGELOG}}', html)
    .replace(/{{YEAR}}/g, String(new Date().getFullYear()))

  mkdirSync(resolve(out, 'changelog'), { recursive: true })
  writeFileSync(resolve(out, 'changelog/index.html'), page)
  writeFileSync(resolve(out, 'sitemap.xml'), renderSitemap())
  console.log(`changelog: rendered ${releases.length} release(s) -> _site/changelog/index.html`)
}

if (import.meta.url === `file://${process.argv[1]}`) main()
