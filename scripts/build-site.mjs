#!/usr/bin/env node
/*
 * Deskmap website builder.  Usage:  node scripts/build-site.mjs [--strict]
 *                                   (make site / make site-serve)
 *
 * No npm dependencies: Node 18+ and, for the Markdown docs, pandoc.
 * Output goes to website/_site/ (gitignored), which is deleted and rebuilt
 * on every run. The site must work from any sub-path (GitHub Pages serves it
 * at https://cnkndmr.github.io/Deskmap/), so EVERY internal link and asset URL
 * is relative: write {{root}} in front of it. Never write href="/docs/".
 *
 * ── Source layout ──────────────────────────────────────────────────────────
 *   website/layout.html   one shared layout (head, OG, header nav, footer)
 *   website/assets/       copied to _site/assets/ (site.css, site.js,
 *                         docs.css, images/). Linked as {{root}}assets/...
 *   website/pages/        hand-written page bodies. pages/foo/index.html
 *                         becomes _site/foo/index.html (URL foo/); the path
 *                         is mirrored 1:1 unless front matter sets `out`.
 *   website/shots/{en,tr}/ web-sized copies (max 1600 px wide) of the
 *                         screenshots in docs/images/{en,tr}/, copied to
 *                         _site/images/{en,tr}/. Linked as
 *                         {{root}}images/en/01-map.png. A file missing from
 *                         website/shots falls back to docs/images (warning).
 *                         website/shots/<l>/light/ holds light-appearance
 *                         twins; see themeImages(). Regenerate both after UI
 *                         changes: make site-shots.
 *                         <img> width/height pointing at images/ are set by
 *                         the build from the shipped file, so pages never
 *                         carry stale sizes.
 *   docs/*.md, CHANGELOG  rendered by renderMarkdownDocs() (see HOOK below).
 *
 * ── Front matter ───────────────────────────────────────────────────────────
 * Every file in website/pages/ starts with a block like this (one
 * `key: value` per line, no nesting, values are plain text, no quotes needed):
 *
 *   ---
 *   title: Download Deskmap — Deskmap        (required; used as-is in <title>)
 *   description: One or two sentences.       (required; meta + OG description)
 *   lang: en                                 (en | tr; default en)
 *   nav: download                            (home | docs | download | compare
 *                                             | changelog | none) active nav item
 *   alt: tr/download/                        (site-relative URL of the same page
 *                                             in the other language; omit if none)
 *   out: docs/index.html                     (optional output path override)
 *   body_class: page-download                (optional extra class on <body>)
 *   js: docs                                 (optional: also load assets/<name>.js, deferred)
 *   css: docs                                (optional: also load assets/<name>.css;
 *                                             comma-separated for several)
 *   og_title: Short title for link cards     (optional; defaults to title)
 *   og_image: assets/images/og.png           (optional site-relative path)
 *   root: absolute                           (ONLY for 404.html: GitHub Pages
 *                                             serves it at any depth, so links
 *                                             use BASE_PATH instead of ../)
 *   noindex: true                            (optional; adds robots noindex)
 *   ---
 *   <section class="page-head">...</section>   ← body HTML, placed in <main>
 *
 * ── Tokens ─────────────────────────────────────────────────────────────────
 * Usable in page bodies, Markdown output and layout.html. Unknown {{...}}
 * text is left untouched.
 *   {{root}}         relative prefix to the site root: "./", "../", "../../"
 *   {{version}}      contents of VERSION (e.g. 0.5.0)
 *   {{release_url}}  https://github.com/cnkndmr/Deskmap/releases/latest
 *   {{repo_url}}     https://github.com/cnkndmr/Deskmap
 *   {{paypal_url}}   the support link from the app's Settings sidebar
 *   {{site_url}}     absolute site URL (env SITE_URL), for metadata only
 *   {{year}}         current year
 *   {{lang}}         page language
 *   {{t.KEY}}        UI string from I18N[lang] below (e.g. {{t.nav_docs}})
 *   {{href.KEY}}     language-aware site-relative path from NAV_HREFS[lang]
 *                    (e.g. {{root}}{{href.download}} → ../tr/download/)
 *
 * ── Languages ──────────────────────────────────────────────────────────────
 * EN pages live at the root, TR pages under tr/. Front matter `alt` names the
 * counterpart; the build then emits <link rel="alternate" hreflang> for both
 * (+ x-default → EN) and points the header EN/TR switch at it. Without `alt`
 * the switch goes to the other language's home page. Give the TR page the
 * reverse `alt` (EN path, e.g. `alt: download/`). The site root itself is
 * written `alt: .` (so the TR home has `alt: .`, the EN home `alt: tr/`).
 *
 * ── Adding a page ──────────────────────────────────────────────────────────
 *   1. Create website/pages/<path>/index.html with the front matter above.
 *   2. Body = <section> blocks using the components in assets/site.css
 *      (see the component index at the top of that file).
 *   3. Prefix internal links/assets with {{root}}; run `make site`.
 *   The build fails on root-absolute href/src ("/...") and warns about
 *   relative links that do not resolve to a built file (--strict: fails).
 */

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const WEB = path.join(REPO, 'website');
const PAGES = path.join(WEB, 'pages');
const OUT = path.join(WEB, '_site');
const SHOTS = path.join(WEB, 'shots');
const STRICT = process.argv.includes('--strict');

const SITE_URL = (process.env.SITE_URL || 'https://cnkndmr.github.io/Deskmap/').replace(/\/?$/, '/');
const BASE_PATH = new URL(SITE_URL).pathname; // "/Deskmap/" — used only by root: absolute
const VERSION = fs.readFileSync(path.join(REPO, 'VERSION'), 'utf8').trim();

