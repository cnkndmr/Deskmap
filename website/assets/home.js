/* Deskmap website — home page behaviour (pages/index.html, layout: bare; TR: pages/tr/index.html).
   Scroll-scrubbed scenes (#plug, #map, #free, #privacy) and the explorable map.
   The theme toggle and the mobile menu are in assets/cine.js (shared header).
   No dependencies; loaded deferred, after cine.js.

   Strings: everything visible comes from the page markup, so a translated page
   needs no change here:
     - map parts: <template id="mapRegions"> (data-chip, h3, p, figure)
     - plan status line: #plan-label text + the pressed .plan button's text
     - typed automation URLs: the <code> items of #urlList
   The few strings this script composes itself are in STR below, one object
   per language (document.documentElement.lang); a missing key falls back to en.

   Theme: same convention as site.js: data-theme="light|dark" on <html>, the
   choice stored in localStorage 'deskmap-theme'; ?theme= is applied (not stored)
   by the pre-paint script in the shared head. Screenshot twins (.shot-dark /
   .shot-light) are made by the build and switched by CSS, also inside the map
   card, which clones its screenshot from the template. */
(function () {
  var STR = {
    en: {
      of: '{k} of {n}',               // map card counter
      prev: 'Previous: {t}', next: 'Next: {t}', // map card buttons (aria-label)
      dial_set: 'set free move', dial_left: 'free move left', // free move dial, under the time
      dial_home: 'Home.', dial_home_sub: 'back on its pin',     // dial when the time is up
      // backups beat: [label, number of marks, retention, kept forever]
      tracks: [['Hourly', 24, 'kept a day', false], ['Daily', 7, 'kept a week', false], ['Weekly', 9, 'kept forever', true]]
    },
    tr: {
      of: '{k} / {n}',
      prev: 'Önceki: {t}', next: 'Sonraki: {t}',
      dial_set: 'süre ayarlanıyor', dial_left: 'kalan serbest süre',
      dial_home: 'Yerinde.', dial_home_sub: 'sabit yerine döndü',
      tracks: [['Saatlik', 24, 'bir gün saklanır', false], ['Günlük', 7, 'bir hafta saklanır', false], ['Haftalık', 9, 'süresiz saklanır', true]]
    }
  };
  var LANG = (document.documentElement.lang || 'en').slice(0, 2);
  function S(key, vars) {
    var s = (STR[LANG] && STR[LANG][key] !== undefined) ? STR[LANG][key] : STR.en[key];
    if (vars && typeof s === 'string') s = s.replace(/\{(\w+)\}/g, function (m, k) { return k in vars ? vars[k] : m; });
    return s;
  }

  var root = document.documentElement;
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  var sysDark = window.matchMedia('(prefers-color-scheme: dark)');
  var phone = window.matchMedia('(max-width: 600px)'), coarse = window.matchMedia('(pointer: coarse)');
  var shortL = window.matchMedia('(max-height: 520px) and (orientation: landscape) and (min-width: 601px)');
  function isStatic() { return reduce.matches || shortL.matches; }

  /* Theme toggle (#themeBtn) and mobile menu (#menuBtn): assets/cine.js, loaded
     before this file (front matter `js: cine, home`). themeBtn is only used here
     to preload the other theme's screenshots. */
  var themeBtn = document.getElementById('themeBtn');

  /* ---------- backups tracks (built here to keep the markup short) ---------- */
  var tracks = document.getElementById('tracks');
  S('tracks').forEach(function (t) {
    var row = document.createElement('div'); row.className = 'track-row';
    var dots = '';
    for (var i = 0; i < t[1]; i++) dots += '<i style="--k:' + i + '"></i>';
    if (t[3]) dots += '<span class="inf">∞</span>';
    row.innerHTML = '<b>' + t[0] + '</b><span class="tr">' + dots + '</span><small>' + t[2] + '</small>';
    tracks.appendChild(row);
  });

  /* ---------- reveal on scroll ---------- */
  var rvs = document.querySelectorAll('.rv');
  if ('IntersectionObserver' in window && !reduce.matches) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -12% 0px', threshold: 0.08 });
    rvs.forEach(function (el) { io.observe(el); });
  } else { rvs.forEach(function (el) { el.classList.add('in'); }); }
  // Fallback for jumps (anchor links, restored scroll): reveal anything already above the fold line.
  var pendingRv = [].slice.call(rvs);
  function sweepRv() {
    if (!pendingRv.length) return;
    var lim = window.innerHeight * 0.92;
    pendingRv = pendingRv.filter(function (el) {
      if (el.classList.contains('in')) return false;
      if (el.getBoundingClientRect().top < lim) { el.classList.add('in'); return false; }
      return true;
    });
  }

  var hero = document.querySelector('.hero');
  if ('IntersectionObserver' in window && hero) {
    new IntersectionObserver(function (es) { hero.classList.toggle('off', !es[0].isIntersecting); }).observe(hero);
  }

  /* ---------- feature beats: animate only while on screen ---------- */
  var beats = document.querySelectorAll('.beat');
  var urlLive = false;
  if ('IntersectionObserver' in window) {
    var bio = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        e.target.classList.toggle('live', e.isIntersecting);
        if (e.target.contains(urlType)) { urlLive = e.isIntersecting; if (urlLive) startTyping(); }
      });
    }, { threshold: 0.25 });
    beats.forEach(function (b) { bio.observe(b); });
  } else { beats.forEach(function (b) { b.classList.add('live'); }); }

  /* typed deskmap:// URLs */
  var urlType = document.getElementById('urlType');
  var urlItems = [].slice.call(document.querySelectorAll('#urlList li'));
  var URLS = urlItems.map(function (li) { return li.querySelector('code').textContent; });
  var typing = false, ui = 0;
  function startTyping() {
    if (typing || reduce.matches) return;
    typing = true;
    (function cycle() {
      if (!urlLive || reduce.matches) { typing = false; return; }
      var s = URLS[ui], n = 0;
      urlItems.forEach(function (li, k) { li.classList.toggle('on', k === ui); });
      (function type() {
        if (!urlLive) { typing = false; return; }
        urlType.textContent = s.slice(0, n);
        if (n < s.length) { n++; setTimeout(type, 55); }
        else setTimeout(function () { ui = (ui + 1) % URLS.length; cycle(); }, 1700);
      })();
    })();
  }

  /* ---------- helpers ---------- */
  function clamp(v, a, b) { return v < a ? a : v > b ? b : v; }
  function seg(p, a, b) { return clamp((p - a) / (b - a), 0, 1); }
  function ease(t) { return t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
  function lerp(a, b, t) { return a + (b - a) * t; }
  function progress(el) {
    var r = el.getBoundingClientRect(), total = r.height - window.innerHeight;
    return total <= 0 ? 0 : clamp(-r.top / total, 0, 1);
  }

  /* ---------- scene 1: the stage ---------- */
  var stage = document.getElementById('stage');
  var display = document.getElementById('display'), laptop = document.getElementById('laptop');
  var thumb1 = document.getElementById('thumb1'), sweep = document.getElementById('sweep');
  var wins = [].slice.call(stage.querySelectorAll('.win'));
  var tls = [].slice.call(stage.querySelectorAll('.thumbs-l'));
  var caps = [].slice.call(document.querySelectorAll('#captions p'));
  var plan = document.getElementById('plan'), planBtns = [].slice.call(plan.querySelectorAll('button'));
  var plugScene = document.getElementById('plug');
  var staticStory = document.getElementById('staticStory'), planLive = document.getElementById('planLive');
  var planLabel = document.getElementById('plan-label').textContent.trim();

  // Two choreographies in stage units. Window rect: [x, y, width, rotation]; height = width * 0.625.
  // wide: 100 x 56.25 (display left, laptop right). tall: 100 x 130 (display above, laptop below) for phones.
  var LAYOUTS = {
    wide: {
      D0: [-22, 2.6, 1], D1: [4.8, 2.6, 1],
      L0: [26, 13, 1], L1: [60.8, 21.2, .8],
      CHAOS: [[31, 15, 22, -3], [45, 17.5, 20, 4], [36, 23.5, 18, 2], [47.5, 25.5, 19, -5], [33, 19.5, 21, 1.5]],
      PLUG:  [[7.5, 5.4, 23, 0], [31.5, 5.4, 23, 0], [7.5, 20.6, 23, 0], [31.5, 20.6, 23, 0], [64.8, 22.85, 30.4, 0]],
      MAIN:  [30.6, 14.6, 38.8, 0],
      TH: function (i) { return [19 + i * 12.6, 1.4, 11.6]; }, TLY: 9.2
    },
    tall: {
      D0: [2, -40, 1.765], D1: [2, 6, 1.765],
      L0: [16.4, 50, 1.4], L1: [16.4, 86, 1.4],
      CHAOS: [[24, 54, 30, -3], [40, 56, 28, 4], [28, 62, 26, 2], [42, 64.5, 27, -5], [26, 58, 29, 1.5]],
      PLUG:  [[6.25, 10.6, 43, 0], [50.75, 10.6, 43, 0], [6.25, 38.6, 43, 0], [50.75, 38.6, 43, 0], [24, 89, 52, 0]],
      MAIN:  [24, 52.9, 52, 0],
      TH: function (i) { return [1.6 + i * 19.6, 26, 18]; }, TLY: 38.6
    }
  };
  var L = LAYOUTS.wide;
  var u = 1;
  function measure() {
    L = phone.matches ? LAYOUTS.tall : LAYOUTS.wide;
    u = stage.getBoundingClientRect().width / 100;
  }

  function place(el, x, y, s, r, o) {
    el.style.transform = 'translate3d(' + (x * u).toFixed(2) + 'px,' + (y * u).toFixed(2) + 'px,0) scale(' + s.toFixed(4) + ')' + (r ? ' rotate(' + r.toFixed(2) + 'deg)' : '');
    if (o !== undefined) el.style.opacity = o.toFixed(3);
  }
  var lastCap = -1, lastPlan = '';
  function setPlan(pl) {
    if (pl === lastPlan) return;
    plan.setAttribute('data-on', pl);
    planBtns.forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-plan') === pl)); });
    lastPlan = pl;
    staticStory.setAttribute('data-on', pl);
    planLive.textContent = planLabel + ': ' + planBtns.filter(function (b) { return b.getAttribute('data-plan') === pl; })[0].textContent;
  }
  function renderStage(p) {
    // monitor in 0.12–0.28, out 0.62–0.74
    var mIn = ease(seg(p, 0.12, 0.28)), mOut = ease(seg(p, 0.62, 0.74));
    var m = mIn * (1 - mOut);
    place(display, lerp(L.D0[0], L.D1[0], m), lerp(L.D0[1], L.D1[1], m), L.D1[2], 0, m);
    place(laptop, lerp(L.L0[0], L.L1[0], m), lerp(L.L0[1], L.L1[1], m), lerp(L.L0[2], L.L1[2], m), 0, 1);

    // the pile follows the laptop while the monitor arrives
    var Lx = lerp(L.L0[0], L.L1[0], mIn), Ly = lerp(L.L0[1], L.L1[1], mIn), ratio = lerp(L.L0[2], L.L1[2], mIn) / L.L0[2];
    wins.forEach(function (w, i) {
      var a = L.CHAOS[i], b = L.PLUG[i], c = i === 0 ? L.MAIN : L.TH(i);
      var t1 = ease(seg(p, 0.28 + i * 0.035, 0.42 + i * 0.035));
      var t2 = ease(seg(p, 0.64 + i * 0.03, 0.80 + i * 0.03));
      var ax = Lx + (a[0] - L.L0[0]) * ratio, ay = Ly + (a[1] - L.L0[1]) * ratio, aw = a[2] * ratio;
      var drift = Math.sin(p * 40 + i * 1.7) * 0.25 * (1 - t1);
      var x1 = lerp(ax, b[0], t1), y1 = lerp(ay + drift, b[1], t1), w1 = lerp(aw, b[2], t1), r1 = lerp(a[3], 0, t1);
      var lift1 = Math.sin(t1 * Math.PI) * -4, lift2 = Math.sin(t2 * Math.PI) * -5;
      var x = lerp(x1, c[0], t2), y = lerp(y1 + lift1, c[1], t2) + lift2, wd = lerp(w1, c[2], t2);
      place(w, x, y, wd / 48, r1 * (1 - t2), 1);
      w.style.setProperty('--pin', Math.max(t1 * (1 - t2), 0).toFixed(2));
    });

    // each desktop's label fades in as its window lands there (window i lands at 0.80 + i * 0.03)
    var t0 = L.TH(0);
    place(thumb1, t0[0], t0[1], 1, 0, seg(p, 0.76, 0.82));
    tls.forEach(function (el, i) { place(el, L.TH(i)[0], L.TLY, 1, 0, seg(p, 0.765 + i * 0.03, 0.815 + i * 0.03)); });

    // light sweeps across during each flight
    var s1 = seg(p, 0.28, 0.48), s2 = seg(p, 0.66, 0.86), s = s2 > 0 ? s2 : s1;
    sweep.style.opacity = (Math.sin(s * Math.PI) * 0.9).toFixed(3);
    sweep.style.transform = 'translate3d(' + (lerp(-25, 110, s) * u).toFixed(1) + 'px,0,0) rotate(14deg)';

    var ci = p < 0.12 ? 0 : p < 0.3 ? 1 : p < 0.6 ? 2 : p < 0.76 ? 3 : 4;
    if (ci !== lastCap) { caps.forEach(function (c, k) { c.classList.toggle('on', k === ci); }); lastCap = ci; }
    setPlan((p >= 0.12 && p < 0.62) ? 'monitor' : 'laptop');
  }
  // Plan buttons: scroll to that moment (or jump straight there with reduced motion)
  var staticP = 0.55;
  planBtns.forEach(function (b) {
    b.addEventListener('click', function () {
      var target = b.getAttribute('data-plan') === 'monitor' ? 0.55 : 0.995;
      if (isStatic()) { staticP = target; renderStage(staticP); return; }
      var top = plugScene.getBoundingClientRect().top + window.scrollY;
      var total = plugScene.offsetHeight - window.innerHeight;
      window.scrollTo({ top: top + total * target, behavior: 'smooth' });
    });
  });

  /* ---------- scene 2: the map, explorable ---------- */
  var mapScene = document.getElementById('map'), mapTilt = document.getElementById('mapTilt'), mapFrame = document.getElementById('mapFrame');
  var mapPan = document.getElementById('mapPan'), mapImg = document.getElementById('mapImg'), mapSpot = document.getElementById('mapSpot');
  var hotsEl = document.getElementById('hots'), legend = document.getElementById('mapLegend');
  var mapWords = [].slice.call(mapScene.querySelectorAll('.w2'));
  var card = document.getElementById('mapCard'), mcK = document.getElementById('mcK'), mcTitle = document.getElementById('mcTitle'), mcText = document.getElementById('mcText');
  var mcShot = document.getElementById('mcShot'), mcCrop = document.getElementById('mcCrop'), mcCap = document.getElementById('mcCap');
  var mcPrev = document.getElementById('mcPrev'), mcNext = document.getElementById('mcNext'), mcClose = document.getElementById('mcClose');

  // Regions of 01-map.png (1600 x 949), in reading order: r = [x, y, w, h] in image pixels,
  // a = the marker dot inside r (fractions), z = max zoom, end/start = tooltip alignment,
  // crop = the part of the related screenshot shown in the card [x, y, w, h].
  // Words and screenshots come from <template id="mapRegions"> (same data-id).
  var MAP_GEOMETRY = [
    {id: 'on', r: [14, 30, 152, 38], a: [0.81, 0.5]},
    {id: 'plan', r: [168, 30, 460, 36], a: [1.05, 0.5]},
    {id: 'search', r: [16, 68, 402, 32], a: [0.94, 0.5]},
    {id: 'view', r: [428, 68, 128, 32], a: [1.13, 0.5], crop: [390, 160, 705, 360]},
    {id: 'profile', r: [1346, 32, 128, 32], a: [-0.08, 0.5], end: 1, crop: [1146, 112, 454, 112]},
    {id: 'recent', r: [1446, 68, 146, 32], a: [-0.13, 0.5], end: 1},
    {id: 'quick', r: [16, 126, 336, 110], a: [0.93, 0.18], start: 1},
    {id: 'oneplan', r: [16, 250, 336, 262], a: [0.93, 0.075], start: 1},
    {id: 'unassigned', r: [16, 527, 336, 194], a: [0.93, 0.09], start: 1, crop: [1146, 112, 454, 300]},
    {id: 'desktop', r: [388, 130, 352, 264], a: [0.5, 0.62], crop: [395, 595, 350, 200]},
    {id: 'window', r: [924, 204, 162, 180], a: [0.5, 0.55], crop: [1146, 112, 454, 300]},
    {id: 'empty', r: [754, 406, 342, 226], a: [0.5, 0.36]},
    {id: 'add', r: [754, 645, 342, 224], a: [0.5, 0.24]},
    {id: 'inspector', r: [1150, 122, 440, 180], a: [0.93, 0.5], end: 1, crop: [1146, 200, 454, 270]},
    {id: 'footer', r: [1488, 914, 104, 30], a: [-0.14, 0.5], z: 1.6, end: 1}
  ];
  var tpl = document.getElementById('mapRegions'), tplParts = {};
  [].forEach.call(tpl.content.querySelectorAll('[data-id]'), function (el) { tplParts[el.getAttribute('data-id')] = el; });
  var REGIONS = MAP_GEOMETRY.filter(function (g) { return tplParts[g.id]; }).map(function (g) {
    var el = tplParts[g.id], fig = el.querySelector('figure');
    g.chip = el.getAttribute('data-chip');
    g.t = el.querySelector('h3').textContent.trim();
    g.d = el.querySelector('p').innerHTML.trim();
    if (fig) { g.imgs = [].slice.call(fig.querySelectorAll('img')); g.cap = fig.querySelector('figcaption').textContent.trim(); }
    return g;
  });
  var N = REGIONS.length, hsBtns = [], chips = [], active = -1, returnTo = null, ignoreScrollUntil = 0;
  REGIONS.forEach(function (g, k) {
    var b = document.createElement('button');
    b.type = 'button'; b.className = 'hs' + (g.r[1] < 140 ? ' below' : '') + (g.end ? ' end' : '') + (g.start ? ' start' : '');
    b.style.cssText = 'left:' + (g.r[0] / 16).toFixed(3) + '%;top:' + (g.r[1] / 9.49).toFixed(3) + '%;width:' + (g.r[2] / 16).toFixed(3) + '%;height:' + (g.r[3] / 9.49).toFixed(3) + '%;--k:' + k;
    b.setAttribute('aria-label', g.t); b.setAttribute('aria-expanded', 'false'); b.setAttribute('aria-controls', 'mapCard');
    b.innerHTML = '<i style="left:' + g.a[0] * 100 + '%;top:' + g.a[1] * 100 + '%"></i><b aria-hidden="true">' + g.chip + '</b>';
    b.addEventListener('click', function (e) { open(e.detail > 0 && coarse.matches ? pickAt(e.clientX, e.clientY, k) : k, true); });
    hotsEl.appendChild(b); hsBtns.push(b);
    var li = document.createElement('li'), c = document.createElement('button');
    c.type = 'button'; c.textContent = g.chip; c.tabIndex = -1; c.style.setProperty('--k', k);
    c.addEventListener('click', function () { open(k, true); });
    li.appendChild(c); legend.appendChild(li); chips.push(c);
  });
  legend.setAttribute('aria-hidden', 'true'); // a pointer shortcut; keyboard and screen readers use the hotspots

  function pickAt(x, y, fallback) {
    var box = hsBtns[0].offsetParent; if (!box) return fallback;
    var hr = box.getBoundingClientRect(), u = hr.width / 1600;
    if (!u) return fallback;
    var px = (x - hr.left) / u, py = (y - hr.top) / (hr.height / 949), best = fallback, bd = 1e9, ba = 1e12;
    REGIONS.forEach(function (g, i) {
      var r = g.r, dx = Math.max(r[0] - px, 0, px - r[0] - r[2]), dy = Math.max(r[1] - py, 0, py - r[1] - r[3]);
      var d = Math.round(Math.hypot(dx, dy) * u), a = r[2] * r[3];
      if (d < bd || (d === bd && a < ba)) { bd = d; ba = a; best = i; }
    });
    return bd <= 24 ? best : fallback;
  }
  // the template image the current theme shows (a twin pair, or one image without a light twin)
  function themedImg(g) {
    var want = isDark() ? 'shot-dark' : 'shot-light';
    return g.imgs.filter(function (im) { return im.classList.contains(want); })[0] || g.imgs.filter(function (im) { return !/\bshot-(dark|light)\b/.test(im.className); })[0] || g.imgs[0];
  }
  function preload(k) { var g = REGIONS[k]; if (g && g.imgs) { var im = new Image(); im.src = themedImg(g).getAttribute('src'); } }
  function revealHots(on) { hotsEl.classList.toggle('on', on); legend.classList.toggle('on', on); }
  function mapIsScrubbed() { return !isStatic() && !phone.matches; }
  function jumpMapTo(p) {
    var top = mapScene.getBoundingClientRect().top + window.scrollY, total = mapScene.offsetHeight - window.innerHeight;
    window.scrollTo({ top: top + total * p, behavior: 'instant' });
    frame();
  }
  function ensureRevealed() { if (mapIsScrubbed() && progress(mapScene) < 0.6) jumpMapTo(0.64); }

  function layout(k) {
    var g = REGIONS[k], FW = mapPan.clientWidth, FH = mapPan.clientHeight;
    var rx = g.r[0] / 1600, ry = g.r[1] / 949, rw = g.r[2] / 1600, rh = g.r[3] / 949, rcx = rx + rw / 2, rcy = ry + rh / 2;
    var side = phone.matches ? 0 : (rcx > 0.5 ? 'left' : 'right');
    card.classList.toggle('left', side === 'left'); card.classList.toggle('right', side === 'right');
    var cw = side ? card.offsetWidth + 24 : 0;
    var a0 = side === 'left' ? cw : 0, aw = FW - cw, pad = phone.matches ? 10 : 22;
    var s = Math.min((aw - 2 * pad) / (rw * FW), (FH - 2 * pad) / (rh * FH), phone.matches ? 3.6 : 2.5, g.z || 9);
    s = Math.max(s, 1);
    var tx = a0 + aw / 2 - s * rcx * FW, ty = FH / 2 - s * rcy * FH;
    tx = clamp(tx, FW - s * FW, 0); ty = clamp(ty, FH - s * FH, 0);
    mapImg.style.transform = 'translate3d(' + tx.toFixed(1) + 'px,' + ty.toFixed(1) + 'px,0) scale(' + s.toFixed(4) + ')';
    mapImg.style.setProperty('--s', s.toFixed(4));
    var m = 0.35; // a little air around the spotlight, in % of the image
    var sl = Math.max(rx * 100 - m, 0.25), st = Math.max(ry * 100 - m * 1.69, 0.4);
    var sr = Math.min((rx + rw) * 100 + m, 99.75), sb = Math.min((ry + rh) * 100 + m * 1.69, 99.6);
    mapSpot.style.left = sl.toFixed(2) + '%'; mapSpot.style.top = st.toFixed(2) + '%';
    mapSpot.style.width = (sr - sl).toFixed(2) + '%'; mapSpot.style.height = (sb - st).toFixed(2) + '%';
    if (!phone.matches) card.style.maxHeight = Math.min(FH - 24, window.innerHeight - 100) + 'px'; else card.style.maxHeight = '';
  }
  // if the card is taller than its room, shrink the related screenshot rather than scroll inside the card
  function fitShot() {
    var crop = document.getElementById('mcCrop');
    crop.style.width = '';
    if (mcShot.hidden) return;
    var over = card.scrollHeight - card.clientHeight;
    if (over <= 0) return;
    var w = crop.offsetWidth, h = crop.offsetHeight, f = (h - over - 2) / h;
    if (f < 0.6) mcShot.hidden = true; // too small to read: the text alone fits
    else crop.style.width = (w * f).toFixed(0) + 'px';
  }
  function fill(k) {
    var g = REGIONS[k];
    mcK.textContent = S('of', { k: k + 1, n: N });
    mcTitle.textContent = g.t;
    mcText.innerHTML = g.d;
    if (g.imgs) {
      // both theme twins go in; CSS shows the one for the current theme (the hidden lazy copy is not fetched)
      mcCrop.textContent = '';
      g.imgs.forEach(function (im) { var c = document.importNode(im, true); c.alt = g.cap; mcCrop.appendChild(c); });
      mcShot.hidden = false; mcCap.textContent = g.cap;
      var c = g.crop || [0, 0, 1600, 949], crop = mcCrop;
      crop.style.setProperty('--ar', c[2] + ' / ' + c[3]);
      crop.style.setProperty('--iw', (1600 / c[2] * 100).toFixed(2) + '%');
      crop.style.setProperty('--il', (-c[0] / c[2] * 100).toFixed(2) + '%');
      crop.style.setProperty('--it', (-c[1] / c[3] * 100).toFixed(2) + '%');
    } else { mcShot.hidden = true; mcCrop.textContent = ''; }
    mcPrev.setAttribute('aria-label', S('prev', { t: REGIONS[(k + N - 1) % N].t }));
    mcNext.setAttribute('aria-label', S('next', { t: REGIONS[(k + 1) % N].t }));
  }
  function open(k, focusTitle) {
    ensureRevealed();
    if (active >= 0) hsBtns[active].setAttribute('aria-expanded', 'false');
    active = k; returnTo = hsBtns[k];
    hsBtns[k].setAttribute('aria-expanded', 'true');
    chips.forEach(function (c, i) { c.classList.toggle('cur', i === k); });
    fill(k);
    mapFrame.classList.add('open');
    mapTilt.style.willChange = 'auto'; // a promoted parent would keep the zoomed shot blurry
    layout(k);
    fitShot();
    card.classList.add('on');
    preload((k + 1) % N);
    if (focusTitle) mcTitle.focus({ preventScroll: true });
    if (chips[k].scrollIntoView && phone.matches) { var lr = legend.getBoundingClientRect(), cr = chips[k].getBoundingClientRect(); legend.scrollLeft += cr.left - lr.left - 16; }
    if (phone.matches || isStatic()) {
      // keep the zoomed map visible above the sheet (or inside the viewport)
      ignoreScrollUntil = Date.now() + 900;
      var fr = mapTilt.getBoundingClientRect(), sheet = phone.matches ? card.offsetHeight + 16 : 0;
      if (fr.top < 60 || fr.bottom > window.innerHeight - sheet) {
        window.scrollTo({ top: window.scrollY + fr.top - 64, behavior: reduce.matches ? 'instant' : 'smooth' });
      }
    }
  }
  function close(restore) {
    if (active < 0) return;
    hsBtns[active].setAttribute('aria-expanded', 'false');
    chips.forEach(function (c) { c.classList.remove('cur'); });
    active = -1;
    mapFrame.classList.remove('open'); card.classList.remove('on'); mapTilt.style.willChange = '';
    mapImg.style.transform = ''; mapImg.style.setProperty('--s', 1);
    mapSpot.style.left = mapSpot.style.top = '0'; mapSpot.style.width = mapSpot.style.height = '100%';
    if (restore && returnTo) returnTo.focus({ preventScroll: true });
  }
  function step(d) { if (active < 0) return; open((active + d + N) % N, false); }
  mcPrev.addEventListener('click', function () { step(-1); });
  mcNext.addEventListener('click', function () { step(1); });
  mcClose.addEventListener('click', function () { close(true); });
  hotsEl.addEventListener('focusin', ensureRevealed);
  document.addEventListener('click', function (e) {
    if (active < 0) return;
    var t = e.target;
    if (card.contains(t) || (t.closest && t.closest('.hs, .map-legend button'))) return;
    close(false);
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && active >= 0) { e.preventDefault(); close(true); return; }
    var inMap = mapFrame.contains(document.activeElement);
    if (!inMap || (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight')) return;
    var d = e.key === 'ArrowRight' ? 1 : -1;
    if (active >= 0) { e.preventDefault(); step(d); }
    else {
      var i = hsBtns.indexOf(document.activeElement);
      if (i >= 0) { e.preventDefault(); hsBtns[(i + d + N) % N].focus(); }
    }
  });
  // Theme twins: start loading the other theme's screenshots before the toggle is pressed.
  var twinsLoaded = false;
  function preloadTwins() {
    if (twinsLoaded) return; twinsLoaded = true;
    [].forEach.call(document.querySelectorAll('img.shot-light, img.shot-dark'), function (im) { im.loading = 'eager'; });
  }
  themeBtn.addEventListener('pointerenter', preloadTwins); themeBtn.addEventListener('focus', preloadTwins);
  themeBtn.addEventListener('touchstart', preloadTwins, { passive: true });
  function mapScrollCheck(p) {
    if (active < 0 || Date.now() < ignoreScrollUntil) return;
    if (mapIsScrubbed()) { if (p < 0.56 || mapScene.getBoundingClientRect().bottom < window.innerHeight * 0.55) close(false); }
    else { var r = mapTilt.getBoundingClientRect(); if (r.bottom < 70 || r.top > window.innerHeight * 0.7) close(false); }
  }
  function staticMap() {
    mapTilt.style.transform = ''; mapTilt.style.opacity = '';
    mapWords.forEach(function (w) { w.style.setProperty('--o', 1); });
    revealHots(true);
  }
  function renderMap(p) {
    var e = ease(seg(p, 0, 0.55));
    mapTilt.style.transform = 'translate3d(0,' + ((1 - e) * 60).toFixed(1) + 'px,0) rotateX(' + ((1 - e) * 32).toFixed(2) + 'deg) scale(' + (0.78 + 0.22 * e).toFixed(4) + ')';
    mapTilt.style.opacity = (0.5 + 0.5 * e).toFixed(3);
    mapTilt.style.setProperty('--sx', lerp(-120, 120, seg(p, 0.45, 0.75)).toFixed(1) + '%');
    mapWords.forEach(function (w, i) { w.style.setProperty('--o', (0.35 + 0.65 * seg(p, i * 0.06, i * 0.06 + 0.1)).toFixed(3)); });
    revealHots(p > 0.58);
  }
  // pause the ping rings while the map is off screen
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (es) { mapFrame.classList.toggle('map-off', !es[0].isIntersecting); }).observe(mapFrame);
  }

  /* ---------- scene 3: free move ---------- */
  var freeScene = document.getElementById('free');
  var dialProg = document.getElementById('dialProg'), dialTime = document.getElementById('dialTime'), dialSub = document.getElementById('dialSub');
  var mini = document.getElementById('mini'), slot = document.getElementById('slot');
  var C = 552.92, lastTxt = '', lastSub = '';
  function setText(t, s) {
    if (t !== lastTxt) { dialTime.textContent = t; lastTxt = t; }
    if (s !== lastSub) { dialSub.textContent = s; lastSub = s; }
  }
  function renderFree(p) {
    var t0 = ease(seg(p, 0.04, 0.24)), t1 = seg(p, 0.28, 0.82), t2 = ease(seg(p, 0.84, 0.95));
    var frac, txt, sub;
    if (t1 <= 0) { var mm = Math.round(15 * t0); frac = 0.25 * t0; txt = mm + ':00'; sub = S('dial_set'); }
    else if (t1 < 1) { var sec = Math.round(900 * (1 - t1)); frac = sec / 3600; txt = Math.floor(sec / 60) + ':' + ('0' + (sec % 60)).slice(-2); sub = S('dial_left'); }
    else { frac = 0; txt = S('dial_home'); sub = S('dial_home_sub'); }
    dialProg.style.strokeDashoffset = (C * (1 - frac)).toFixed(2);
    setText(txt, sub);
    var f = t0 * (1 - t2), k = phone.matches ? 0.45 : 1;
    var dx = k * f * (-46 + Math.sin(p * 13) * 70), dy = f * (-34 + Math.cos(p * 9) * 12), r = f * (-6 + Math.sin(p * 10) * 4);
    mini.style.transform = 'translate3d(' + dx.toFixed(1) + 'px,' + dy.toFixed(1) + 'px,0) rotate(' + r.toFixed(2) + 'deg)';
    slot.classList.toggle('home', t2 >= 1);
  }
  function staticFree() {
    dialProg.style.strokeDashoffset = (C * 0.75).toFixed(2);
    setText('15:00', S('dial_left'));
    mini.style.transform = 'translate3d(-46px,-34px,0) rotate(-6deg)';
  }

  /* ---------- scene 4: privacy ---------- */
  var privScene = document.getElementById('privacy');
  var pws = [].slice.call(privScene.querySelectorAll('.pw')), facts = privScene.querySelector('.facts');
  function renderPriv(p) {
    var n = pws.length;
    pws.forEach(function (w, i) { w.style.setProperty('--o', (0.14 + 0.86 * seg(p, i / n * 0.7, (i + 1) / n * 0.7)).toFixed(3)); });
    facts.style.setProperty('--fo', ease(seg(p, 0.72, 0.92)).toFixed(3));
  }

  /* ---------- loop ---------- */
  var ticking = false, last = { plug: -1, map: -1, free: -1, priv: -1 }, dirty = true;
  function frame() {
    ticking = false;
    sweepRv();
    if (isStatic()) { renderStage(staticP); staticMap(); staticFree(); mapScrollCheck(1); dirty = true; return; }
    // read every scene's progress first, then write; skip scenes whose progress did not change
    var pp = progress(plugScene), pm = progress(mapScene), pf = progress(freeScene), pv = progress(privScene);
    if (dirty || pp !== last.plug) renderStage(pp);
    if (phone.matches) staticMap(); else if (dirty || pm !== last.map) renderMap(pm);
    if (dirty || pf !== last.free) renderFree(pf);
    if (dirty || pv !== last.priv) renderPriv(pv);
    last.plug = pp; last.map = pm; last.free = pf; last.priv = pv; dirty = false;
    mapScrollCheck(pm);
  }
  function req() { if (!ticking) { ticking = true; requestAnimationFrame(frame); } }
  window.addEventListener('scroll', req, { passive: true });
  window.addEventListener('resize', function () { measure(); dirty = true; if (active >= 0) { layout(active); fitShot(); } req(); });
  reduce.addEventListener && reduce.addEventListener('change', function () { if (reduce.matches) rvs.forEach(function (el) { el.classList.add('in'); }); dirty = true; req(); });
  shortL.addEventListener && shortL.addEventListener('change', function () { dirty = true; measure(); req(); });
  measure();
  frame();
})();
