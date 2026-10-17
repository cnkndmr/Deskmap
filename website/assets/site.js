/* Deskmap website — shared behaviour. Every block is feature-detected, so
   pages only get what their markup asks for:
     #theme-toggle            light/dark, remembered in localStorage
     #menu-btn + #nav-links   mobile nav
     .reveal                  fade in on scroll
     a.zoom > img             click-to-enlarge lightbox (link works without JS)
     .prose pre, [data-copy]  copy button (data-copy="text to copy")
     .lang-switch a           on docs pages, carries #section to the twin page
     #atlas                   home page two-setup map demo                  */
(function () {
  'use strict';
  var root = document.documentElement;
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var tr = (root.lang || 'en').slice(0, 2) === 'tr';
  var S = tr ? { copy: 'Kopyala', copied: 'Kopyalandı', close: 'Kapat' }
             : { copy: 'Copy', copied: 'Copied', close: 'Close' };

  function store(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* private mode */ } }

  /* ---------- theme ---------- */
  var tbtn = document.getElementById('theme-toggle');
  var mq = window.matchMedia('(prefers-color-scheme: dark)');
  function isDark() { var t = root.getAttribute('data-theme'); return t ? t === 'dark' : mq.matches; }
  function paintTheme() {
    if (!tbtn) return;
    tbtn.setAttribute('aria-label', isDark() ? tbtn.getAttribute('data-label-light') : tbtn.getAttribute('data-label-dark'));
  }
  if (tbtn) {
    tbtn.addEventListener('click', function () {
      var next = isDark() ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      store('deskmap-theme', next);
      paintTheme();
    });
    if (mq.addEventListener) mq.addEventListener('change', paintTheme);
    paintTheme();
  }

  /* ---------- language switch keeps the section ----------
     EN and TR docs share heading ids, so #automation-url-scheme on one is the
     same section on the other. Only on docs pages: elsewhere ids differ. */
  if (document.body.classList.contains('page-doc')) {
    document.querySelectorAll('.lang-switch a[href], a[hreflang][lang]').forEach(function (a) {
      a.addEventListener('click', function () {
        if (location.hash && a.getAttribute('href').indexOf('#') < 0) a.setAttribute('href', a.getAttribute('href') + location.hash);
      });
    });
  }

  /* ---------- mobile nav ---------- */
  var mb = document.getElementById('menu-btn'), links = document.getElementById('nav-links');
  if (mb && links) {
    var setMenu = function (open) {
      links.classList.toggle('open', open);
      mb.setAttribute('aria-expanded', open);
      mb.setAttribute('aria-label', mb.getAttribute(open ? 'data-label-close' : 'data-label-open'));
    };
    mb.addEventListener('click', function () { setMenu(!links.classList.contains('open')); });
    links.addEventListener('click', function (e) { if (e.target.tagName === 'A') setMenu(false); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && links.classList.contains('open')) { setMenu(false); mb.focus(); } });
  }

  /* ---------- reveal on scroll ---------- */
  var rv = document.querySelectorAll('.reveal');
  if (reduce || !('IntersectionObserver' in window)) {
    rv.forEach(function (el) { el.classList.add('in'); });
  } else {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px' });
    rv.forEach(function (el) { io.observe(el); });
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
    zooms.forEach(function (a) {
      a.addEventListener('click', function (e) {
        if (e.metaKey || e.ctrlKey || e.shiftKey) return;
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
    if (!navigator.clipboard) return;
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
  document.querySelectorAll('.prose pre').forEach(function (pre) {
    var box = pre.parentElement && pre.parentElement.classList.contains('sourceCode') ? pre.parentElement : pre;
    addCopy(box, function () { return pre.innerText.replace(/\n$/, ''); });
  });
  document.querySelectorAll('[data-copy]').forEach(function (el) {
    addCopy(el, function () { return el.getAttribute('data-copy'); });
  });

  /* ---------- home: two-setup map demo ---------- */
  var atlas = document.getElementById('atlas');
  if (atlas) {
    // [left, top, width, height] in % of the sheet, per plan.
    // Narrow geometry (container <= NARROW px) matches the @container rule in site.css.
    var NARROW = 520;
    var POS = {
      wide: {
        monitor: { acme: [36.3, 16.5, 13.4, 34], notes: [50.3, 16.5, 13.4, 34], deploy: [71, 21, 20.6, 24], mail: [23, 69, 15.7, 23.5] },
        laptop:  { acme: [23, 69, 15.7, 23.5], notes: [42.2, 69, 15.7, 23.5], deploy: [69.5, 69, 7.6, 23.5], mail: [61.3, 69, 7.6, 23.5] }
      },
      narrow: {
        monitor: { acme: [52.5, 13.5, 20.5, 17.5], notes: [73.5, 13.5, 20, 17.5], deploy: [8, 38, 38, 15], mail: [6.6, 71.5, 26.6, 20] },
        laptop:  { acme: [6.6, 71.5, 26.6, 20], notes: [37.2, 71.5, 26.6, 20], deploy: [67.9, 71.5, 25.6, 9.4], mail: [67.9, 82, 25.6, 9.6] }
      }
    };
    var frame = atlas.parentElement;
    var geo = function () { return frame.clientWidth <= NARROW ? POS.narrow : POS.wide; };
    var wins = atlas.querySelectorAll('.win');
    var segBtns = document.querySelectorAll('[data-atlas-plan]');
    var status = document.getElementById('atlas-status');
    var playBtn = document.getElementById('atlas-play');
    var current = 'monitor', timer = null, playing = !reduce, visible = false;

    var apply = function (plan, announce) {
      atlas.setAttribute('data-plan', plan);
      wins.forEach(function (w) {
        var p = geo()[plan][w.getAttribute('data-w')];
        w.style.left = p[0] + '%'; w.style.top = p[1] + '%'; w.style.width = p[2] + '%'; w.style.height = p[3] + '%';
      });
      segBtns.forEach(function (b) { b.setAttribute('aria-pressed', b.getAttribute('data-atlas-plan') === plan); });
      // Only user choices are announced; autoplay updates the text silently.
      if (status) { status.setAttribute('aria-live', announce ? 'polite' : 'off'); status.textContent = atlas.getAttribute('data-msg-' + plan); }
    };
    var tick = function () { current = current === 'monitor' ? 'laptop' : 'monitor'; apply(current, false); };
    var sync = function () {
      clearInterval(timer); timer = null;
      if (playing && visible) timer = setInterval(tick, 3800);
      if (playBtn) {
        playBtn.textContent = atlas.getAttribute(playing ? 'data-label-pause' : 'data-label-play');
        playBtn.setAttribute('aria-pressed', playing);
      }
    };
    apply('monitor', false);
    if ('ResizeObserver' in window) {
      var lastNarrow = geo() === POS.narrow;
      new ResizeObserver(function () {
        var n = geo() === POS.narrow;
        if (n !== lastNarrow) { lastNarrow = n; apply(current, false); }
      }).observe(frame);
    }
    segBtns.forEach(function (b) {
      b.addEventListener('click', function () { current = b.getAttribute('data-atlas-plan'); apply(current, true); playing = false; sync(); });
    });
    if (playBtn) playBtn.addEventListener('click', function () { playing = !playing; sync(); });
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (es) { visible = es[0].isIntersecting; sync(); }, { threshold: 0.3 }).observe(atlas);
    } else { visible = true; }
    sync();
  }
})();