const GLOBALS = {
  version: VERSION,
  release_url: 'https://github.com/cnkndmr/Deskmap/releases/latest',
  repo_url: 'https://github.com/cnkndmr/Deskmap',
  paypal_url: 'https://paypal.me/mcankandemir', // app/Sources/Deskmap/Views/SettingsView.swift
  site_url: SITE_URL,
  year: String(new Date().getFullYear()),
};

/* Language-aware site-relative paths ({{href.KEY}}). */
const NAV_HREFS = {
  en: { home: '', docs: 'docs/', guide: 'docs/guide/', download: 'download/', compare: 'compare/', changelog: 'changelog/' },
  tr: { home: 'tr/', docs: 'tr/docs/kilavuz/', guide: 'tr/docs/kilavuz/', download: 'tr/download/', compare: 'compare/', changelog: 'changelog/' },
};
const NAV_ORDER = ['home', 'docs', 'download', 'compare', 'changelog'];

/* UI strings ({{t.KEY}}). Add a key to both languages. */
const I18N = {
  en: {
    nav_home: 'Home', nav_docs: 'Docs', nav_download: 'Download', nav_compare: 'Compare', nav_changelog: 'Changelog',
    nav_label: 'Main', brand_label: 'Deskmap home', lang_label: 'Language', skip: 'Skip to content',
    theme_dark: 'Switch to dark theme', theme_light: 'Switch to light theme',
    menu_open: 'Open menu', menu_close: 'Close menu', download_short: 'Download',
    foot_blurb: 'Every window on the right display, the right desktop, in the right layout. A free menu bar app for macOS by Can Kandemir.',
    foot_product: 'Product', foot_docs: 'Docs', foot_project: 'Project',
    foot_all_docs: 'All docs', foot_guide: 'User guide', foot_reference: 'Reference', foot_architecture: 'Architecture', foot_privacy: 'Privacy',
    foot_issue: 'Report an issue', foot_support: 'Support the project',
    foot_license: 'MIT License · © {{year}} Can Kandemir · No data collected',
    foot_vibe: 'Vibe-coded with Claude Code',
    other_lang_name: 'Türkçe', copy: 'Copy', copied: 'Copied', close: 'Close',
    zoom: 'Open full size',
  },
  tr: {
    nav_home: 'Anasayfa', nav_docs: 'Belgeler', nav_download: 'İndir', nav_compare: 'Karşılaştırma', nav_changelog: 'Değişiklikler',
    nav_label: 'Ana menü', brand_label: 'Deskmap anasayfası', lang_label: 'Dil', skip: 'İçeriğe geç',
    theme_dark: 'Koyu temaya geç', theme_light: 'Açık temaya geç',
    menu_open: 'Menüyü aç', menu_close: 'Menüyü kapat', download_short: 'İndir',
    foot_blurb: 'Her pencere doğru ekranda, doğru masaüstünde, doğru düzende. Can Kandemir’den macOS için ücretsiz bir menü çubuğu uygulaması.',
    foot_product: 'Ürün', foot_docs: 'Belgeler', foot_project: 'Proje',
    foot_all_docs: 'Tüm belgeler (EN)', foot_guide: 'Kullanım kılavuzu', foot_reference: 'Başvuru (EN)', foot_architecture: 'Mimari (EN)', foot_privacy: 'Gizlilik',
    foot_issue: 'Sorun bildir', foot_support: 'Projeyi destekle',
    foot_license: 'MIT Lisansı · © {{year}} Can Kandemir · Hiç veri toplamaz',
    foot_vibe: 'Claude Code ile vibe coding yöntemiyle yazıldı',
    other_lang_name: 'English', copy: 'Kopyala', copied: 'Kopyalandı', close: 'Kapat',
    zoom: 'Tam boyutta aç',
  },
};
const OG_LOCALE = { en: 'en_US', tr: 'tr_TR' };

/* ───────────────────────── helpers ───────────────────────── */

const warnings = [];
const warn = (m) => { warnings.push(m); };
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

function parseFrontMatter(text, file) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(text);
  if (!m) throw new Error(`${file}: missing front matter (--- ... ---)`);
  const data = {};
  for (const line of m[1].split(/\r?\n/)) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    const i = line.indexOf(':');
    if (i < 0) throw new Error(`${file}: bad front matter line: ${line}`);
    data[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return { data, body: text.slice(m[0].length) };
}

/** Replace known {{tokens}}; leave anything else alone. Runs twice so a
 *  token inside an I18N string ({{year}}) resolves too. */
function fillTokens(str, vars, lang) {
  const t = I18N[lang], h = NAV_HREFS[lang];
  const one = (s) => s.replace(/\{\{\s*([a-z_]+(?:\.[a-z_]+)?)\s*\}\}/g, (all, key) => {
    if (key.startsWith('t.')) { const k = key.slice(2); if (k in t) return t[k]; warn(`unknown UI string {{${key}}}`); return all; }
    if (key.startsWith('href.')) { const k = key.slice(5); if (k in h) return h[k]; warn(`unknown href {{${key}}}`); return all; }
    if (key in vars) return vars[key];
    return all;
  });
  return one(one(str));
}

