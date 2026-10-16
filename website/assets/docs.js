/* Deskmap website — documentation pages (front matter `js: docs`).
     .docs-nav-toggle      mobile disclosure for the docs sidebar
     .docs-toc             "On this page" scroll-spy
     .toc-inline           closes after a jump on narrow screens
     .diagram .mermaid     Mermaid diagrams: the library (pinned version) is
                           loaded only on pages that have one; without JS or
                           if it fails, the Mermaid source stays readable.
   Copy buttons on code blocks come from site.js.                          */
(function () {
  var SELF = document.currentScript && document.currentScript.src;
  'use strict';
  var root = document.documentElement;

  /* ---------- sidebar disclosure ---------- */
  var tog = document.querySelector('.docs-nav-toggle');
  var nav = document.getElementById('docs-nav');
  if (tog && nav) {
    tog.addEventListener('click', function () {
      var open = !nav.classList.contains('open');
      nav.classList.toggle('open', open);
      tog.setAttribute('aria-expanded', open);
    });
  }

  /* ---------- scroll-spy ---------- */
  var tocLinks = Array.prototype.slice.call(document.querySelectorAll('.docs-toc a[href^="#"]:not(.toc-top)'));
  var heads = tocLinks.map(function (a) {
    try { return document.getElementById(decodeURIComponent(a.getAttribute('href').slice(1))); } catch (e) { return null; }
  });
  var current = -1, ticking = false;
  function spy() {
    ticking = false;
    var line = (parseFloat(getComputedStyle(root).getPropertyValue('--header-h')) || 64) + 40;
    var idx = -1;
    for (var i = 0; i < heads.length; i++) {
      if (heads[i] && heads[i].getBoundingClientRect().top <= line) idx = i; else if (heads[i]) break;
    }
    if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 4) idx = heads.length - 1;
    if (idx === current) return;
    if (current >= 0) tocLinks[current].classList.remove('active');
    current = idx;
    if (idx >= 0) {
      var a = tocLinks[idx];
      a.classList.add('active');
      var box = a.closest('.docs-toc');
      if (box && box.scrollHeight > box.clientHeight) {
        var r = a.getBoundingClientRect(), b = box.getBoundingClientRect();
        if (r.top < b.top + 40 || r.bottom > b.bottom - 40) box.scrollTop += r.top - b.top - b.height / 3;
      }
    }
  }
  if (tocLinks.length) {
    window.addEventListener('scroll', function () { if (!ticking) { ticking = true; requestAnimationFrame(spy); } }, { passive: true });
    window.addEventListener('resize', spy);
    spy();
  }

  /* ---------- inline TOC: close after a jump ---------- */
  document.querySelectorAll('.toc-inline').forEach(function (d) {
    d.addEventListener('click', function (e) { if (e.target.tagName === 'A') d.open = false; });
  });

  /* ---------- Mermaid diagrams ---------- */
  var diagrams = Array.prototype.slice.call(document.querySelectorAll('.diagram .mermaid'));
  if (!diagrams.length) return;
  /* Self-hosted copy (MIT) so docs pages make no third-party requests. */
  var SRC = SELF ? new URL('vendor/mermaid-10.9.1.min.js', SELF).href : 'https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js';
  var sources = diagrams.map(function (el) { return el.textContent; });

  function cssVar(n) { return getComputedStyle(root).getPropertyValue(n).trim(); }
  function render() {
    var m = window.mermaid;
    if (!m) return;
    m.initialize({
      startOnLoad: false, securityLevel: 'strict', theme: 'base',
      fontFamily: '"IBM Plex Sans", -apple-system, sans-serif',
      flowchart: { htmlLabels: true, curve: 'basis' },
      themeVariables: {
        fontSize: '14px',
        background: cssVar('--sheet'), mainBkg: cssVar('--paper-2'),
        primaryColor: cssVar('--paper-2'), primaryTextColor: cssVar('--ink'),
        primaryBorderColor: cssVar('--ink-3'), lineColor: cssVar('--ink-3'),
        textColor: cssVar('--ink'), clusterBkg: cssVar('--paper'), clusterBorder: cssVar('--ink-3'),
        edgeLabelBackground: cssVar('--sheet'), tertiaryColor: cssVar('--sheet')
      }
    });
    diagrams.forEach(function (el, i) {
      el.removeAttribute('data-processed');
      el.textContent = sources[i];
    });
    m.run({ nodes: diagrams }).then(function () {
      diagrams.forEach(function (el) { el.classList.add('is-rendered'); });
    }, function () {
      diagrams.forEach(function (el, i) { el.classList.remove('is-rendered'); el.textContent = sources[i]; });
    });
  }
  function load() {
    var s = document.createElement('script');
    s.src = SRC; s.async = true; s.crossOrigin = 'anonymous';
    s.onload = render;
    document.head.appendChild(s);
  }
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (es) {
      if (es.some(function (e) { return e.isIntersecting; })) { io.disconnect(); load(); }
    }, { rootMargin: '600px 0px' });
    diagrams.forEach(function (el) { io.observe(el); });
  } else { load(); }
  // Re-render in the other palette when the theme changes.
  var rerender = function () { if (window.mermaid) setTimeout(render, 30); };
  new MutationObserver(rerender).observe(root, { attributes: true, attributeFilter: ['data-theme'] });
  var mq = window.matchMedia('(prefers-color-scheme: dark)');
  if (mq.addEventListener) mq.addEventListener('change', rerender);
})();
