#!/usr/bin/env node
// Local preview server for the GitHub Pages site (zero dependencies).
//
// Builds _site/ (via build-site.mjs), serves it on http://localhost:8080, and
// rebuilds automatically when you edit site/, the screenshots, the build
// scripts, or CHANGELOG.md — so you can play with the landing/changelog pages.
//
//   node scripts/serve-site.mjs            # http://localhost:8080
//   node scripts/serve-site.mjs 3000       # custom port
//   PORT=3000 node scripts/serve-site.mjs
//
// Ctrl-C to stop.

import { createServer } from 'node:http'
import { spawnSync } from 'node:child_process'
import { readFileSync, existsSync, statSync, watch } from 'node:fs'
import { dirname, resolve, join, extname, normalize } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const root = resolve(__dirname, '..')
const siteDir = resolve(root, '_site')
const port = Number(process.argv[2] || process.env.PORT || 8080)

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
}

function build() {
  const res = spawnSync(process.execPath, [resolve(__dirname, 'build-site.mjs')], {
    stdio: 'inherit',
  })
  return res.status === 0
}

// Resolve a URL path to a file inside _site/, defaulting directories to
// index.html and preventing path traversal outside _site/.
function resolveFile(urlPath) {
  let p = decodeURIComponent(urlPath.split('?')[0])
  if (p.endsWith('/')) p += 'index.html'
  const abs = normalize(join(siteDir, p))
  if (!abs.startsWith(siteDir)) return null
  if (existsSync(abs) && statSync(abs).isDirectory()) return join(abs, 'index.html')
  return abs
}

const server = createServer((req, res) => {
  let file = resolveFile(req.url || '/')
  // Friendly fallback: /changelog -> /changelog/index.html
  if (file && !existsSync(file) && existsSync(file + '/index.html')) file += '/index.html'
  if (!file || !existsSync(file) || statSync(file).isDirectory()) {
    res.writeHead(404, { 'Content-Type': 'text/html' })
    res.end('<h1>404</h1><p>Not found. <a href="/">Home</a></p>')
    return
  }
  res.writeHead(200, { 'Content-Type': MIME[extname(file)] || 'application/octet-stream' })
  res.end(readFileSync(file))
})

// Debounced rebuild on source changes.
const watched = ['site', 'assets/screenshots', 'CHANGELOG.md', 'scripts/build-site.mjs', 'scripts/build-changelog.mjs']
let timer = null
function onChange() {
  clearTimeout(timer)
  timer = setTimeout(() => {
    process.stdout.write('\n↻ change detected — rebuilding…\n')
    build()
  }, 150)
}

if (!build()) {
  console.error('Initial site build failed.')
  process.exit(1)
}

for (const rel of watched) {
  const abs = resolve(root, rel)
  if (!existsSync(abs)) continue
  try {
    watch(abs, { recursive: statSync(abs).isDirectory() }, onChange)
  } catch {
    // recursive watch may be unsupported on some platforms — non-fatal.
  }
}

server.listen(port, () => {
  console.log(`\n  Cliplex site → http://localhost:${port}`)
  console.log(`  Watching for changes. Ctrl-C to stop.\n`)
})