/** "docs/guide/index.html" → depth 2 → "../../" */
function rootFor(outRel) {
  const depth = outRel.split('/').length - 1;
  return depth === 0 ? './' : '../'.repeat(depth);
}
/** "docs/guide/index.html" → "docs/guide/" ; "404.html" → "404.html" */
function urlPathFor(outRel) {
  return outRel === 'index.html' ? '' : outRel.replace(/(^|\/)index\.html$/, '$1');
}
function normAlt(alt) { return (alt === '.' || alt === '/' || alt === './') ? '' : alt.replace(/^\.?\//, ''); }

function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p)); else out.push(p);
  }
  return out;
}

/* ───────────────────────── page rendering ───────────────────────── */

const LAYOUT = fs.readFileSync(path.join(WEB, 'layout.html'), 'utf8');
const built = []; // { outRel, lang, alt }

/**
 * Wrap one page body in the shared layout and write it.
 *   page = { outRel: 'docs/guide/index.html', data: {front matter}, body: '<html>', source }
 * Exported shape for renderMarkdownDocs(): return objects of this shape.
 */
function renderPage(page) {
  const { outRel, data, source } = page;
  for (const k of ['title', 'description']) if (!data[k]) throw new Error(`${source}: front matter needs "${k}"`);
  const lang = data.lang || 'en';
  if (!I18N[lang]) throw new Error(`${source}: lang must be en or tr`);
  const other = lang === 'en' ? 'tr' : 'en';
  const absolute = data.root === 'absolute';
  const root = absolute ? BASE_PATH : rootFor(outRel);
  const urlPath = urlPathFor(outRel);
  const t = I18N[lang];

  // Guard: no root-absolute internal URLs in hand-written bodies.
  if (!absolute) {
    const bad = page.body.match(/\s(?:href|src|srcset)="\/(?!\/)[^"]*"/g);
    if (bad) throw new Error(`${source}: root-absolute URL(s) ${bad.join(', ')} — use {{root}}`);
  }

  const nav = NAV_ORDER.map((key) => {
    const cur = data.nav === key ? ' aria-current="page"' : '';
    return `      <li><a href="${root}${NAV_HREFS[lang][key]}"${cur}>${t['nav_' + key]}</a></li>`;
  });
  nav.push(`      <li><a href="${GLOBALS.repo_url}">GitHub</a></li>`);

  const altPath = data.alt !== undefined ? normAlt(data.alt) : null;
  const otherHref = root + (altPath !== null ? altPath : NAV_HREFS[other].home);
  const langSwitch = ['en', 'tr'].map((l) => l === lang
    ? `<a aria-current="true" lang="${l}">${l.toUpperCase()}</a>`
    : `<a href="${otherHref}" hreflang="${l}" lang="${l}" title="${esc(I18N[l].other_lang_name === 'English' ? 'Türkçe' : 'English')}">${l.toUpperCase()}</a>`).join('');

  let alternates = '';
  if (altPath !== null) {
    const en = lang === 'en' ? urlPath : altPath;
    const tr = lang === 'tr' ? urlPath : altPath;
    alternates = `<link rel="alternate" hreflang="en" href="${SITE_URL}${en}">\n`
      + `<link rel="alternate" hreflang="tr" href="${SITE_URL}${tr}">\n`
      + `<link rel="alternate" hreflang="x-default" href="${SITE_URL}${en}">\n`;
  }
  const extraCss = (data.css || '').split(',').map((s) => s.trim()).filter(Boolean)
    .map((n) => `<link rel="stylesheet" href="${root}assets/${n}.css?v=${VERSION}">\n`).join('')
    + (data.js || '').split(',').map((s) => s.trim()).filter(Boolean)
      .map((n) => `<script src="${root}assets/${n}.js?v=${VERSION}" defer></script>\n`).join('');

  const vars = {
    ...GLOBALS, root, lang,
    title: esc(data.title), description: esc(data.description),
    og_title: esc(data.og_title || data.title),
    og_image: SITE_URL + (data.og_image || 'assets/images/og.png'),
    og_locale: OG_LOCALE[lang],
    canonical: SITE_URL + urlPath,
    robots: data.noindex === 'true' ? '<meta name="robots" content="noindex">\n' : '',
    alternates, extra_css: extraCss,
    body_class: esc(['lang-' + lang, data.body_class].filter(Boolean).join(' ')),
    home_href: root + NAV_HREFS[lang].home,
    nav_items: nav.join('\n'), lang_switch: langSwitch,
    other_lang: other, other_lang_href: otherHref,
  };
  const body = fillTokens(themeImages(sizeImages(page.body)), vars, lang);
  const html = fillTokens(LAYOUT, vars, lang).replace('{{content}}', () => body);

  const dest = path.join(OUT, outRel);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, html);
  built.push({ outRel, lang, alt: altPath, source, noindex: data.noindex === 'true' });
}

/* ───────────────────────── hand-written pages ───────────────────────── */

function renderHandwrittenPages() {
  if (!fs.existsSync(PAGES)) return;
  for (const file of walk(PAGES).filter((f) => f.endsWith('.html')).sort()) {
    const rel = path.relative(PAGES, file).split(path.sep).join('/');
    const { data, body } = parseFrontMatter(fs.readFileSync(file, 'utf8'), rel);
    renderPage({ outRel: data.out || rel, data, body, source: `website/pages/${rel}` });
  }
}

