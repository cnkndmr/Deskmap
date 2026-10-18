/* Deskmap website — documentation pages (front matter `js: docs`), loaded
   after assets/cine.js, which already does the theme toggle, copy buttons on
   .prose pre, the screenshot lightbox and the EN/TR #hash carry-over.
     .docs-nav-toggle      mobile disclosure for the docs sidebar (Escape and
                           a link click close it)
     .docs-toc             "On this page" scroll-spy
     .toc-inline           closes after a jump on narrow screens
     .diagram .mermaid     Mermaid diagrams: the self-hosted library
                           (assets/vendor, pinned version) is loaded only on
                           pages that have one, themed from the cine tokens and
                           redrawn when the theme changes; without JS or if it
                           fails, the Mermaid source stays readable.
   No third-party requests.                                                 */
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
    var shut = function () { nav.classList.remove('open'); tog.setAttribute('aria-expanded', 'false'); };
    nav.addEventListener('click', function (e) { if (e.target.closest('a')) shut(); });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && nav.classList.contains('open')) { shut(); tog.focus(); }
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
    var line = (parseFloat(getComputedStyle(root).getPropertyValue('--nav-h')) || 52) + Math.min(window.innerHeight * 0.3, 240); // a heading in the top third counts as read
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
  var me = SELF || (document.querySelector('script[src*="assets/docs.js"]') || {}).src;
  if (!me) return;
  var SRC = new URL('vendor/mermaid-10.9.1.min.js', me).href;
  var sources = diagrams.map(function (el) { return el.textContent; });

  function cssVar(n) { return getComputedStyle(root).getPropertyValue(n).trim(); }
  function render() {
    var m = window.mermaid;
    if (!m) return;
    m.initialize({
      startOnLoad: false, securityLevel: 'strict', theme: 'base',
      fontFamily: cssVar('--font') || '-apple-system, BlinkMacSystemFont, sans-serif',
      flowchart: { htmlLabels: true, curve: 'basis' },
      themeVariables: {
        fontSize: '14px', fontFamily: cssVar('--font'),
        background: cssVar('--tile'), mainBkg: cssVar('--bg'),
        primaryColor: cssVar('--bg'), primaryTextColor: cssVar('--fg'),
        primaryBorderColor: cssVar('--accent'), lineColor: cssVar('--fg-3'),
        secondaryColor: cssVar('--bg-2'), secondaryBorderColor: cssVar('--fg-3'), secondaryTextColor: cssVar('--fg'),
        textColor: cssVar('--fg'), clusterBkg: cssVar('--bg-2'), clusterBorder: cssVar('--line'),
        edgeLabelBackground: cssVar('--tile'), tertiaryColor: cssVar('--bg-2'), tertiaryTextColor: cssVar('--fg'),
        nodeTextColor: cssVar('--fg'), titleColor: cssVar('--fg')
      }
    });
    diagrams.forEach(function (el, i) {
      el.removeAttribute('data-processed');
      el.textContent = sources[i];
    });
    m.run({ nodes: diagrams }).then(function () {
      diagrams.forEach(function (el) {
        el.classList.add('is-rendered');
        // A wide diagram is not shrunk below a readable size: it scrolls sideways instead.
        var svg = el.querySelector('svg'), natural = svg && parseFloat(svg.style.maxWidth);
        if (natural && natural > el.clientWidth) svg.style.minWidth = Math.round(Math.min(natural, Math.max(el.clientWidth * 1.5, 620))) + 'px';
      });
    }, function () {
      diagrams.forEach(function (el, i) { el.classList.remove('is-rendered'); el.textContent = sources[i]; });
    });
  }
  function load() {
    var s = document.createElement('script');
    s.src = SRC; s.async = true;
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
