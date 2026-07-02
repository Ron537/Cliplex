#!/usr/bin/env node
// Assemble the GitHub Pages bundle into _site/ (zero dependencies).
//
//   _site/                      <- site/ (minus *.template)
//   _site/assets/screenshots/   <- assets/screenshots/ (real app screenshots)
//   _site/changelog/index.html  } produced by build-changelog.mjs
//   _site/sitemap.xml           }
//
// Mirrors the Pages workflow so you can preview locally:
//   node scripts/build-site.mjs && npx --yes serve@14 _site

import { cpSync, mkdirSync, rmSync, existsSync, readdirSync, statSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { dirname, resolve, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const root = resolve(__dirname, '..')
const out = resolve(root, '_site')

rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })

// 1. Copy site/ except *.template files.
cpSync(resolve(root, 'site'), out, {
  recursive: true,
  filter: (src) => !src.endsWith('.template'),
})

// 2. Copy the real app screenshots used by the landing page.
const shots = resolve(root, 'assets/screenshots')
if (existsSync(shots)) {
  cpSync(shots, resolve(out, 'assets/screenshots'), { recursive: true })
}

// 2b. Copy the demo GIFs used by the landing page.
for (const gif of ['demo.gif', 'demo-snippet.gif', 'demo-action.gif']) {
  const src = resolve(root, 'assets', gif)
  if (existsSync(src)) cpSync(src, resolve(out, 'assets', gif))
}

// 3. Render the changelog page + sitemap.
const res = spawnSync(process.execPath, [resolve(__dirname, 'build-changelog.mjs')], {
  stdio: 'inherit',
})
if (res.status !== 0) process.exit(res.status ?? 1)

// Summary.
function countFiles(dir) {
  let n = 0
  for (const e of readdirSync(dir)) {
    const p = join(dir, e)
    n += statSync(p).isDirectory() ? countFiles(p) : 1
  }
  return n
}
console.log(`site: built _site/ (${countFiles(out)} files)`)