/* ═════════════════════════════════════════════════════════════════════════
 * HOOK: Markdown docs pipeline
 *
 * renderMarkdownDocs() turns the public Markdown files into pages of the
 * same shape renderPage() takes ({ outRel, data, body, source }). Per page:
 *   1. GitHub alert blockquotes (> [!NOTE] / [!TIP] / [!IMPORTANT] /
 *      [!WARNING] / [!CAUTION]) become <div class="callout callout-…"> in the
 *      Markdown itself, so the result does not depend on the pandoc version.
 *   2. pandoc -f gfm -t html5 (fragment, no section divs, with highlighting).
 *   3. Post-processing: links between docs → site URLs (DOC_PAGES + README →
 *      home), other repo files → github.com/…/blob/main/<path>, screenshots
 *      → {{root}}images/… wrapped in a.zoom with width/height, mermaid code
 *      blocks → div.mermaid in a figure plate (docs.js renders them), heading
 *      anchor links, line-number anchors stripped from code blocks.
 *   4. Docs chrome: left sidebar (DOC_GROUPS), "On this page" TOC from h2/h3
 *      (right column; a <details> above the content on narrow screens),
 *      prev/next, "Edit this page on GitHub" + last-commit date.
 * The changelog gets a release timeline (one section.release per version).
 * Title comes from DOC_PAGES; the meta description is DOC_PAGES.description
 * or else the first paragraph (whole sentences up to 158 characters).
 * Do NOT add internal docs (desktop-names-v2, naming, distribution,
 * profile-desktop-state, test-matrix*): links to them go to GitHub.
 * The docs landing page is hand-written: website/pages/docs/index.html.
 * ═════════════════════════════════════════════════════════════════════════ */
const DOC_PAGES = [
  { key: 'guide', src: 'docs/guide.md', url: 'docs/guide/', lang: 'en', alt: 'tr/docs/kilavuz/', group: 'start', title: 'User guide', nav: 'User guide' },
  { key: 'kilavuz', src: 'docs/kilavuz.md', url: 'tr/docs/kilavuz/', lang: 'tr', alt: 'docs/guide/', group: 'start', title: 'Kullanım kılavuzu', nav: 'Kullanım kılavuzu', tag: 'TR' },
  { key: 'reference', src: 'docs/reference.md', url: 'docs/reference/', lang: 'en', group: 'ref', title: 'Reference', nav: 'Reference', nav_tr: 'Başvuru',
    description: 'Every rule, every setting, every failure mode of Deskmap: pins, modes, desktops, profiles, backups, automation, shortcuts, troubleshooting and limitations.' },
  { key: 'architecture', src: 'docs/architecture.md', url: 'docs/architecture/', lang: 'en', group: 'ref', title: 'Architecture', nav: 'Architecture', nav_tr: 'Mimari',
    description: 'How Deskmap is put together: the main types, what happens during a sweep, the retry limits, the data files and how localization works.' },
  { key: 'privacy', src: 'docs/privacy.md', url: 'privacy/', lang: 'en', group: 'project', title: 'Privacy', nav: 'Privacy', nav_tr: 'Gizlilik', siteNav: 'none' },
  { key: 'changelog', src: 'CHANGELOG.md', url: 'changelog/', lang: 'en', group: 'project', title: 'Changelog', nav: 'Changelog', nav_tr: 'Değişiklikler', siteNav: 'changelog', tocDepth: 2,
    description: 'Every notable change to Deskmap, release by release: what was added, changed and fixed, and what is done but not released yet.' },
];
const DOC_GROUPS = ['start', 'ref', 'project'];
/* Reading order for prev/next. The Turkish guide sits outside the EN chain
 * and continues into the reference. */
const DOC_CHAIN = { en: ['guide', 'reference', 'architecture', 'privacy', 'changelog'], tr: ['kilavuz', 'reference'] };
/* Docs UI strings (kept here, not in I18N, so the docs pipeline is
 * self-contained). */
const DOCS_UI = {
  en: {
    docs: 'Docs', all_docs: 'All docs', on_this_page: 'On this page', doc_nav: 'Documentation',
    g_start: 'Get started', g_ref: 'Reference', g_project: 'Project',
    prev: 'Previous', next: 'Next', edit: 'Edit this page on GitHub', updated: 'Last change',
    source: 'Source', anchor: 'Link to this section', diagram: 'Diagram', diagram_note: 'rendered from the Mermaid source in',
    unreleased: 'Unreleased', latest: 'Latest', in_progress: 'Not released yet', back_top: 'Back to top',
  },
  tr: {
    docs: 'Belgeler', all_docs: 'Tüm belgeler', on_this_page: 'Bu sayfada', doc_nav: 'Belgeler',
    g_start: 'Başlarken', g_ref: 'Başvuru', g_project: 'Proje',
    prev: 'Önceki', next: 'Sonraki', edit: 'Bu sayfayı GitHub’da düzenle', updated: 'Son değişiklik',
    source: 'Kaynak', anchor: 'Bu bölümün bağlantısı', diagram: 'Diyagram', diagram_note: 'Mermaid kaynağından çizildi:',
    unreleased: 'Yayımlanmadı', latest: 'Son sürüm', in_progress: 'Henüz yayımlanmadı', back_top: 'Başa dön',
  },
};
/* Repo files that moved after old docs (mostly the changelog) linked them. */
const MOVED = { 'docs/app-store-submission.md': 'appstore/submission.md' };
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function pandoc(markdown, source) {
  const bin = process.env.PANDOC || (fs.existsSync('/opt/homebrew/bin/pandoc') ? '/opt/homebrew/bin/pandoc' : 'pandoc');
  const r = spawnSync(bin, ['-f', 'gfm', '-t', 'html5', '--wrap=none'], { input: markdown, encoding: 'utf8', maxBuffer: 64 << 20 });
  if (r.error || r.status !== 0) throw new Error(`pandoc failed on ${source}: ${r.error?.message || r.stderr}`);
  return r.stdout;
}

