/* Deskmap website — shared behaviour of the cinematic pages (layout.html and
   the home pages, which load it before home.js). Every block is
   feature-detected, so a page only gets what its markup asks for:
     #themeBtn                  light/dark toggle: data-theme on <html>, stored
                                in localStorage 'deskmap-theme' (the pre-paint
                                script in partials/head.html applies it, and ?theme=)
     #nav + #menuBtn + #navlinks  mobile menu (Escape closes, focus returns)
     .rv                        reveal on scroll (not on the home page: home.js)
     a.zoom > img               lightbox (<dialog>); the link works without JS
     .prose pre, pre.code, [data-copy]   copy buttons (data-copy = text to copy)
     .tabs[data-tabs]           segmented control: .seg > button[role=tab]
                                [aria-controls] + .tab-panel; arrow keys move
     .page-doc .lang-switch a   carries #section to the twin language page
   Strings: S below (by <html lang>). No dependencies; loaded deferred. */
(function () {
  'use strict';
  var root = document.documentElement;
  var tr = (root.lang || 'en').slice(0, 2) === 'tr';
  var S = tr ? { copy: 'Kopyala', copied: 'Kopyalandı', close: 'Kapat' }
             : { copy: 'Copy', copied: 'Copied', close: 'Close' };
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  var each = function (sel, fn, ctx) { Array.prototype.forEach.call((ctx || document).querySelectorAll(sel), fn); };

  /* ---------- theme toggle ---------- */
  var themeBtn = document.getElementById('themeBtn');
  var sysDark = window.matchMedia('(prefers-color-scheme: dark)');
  function isDark() { var t = root.getAttribute('data-theme'); return t ? t === 'dark' : sysDark.matches; }
  function syncThemeBtn() { if (themeBtn) themeBtn.setAttribute('aria-pressed', String(isDark())); }
  if (themeBtn) {
    themeBtn.addEventListener('click', function () {
      var next = isDark() ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try { localStorage.setItem('deskmap-theme', next); } catch (e) { /* private mode */ }
      syncThemeBtn();
    });
    if (sysDark.addEventListener) sysDark.addEventListener('change', syncThemeBtn);
    syncThemeBtn();
  }

  /* ---------- mobile menu ---------- */
  var nav = document.getElementById('nav'), menuBtn = document.getElementById('menuBtn');
  if (nav && menuBtn) {
    var wide = window.matchMedia('(min-width: 821px)'); // matches the 820px menu breakpoint in cine.css
    var closeMenu = function () {
      nav.classList.remove('open');
      menuBtn.setAttribute('aria-expanded', 'false');
      menuBtn.setAttribute('aria-label', menuBtn.getAttribute('data-label-open'));
    };
    menuBtn.addEventListener('click', function () {
      var open = nav.classList.toggle('open');
      menuBtn.setAttribute('aria-expanded', String(open));
      menuBtn.setAttribute('aria-label', menuBtn.getAttribute(open ? 'data-label-close' : 'data-label-open'));
    });
    each('#navlinks a', function (a) { a.addEventListener('click', closeMenu); });
    if (wide.addEventListener) wide.addEventListener('change', function () { if (wide.matches) closeMenu(); });
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && nav.classList.contains('open')) { closeMenu(); menuBtn.focus(); }
    });
  }

  /* ---------- language switch keeps the section (docs only: EN and TR docs share heading ids;
     where they differ the build puts the twin's id in data-alt-id) ---------- */
  if (document.body.classList.contains('page-doc')) {
    each('.lang-switch a[href], a[hreflang][lang]', function (a) {
      a.addEventListener('click', function () {
        var href = a.getAttribute('data-href') || a.getAttribute('href');
        if (href.indexOf('#') >= 0) return;
        a.setAttribute('data-href', href);
        if (!location.hash) { a.setAttribute('href', href); return; }
        var id = location.hash.slice(1), el = null;
        try { el = document.getElementById(decodeURIComponent(id)); } catch (e) {}
        var alt = el && el.getAttribute('data-alt-id');
        a.setAttribute('href', href + (alt ? '#' + encodeURIComponent(alt) : location.hash));
      });
    });
  }

  /* ---------- reveal on scroll (the home page runs its own in home.js) ---------- */
  if (!document.body.classList.contains('page-home')) {
    var rv = document.querySelectorAll('.rv');
    if (reduce.matches || !('IntersectionObserver' in window)) {
      each('.rv', function (el) { el.classList.add('in'); });
    } else if (rv.length) {
      var io = new IntersectionObserver(function (es) {
        es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
      }, { rootMargin: '0px 0px -8% 0px' });
      each('.rv', function (el) { io.observe(el); });
    }
  }

  /* ---------- lightbox ---------- */
  var zooms = document.querySelectorAll('a.zoom');
  if (zooms.length && typeof HTMLDialogElement === 'function') {
    var dlg = document.createElement('dialog');
    dlg.className = 'lightbox';
    dlg.innerHTML = '<button type="button" aria-label="' + S.close + '">×</button><img alt=""><p></p>';
    document.body.appendChild(dlg);
    var dImg = dlg.querySelector('img'), dCap = dlg.querySelector('p');
    dlg.querySelector('button').addEventListener('click', function () { dlg.close(); });
    dlg.addEventListener('click', function (e) { if (e.target === dlg) dlg.close(); });
    Array.prototype.forEach.call(zooms, function (a) {
      a.addEventListener('click', function (e) {
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        e.preventDefault();
        // Light/dark twins: enlarge the one the theme shows.
        var img = [].filter.call(a.querySelectorAll('img'), function (i) { return i.offsetParent !== null; })[0] || a.querySelector('img');
        dImg.src = img && img.classList.contains('shot-light') ? img.getAttribute('src') : a.getAttribute('href');
        dImg.alt = img ? img.alt : '';
        dCap.textContent = img ? img.alt : '';
        dlg.showModal();
      });
    });
  }

  /* ---------- copy buttons ---------- */
  function addCopy(box, getText) {
    if (!navigator.clipboard || box.querySelector(':scope > .copy-btn')) return;
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'copy-btn'; b.textContent = S.copy;
    b.addEventListener('click', function () {
      navigator.clipboard.writeText(getText()).then(function () {
        b.textContent = S.copied; b.classList.add('done');
        setTimeout(function () { b.textContent = S.copy; b.classList.remove('done'); }, 1600);
      }, function () {});
    });
    box.classList.add('has-copy');
    box.appendChild(b);
  }
  each('[data-copy]', function (el) { addCopy(el, function () { return el.getAttribute('data-copy'); }); });
  each('.prose pre, pre.code', function (pre) {
    if (pre.closest('[data-copy]')) return;
    var box = pre.parentElement && pre.parentElement.classList.contains('sourceCode') ? pre.parentElement : pre;
    if (box === pre) {
      // a <pre> scrolls sideways; put the button on a wrapper so it stays put
      var w = document.createElement('div');
      w.className = 'pre-wrap';
      pre.parentNode.insertBefore(w, pre); w.appendChild(pre); box = w;
    }
    addCopy(box, function () { return pre.innerText.replace(/\n$/, ''); });
  });

  /* ---------- tabs / segmented control ---------- */
  each('.tabs[data-tabs]', function (box) {
    var tabs = [].slice.call(box.querySelectorAll('.seg [role="tab"]'));
    if (!tabs.length) return;
    function select(tab, focus) {
      tabs.forEach(function (t) {
        var on = t === tab, panel = document.getElementById(t.getAttribute('aria-controls'));
        t.setAttribute('aria-selected', String(on));
        t.tabIndex = on ? 0 : -1;
        if (panel) panel.hidden = !on;
      });
      if (focus) tab.focus();
    }
    tabs.forEach(function (t, i) {
      t.addEventListener('click', function () { select(t, false); });
      t.addEventListener('keydown', function (e) {
        var k = e.key, n = tabs.length, j = -1;
        if (k === 'ArrowRight' || k === 'ArrowDown') j = (i + 1) % n;
        else if (k === 'ArrowLeft' || k === 'ArrowUp') j = (i - 1 + n) % n;
        else if (k === 'Home') j = 0; else if (k === 'End') j = n - 1;
        if (j >= 0) { e.preventDefault(); select(tabs[j], true); }
      });
    });
    select(tabs.filter(function (t) { return t.getAttribute('aria-selected') === 'true'; })[0] || tabs[0], false);
  });
})();