/** > [!NOTE] blockquotes → raw HTML callout around the inner Markdown. */
function alertsToCallouts(md, lang) {
  const names = lang === 'tr'
    ? { note: 'Not', tip: 'İpucu', important: 'Önemli', warning: 'Uyarı', caution: 'Dikkat' }
    : { note: 'Note', tip: 'Tip', important: 'Important', warning: 'Warning', caution: 'Caution' };
  const kind = { note: 'note', tip: 'tip', important: 'tip', warning: 'warn', caution: 'warn' };
  const lines = md.split('\n');
  const out = [];
  let inFence = false;
  for (let i = 0; i < lines.length; i++) {
    if (/^\s*(```|~~~)/.test(lines[i])) inFence = !inFence;
    const m = !inFence && /^>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$/i.exec(lines[i]);
    if (!m) { out.push(lines[i]); continue; }
    const t = m[1].toLowerCase();
    const inner = [];
    while (i + 1 < lines.length && /^>/.test(lines[i + 1])) inner.push(lines[++i].replace(/^>\s?/, ''));
    out.push(`<div class="callout callout-${kind[t]}">`, `<p class="callout-title">${names[t]}</p>`, '', ...inner, '', '</div>');
  }
  return out.join('\n');
}

const stripTags = (s) => s.replace(/<[^>]+>/g, '');
const decodeEntities = (s) => s
  .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(+n)).replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
  .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&');
const plain = (html) => decodeEntities(stripTags(html)).replace(/\s+/g, ' ').trim();

function summarize(html) {
  const p = /<p>([\s\S]*?)<\/p>/.exec(html.replace(/^[\s\S]*?<\/h1>/, ''));
  let s = p ? plain(p[1]) : '';
  if (s.length > 158) {
    // Whole sentences if they fit, else cut at a word.
    const sentences = s.match(/[^.!?]+[.!?]+(\s|$)/g) || [];
    let fit = '';
    for (const x of sentences) { if ((fit + x).trim().length > 158) break; fit += x; }
    s = fit.trim() || s.slice(0, 157).replace(/[\s,;:—–-]+\S*$/, '') + '…';
  }
  return s;
}

/** Width/height of a PNG from its IHDR chunk (null for anything else). */
function pngSize(file) {
  try {
    const b = Buffer.alloc(24);
    const fd = fs.openSync(file, 'r'); fs.readSync(fd, b, 0, 24, 0); fs.closeSync(fd);
    if (b.toString('latin1', 12, 16) !== 'IHDR') return null;
    return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) };
  } catch { return null; }
}

/** Source file that ships as _site/images/<l>/<name> (web copy if present). */
function shippedImage(rel) { // rel: "images/en/01-map.png"
  const sub = rel.replace(/^images\//, '');
  const web = path.join(SHOTS, sub);
  return fs.existsSync(web) ? web : path.join(REPO, 'docs/images', sub);
}

/** <img src="{{root}}images/..."> → width/height of the shipped file. An
 *  explicit width smaller than the file is kept and the height scaled. */
function sizeImages(html) {
  return html.replace(/<img\b[^>]*>/g, (tag) => {
    const src = /\ssrc="\{\{root\}\}(images\/[^"]+\.png)"/.exec(tag)?.[1];
    if (!src) return tag;
    const size = pngSize(shippedImage(src));
    if (!size) return tag;
    const hadH = /\sheight="\d+"/.test(tag);
    let w = +(/\swidth="(\d+)"/.exec(tag)?.[1] || size.w);
    if (hadH || w > size.w) w = size.w; // explicit full size from the original → shipped size
    const h = Math.round(size.h * w / size.w);
    return tag.replace(/\s(?:width|height)="\d+"/g, '').replace(/^<img\b/, `<img width="${w}" height="${h}"`);
  });
}

/** A screenshot with a light twin (website/shots/<l>/light/<name>) becomes two
 *  <img>: .shot-dark and .shot-light; site.css shows the one matching the
 *  page theme (system setting or the toggle). Lazy hidden copies never load. */
function themeImages(html) {
  return html.replace(/<img\b[^>]*>/g, (tag) => {
    const m = /\ssrc="\{\{root\}\}images\/(en|tr)\/([^"/]+\.png)"/.exec(tag);
    if (!m || !fs.existsSync(path.join(SHOTS, m[1], 'light', m[2]))) return tag;
    const withClass = (t, c) => /\sclass="/.test(t) ? t.replace(/\sclass="/, ` class="${c} `) : t.replace(/^<img\b/, `<img class="${c}"`);
    const light = tag.replace(m[0], ` src="{{root}}images/${m[1]}/light/${m[2]}"`);
    return withClass(tag, 'shot-dark') + withClass(light, 'shot-light');
  });
}

function lastChange(src) {
  const r = spawnSync('git', ['log', '-1', '--format=%cs', '--', src], { cwd: REPO, encoding: 'utf8' });
  return r.status === 0 ? r.stdout.trim() : '';
}

/** Site-relative URL (without {{root}}) for a repo file, or null. */
function siteUrlForRepoPath(repoPath, lang) {
  const doc = DOC_PAGES.find((d) => d.src === repoPath);
  if (doc) return doc.url;
  if (repoPath === 'README.md') return NAV_HREFS[lang].home;
  return null;
}

function rewriteUrls(html, d) {
  const dir = path.posix.dirname(d.src);
  return html.replace(/(\s(?:href|src))="([^"]*)"/g, (all, attr, url) => {
    if (!url || /^(?:[a-z][a-z0-9+.-]*:|\/\/|#|\{\{)/i.test(url)) return all;
    const hashAt = url.indexOf('#');
    const p = hashAt < 0 ? url : url.slice(0, hashAt);
    const frag = hashAt < 0 ? '' : url.slice(hashAt);
    let resolved = path.posix.normalize(path.posix.join(dir, decodeURI(p)));
    resolved = MOVED[resolved] || resolved;
    if (resolved.startsWith('..')) { warn(`${d.src}: link outside the repo: ${url}`); return all; }
    const site = siteUrlForRepoPath(resolved, d.lang);
    if (site !== null) return `${attr}="{{root}}${site}${frag}"`;
    if (resolved.startsWith('docs/images/')) return `${attr}="{{root}}${resolved.slice('docs/'.length)}"`;
    const abs = path.join(REPO, resolved);
    if (!fs.existsSync(abs)) warn(`${d.src}: link to a missing repo file: ${url}`);
    const kind = fs.existsSync(abs) && fs.statSync(abs).isDirectory() ? 'tree' : 'blob';
    return `${attr}="${GLOBALS.repo_url}/${kind}/main/${resolved}${frag}"`;
  });
}

/** Screenshots: lazy, sized, click to enlarge; align="right" floats the link. */
function enhanceImages(html, lang) {
  return html.replace(/<img\b([^>]*?)\s*\/?>/g, (all, attrs) => {
    const src = /\ssrc="([^"]+)"/.exec(attrs)?.[1];
    if (!src || !src.startsWith('{{root}}images/')) return all;
    const right = /\salign="right"/.test(attrs);
    let a = attrs.replace(/\salign="[^"]*"/, '');
    if (!/\sloading=/.test(a)) a += ' loading="lazy" decoding="async"';
    return `<a class="zoom${right ? ' zoom-right' : ''}" href="${src}" aria-label="${esc(I18N[lang].zoom)}"><img${a}></a>`;
  });
}

function anchorHeadings(html, ui) {
  return html.replace(/<(h[2-4]) id="([^"]+)"([^>]*)>([\s\S]*?)<\/\1>/g, (all, tag, id, rest, inner) =>
    `<${tag} id="${id}"${rest}>${inner}<a class="anchor" href="#${id}" aria-label="${esc(ui.anchor)}">#</a></${tag}>`);
}

function mermaidFigures(html, d, ui, counter) {
  return html.replace(/<pre class="mermaid"><code>([\s\S]*?)<\/code><\/pre>/g, (all, code, at) => {
    counter.n += 1;
    // Name the diagram after the section it illustrates.
    const heads = [...html.slice(0, at).matchAll(/<h[2-4][^>]*>([\s\S]*?)<\/h[2-4]>/g)];
    const sect = heads.length ? plain(heads[heads.length - 1][1]) : '';
    const label = sect ? `${ui.diagram}: ${sect}` : `${ui.diagram} ${counter.n}`;
    return `<figure class="plate diagram"><div class="mermaid" role="img" aria-label="${esc(label)}">${code}</div>`
      + `<figcaption><span><b>Fig. ${counter.n}</b> · ${esc(ui.diagram)}</span><span>${esc(ui.diagram_note)} <a href="${GLOBALS.repo_url}/blob/main/${d.src}">${d.src}</a></span></figcaption></figure>`;
  });
}

function collectToc(html, depth) {
  const items = [];
  const re = /<(h[23]) id="([^"]+)"[^>]*>([\s\S]*?)<\/\1>/g;
  for (const m of html.matchAll(re)) {
    const level = +m[1][1];
    if (level > depth) continue;
    const label = m[3].replace(/<a class="anchor"[\s\S]*?<\/a>/, '').replace(/<time[\s\S]*?<\/time>|<span class="rel-tag[^"]*">[\s\S]*?<\/span>/g, '');
    items.push({ level, id: m[2], html: stripTags(label).trim() });
  }
  return items;
}
function tocList(items) {
  return '<ol>' + items.map((i) => `<li class="toc-h${i.level}"><a href="#${i.id}">${i.html}</a></li>`).join('') + '</ol>';
}

/** CHANGELOG: one <section class="release"> per "## [x.y.z] — date". */
function changelogTimeline(html, ui) {
  const parts = html.split(/(?=<h2 )/);
  return parts.map((chunk, idx) => {
    if (idx === 0) return chunk;
    const m = /^<h2 id="[^"]*"[^>]*>([\s\S]*?)<\/h2>/.exec(chunk);
    if (!m) return chunk;
    const text = plain(m[1]);
    const v = /^\[?([^\]\s—–]+)\]?\s*(?:[—–-]\s*(\d{4}-\d{2}-\d{2}))?/.exec(text);
    const ver = v ? v[1] : text;
    const date = v && v[2];
    const unreleased = /^unreleased$/i.test(ver);
    const id = unreleased ? 'unreleased' : 'v' + ver;
    let tag = '';
    if (unreleased) tag = `<span class="rel-tag rel-tag-next">${esc(ui.in_progress)}</span>`;
    else if (ver === VERSION) tag = `<span class="rel-tag">${esc(ui.latest)}</span>`;
    const when = date ? `<time datetime="${date}">${+date.slice(8)} ${MONTHS[+date.slice(5, 7) - 1]} ${date.slice(0, 4)}</time>` : '';
    const h2 = `<h2 id="${id}"><span class="rel-ver">${esc(unreleased ? ui.unreleased : ver)}</span>${when}${tag}</h2>`;
    return `<section class="release${unreleased ? ' release-next' : ''}">${h2}${chunk.slice(m[0].length)}</section>\n`;
  }).join('');
}

/** Link text for doc d as shown on page cur: a Turkish name on TR pages when
 *  there is one, else the page's own title marked with its language, plus an
 *  EN/TR tag when the target is in the other language. */
function docLabel(d, cur) {
  const tr = cur.lang === 'tr' && d.nav_tr;
  const text = tr ? d.nav_tr : d.nav;
  const textLang = tr ? 'tr' : d.lang;
  const inner = textLang !== cur.lang ? `<span lang="${textLang}">${esc(text)}</span>` : esc(text);
  const tagText = d.tag || (d.lang !== cur.lang ? d.lang.toUpperCase() : '');
  return inner + (tagText ? ` <span class="doc-tag" lang="en">${tagText}</span>` : '');
}

function docsSidebar(cur, ui) {
  const groups = DOC_GROUPS.map((g, gi) => {
    // A page that exists in both languages is listed only in the reader's own;
    // the EN/TR switch leads to the other one.
    const links = DOC_PAGES.filter((d) => d.group === g && !(d.alt && d.lang !== cur.lang)).map((d) => {
      const here = d.key === cur.key ? ' aria-current="page"' : '';
      return `<li><a href="{{root}}${d.url}"${here}${d.lang !== cur.lang ? ` hreflang="${d.lang}"` : ''}>${docLabel(d, cur)}</a></li>`;
    }).join('');
    return `<div class="docs-group"><p class="label"><b>0${gi + 1}</b> · ${esc(ui['g_' + g])}</p><ul>${links}</ul></div>`;
  }).join('\n');
  return `<aside class="docs-side">
  <button class="docs-nav-toggle" type="button" aria-expanded="false" aria-controls="docs-nav"><span class="label">${esc(ui.docs)}</span><span class="cur">${esc(cur.nav)}</span><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg></button>
  <nav class="docs-nav" id="docs-nav" aria-label="${esc(ui.doc_nav)}">
    <a class="docs-home" href="{{root}}docs/">← ${esc(ui.all_docs)}</a>
${groups}
  </nav>
</aside>`;
}

function pager(cur, ui) {
  const chain = DOC_CHAIN[cur.lang];
  const i = chain.indexOf(cur.key);
  const at = (k) => DOC_PAGES.find((d) => d.key === k);
  const prev = i > 0 ? at(chain[i - 1]) : null;
  const next = i >= 0 && i < chain.length - 1 ? at(chain[i + 1]) : null;
  const card = (d, dir) => d
    ? `<a class="pager-${dir}" href="{{root}}${d.url}" rel="${dir}"${d.lang !== cur.lang ? ` hreflang="${d.lang}"` : ''}><span class="label">${dir === 'prev' ? '← ' + esc(ui.prev) : esc(ui.next) + ' →'}</span><span class="pager-t">${docLabel(d, cur)}</span></a>`
    : '<span></span>';
  return prev || next ? `<nav class="pager" aria-label="${esc(ui.prev)} / ${esc(ui.next)}">${card(prev, 'prev')}${card(next, 'next')}</nav>` : '';
}

function renderMarkdownDocs() {
  const pages = [];
  const groupName = (d) => DOCS_UI[d.lang]['g_' + d.group];
  for (const d of DOC_PAGES) {
    const ui = DOCS_UI[d.lang];
    const md = alertsToCallouts(fs.readFileSync(path.join(REPO, d.src), 'utf8'), d.lang);
    let html = pandoc(md, d.src);
    const description = d.description || summarize(html) || `${d.title} — Deskmap documentation.`;

    html = html.replace(/<a href="#cb\d+-\d+"[^>]*><\/a>/g, ''); // pandoc line anchors
    html = rewriteUrls(html, d);
    html = enhanceImages(html, d.lang);
    html = html.replace(/<br clear="(?:right|all|both)"\s*\/?>/g, '<div class="clear"></div>');
    html = mermaidFigures(html, d, ui, { n: 0 });
    // A hand-made contents list right after the intro duplicates the TOC.
    html = html.replace(/<ul>\s*(?:<li><a href="#[^"]*">[^<]*<\/a><\/li>\s*){4,}<\/ul>/, '');
    if (d.key === 'changelog') html = changelogTimeline(html, ui);
    if (d.key === 'privacy') html = html.replace(/(<h2 id="türkçe-özet")/, '<div class="lang-block" lang="tr">$1') + (html.includes('id="türkçe-özet"') ? '</div>' : '');
    html = anchorHeadings(html, ui);

    const toc = collectToc(html, d.tocDepth || 3);
    if (toc.length) {
      // Narrow screens: a collapsible TOC after the intro, before the first section.
      html = html.replace(/(?:<hr \/>\s*)?<h2 /, (m) => `<details class="toc-inline"><summary>${esc(ui.on_this_page)}</summary>${tocList(toc)}</details>\n${m}`);
    }
    const date = lastChange(d.src);
    const meta = `<div class="doc-meta">
  <a class="text-link" href="${GLOBALS.repo_url}/edit/main/${d.src}">${esc(ui.edit)}</a>
  <span>${esc(ui.source)} <a href="${GLOBALS.repo_url}/blob/main/${d.src}"><code>${d.src}</code></a></span>
  ${date ? `<span>${esc(ui.updated)} <time datetime="${date}">${date}</time></span>` : ''}
</div>`;
    const body = `<div class="docs-shell${d.key === 'changelog' ? ' docs-changelog' : ''}">
${docsSidebar(d, ui)}
<div class="docs-main">
  <p class="label doc-crumb"><a href="{{root}}docs/"><b>§ ${esc(ui.docs)}</b></a> · ${esc(groupName(d))}</p>
  <article class="prose doc">
${html}
  </article>
  <footer class="doc-foot">
${pager(d, ui)}
${meta}
  </footer>
</div>
${toc.length ? `<aside class="docs-toc"><nav aria-label="${esc(ui.on_this_page)}"><p class="label">${esc(ui.on_this_page)}</p>${tocList(toc)}<a class="toc-top" href="#main">↑ ${esc(ui.back_top)}</a></nav></aside>` : ''}
</div>`;
    pages.push({
      outRel: d.url + 'index.html', source: d.src, body,
      data: {
        title: `${d.title} — Deskmap`, description, lang: d.lang, nav: d.siteNav || 'docs',
        alt: d.alt, css: 'docs', js: 'docs', body_class: `page-doc doc-${d.key}`,
      },
    });
  }
  return pages;
}

/* ───────────────────────── sitemap.xml + robots.txt ───────────────────────── */

function writeSitemap() {
  const rows = built.filter((b) => b.outRel !== '404.html' && !b.noindex).sort((a, b) => a.outRel.localeCompare(b.outRel)).map((b) => {
    const url = SITE_URL + urlPathFor(b.outRel);
    let alts = '';
    if (b.alt !== null && b.alt !== undefined) {
      const en = b.lang === 'en' ? urlPathFor(b.outRel) : b.alt;
      const tr = b.lang === 'tr' ? urlPathFor(b.outRel) : b.alt;
      alts = `\n    <xhtml:link rel="alternate" hreflang="en" href="${esc(SITE_URL + en)}"/>`
        + `\n    <xhtml:link rel="alternate" hreflang="tr" href="${esc(SITE_URL + tr)}"/>`
        + `\n    <xhtml:link rel="alternate" hreflang="x-default" href="${esc(SITE_URL + en)}"/>`;
    }
    return `  <url>\n    <loc>${esc(url)}</loc>${alts}\n  </url>`;
  });
  fs.writeFileSync(path.join(OUT, 'sitemap.xml'), '<?xml version="1.0" encoding="UTF-8"?>\n'
    + '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
    + rows.join('\n') + '\n</urlset>\n');
  // Crawlers only read robots.txt at the host root; under a GitHub Pages
  // sub-path this file is informational until a custom domain is used.
  fs.writeFileSync(path.join(OUT, 'robots.txt'), `User-agent: *\nAllow: /\n\nSitemap: ${SITE_URL}sitemap.xml\n`);
}

/* ───────────────────────── assets ───────────────────────── */

function copyAssets() {
  fs.cpSync(path.join(WEB, 'assets'), path.join(OUT, 'assets'), { recursive: true });
  for (const l of ['en', 'tr']) {
    const dest = path.join(OUT, 'images', l);
    fs.mkdirSync(dest, { recursive: true });
    const lightSrc = path.join(SHOTS, l, 'light');
    if (fs.existsSync(lightSrc)) fs.cpSync(lightSrc, path.join(dest, 'light'), { recursive: true });
    for (const f of fs.readdirSync(path.join(REPO, 'docs/images', l))) {
      const web = path.join(SHOTS, l, f);
      if (!fs.existsSync(web)) warn(`website/shots/${l}/${f} missing: shipping the full-size docs/images copy (run make site-shots)`);
      fs.copyFileSync(fs.existsSync(web) ? web : path.join(REPO, 'docs/images', l, f), path.join(dest, f));
    }
  }
  fs.writeFileSync(path.join(OUT, '.nojekyll'), '');
}

/* ───────────────────────── link check ───────────────────────── */

function checkLinks() {
  const re = /\s(?:href|src)="([^"]+)"/g;
  for (const b of built) {
    if (b.outRel === '404.html') continue;
    const file = path.join(OUT, b.outRel);
    const html = fs.readFileSync(file, 'utf8');
    for (const m of html.matchAll(re)) {
      let u = m[1];
      if (/^(?:[a-z]+:|\/\/|#|data:)/i.test(u)) continue;
      u = u.replace(/[?#].*$/, '');
      if (!u) continue;
      let target = path.resolve(path.dirname(file), decodeURI(u));
      if (u.endsWith('/') || (fs.existsSync(target) && fs.statSync(target).isDirectory())) target = path.join(target, 'index.html');
      if (!target.startsWith(OUT)) { warn(`${b.outRel}: link escapes the site: ${m[1]}`); continue; }
      if (!fs.existsSync(target)) warn(`${b.outRel}: broken link ${m[1]}`);
    }
  }
}

/* ───────────────────────── main ───────────────────────── */

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(OUT, { recursive: true });
copyAssets();
renderHandwrittenPages();
const handwritten = new Set(built.map((b) => b.outRel));
for (const p of renderMarkdownDocs()) {
  if (handwritten.has(p.outRel)) { warn(`${p.outRel}: hand-written page wins over ${p.source}`); continue; }
  renderPage(p);
}
checkLinks();
writeSitemap();

const uniq = [...new Set(warnings)];
console.log(`Built ${built.length} pages into ${path.relative(REPO, OUT)}/ (version ${VERSION}, site ${SITE_URL})`);
if (uniq.length) {
  console.log(`${uniq.length} warning(s):`);
  for (const w of uniq.slice(0, 60)) console.log('  - ' + w);
  if (uniq.length > 60) console.log(`  … and ${uniq.length - 60} more`);
  if (STRICT) process.exit(1);
}
