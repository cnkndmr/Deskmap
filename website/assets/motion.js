/* Deskmap website — animated home page (pages/index.html; static version: pages/classic/).
   Loaded after site.js (front matter `js: motion`). See motion.css for the
   model: html.m-on enables motion; [data-sd] elements get a scroll progress
   --p (CSS scroll-driven animations, or the fallback below); [data-play]
   scenes run only while on screen; .m-reveal fades in once.
   With prefers-reduced-motion nothing here animates: the page keeps its
   static end state and the plug scene gets two buttons instead of scroll. */
(function () {
  'use strict';
  var root = document.documentElement;
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var finePointer = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
  var SDA = !!(window.CSS && CSS.supports && CSS.supports('animation-timeline: view()'));
  var $ = function (s, c) { return [].slice.call((c || document).querySelectorAll(s)); };

  /* ---------- plug scene: buttons when motion is reduced ---------- */
  var plug = document.getElementById('plug');
  if (reduce) {
    if (plug) {
      var ctl = plug.querySelector('.m-plug-controls');
      var btns = $('[data-plug-plan]', plug);
      if (ctl) ctl.hidden = false;
      btns.forEach(function (b) {
        b.addEventListener('click', function () {
          var plan = b.getAttribute('data-plug-plan');
          plug.style.setProperty('--p', plan === 'laptop' ? '0.5' : '0');
          btns.forEach(function (o) { o.setAttribute('aria-pressed', o === b); });
        });
      });
    }
    return;
  }
  root.classList.add('m-on');

  /* ---------- split words (interlude) and characters (terminal) ---------- */
  function splitWords(el) {
    var n = 0;
    (function walk(node) {
      [].slice.call(node.childNodes).forEach(function (c) {
        if (c.nodeType === 1) { walk(c); return; }
        if (c.nodeType !== 3 || !c.nodeValue.trim()) return;
        var frag = document.createDocumentFragment();
        c.nodeValue.split(/(\s+)/).forEach(function (part) {
          if (!part) return;
          if (/^\s+$/.test(part)) { frag.appendChild(document.createTextNode(part)); return; }
          var s = document.createElement('span');
          s.className = 'w'; s.style.setProperty('--i', n++); s.textContent = part;
          frag.appendChild(s);
        });
        node.replaceChild(frag, c);
      });
    })(el);
    el.style.setProperty('--n', n);
  }
  $('.m-words').forEach(splitWords);
  $('.m-type').forEach(function (el) {
    var text = el.textContent; el.textContent = '';
    for (var i = 0; i < text.length; i++) {
      var s = document.createElement('span');
      s.className = 'ch'; s.style.setProperty('--i', i); s.textContent = text[i];
      el.appendChild(s);
    }
  });

  /* ---------- reveals and on-screen scenes ---------- */
  var reveals = $('.m-reveal, [data-play]');
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        var el = e.target;
        if (e.isIntersecting) {
          el.classList.add('is-in');
          if (el.hasAttribute('data-play')) { el.classList.add('is-on'); start(el); }
          else io.unobserve(el);
        } else if (el.hasAttribute('data-play') && el.getAttribute('data-play') !== 'once') {
          el.classList.remove('is-on');
        }
      });
    }, { rootMargin: '0px 0px -10% 0px', threshold: 0.15 });
    reveals.forEach(function (el) { io.observe(el); });
    if (plug) {
      new IntersectionObserver(function (es) { plug.classList.toggle('is-on', es[0].isIntersecting); }).observe(plug);
    }
  } else {
    reveals.forEach(function (el) { el.classList.add('is-in', 'is-on'); start(el); });
  }

  /* final section: two windows travel the route (SVG animateMotion) */
  function start(el) {
    if (!el.classList.contains('m-final') || el._started) return;
    el._started = true;
    $('.m-route-win', el).forEach(function (g) {
      var path = document.getElementById(g.getAttribute('data-route'));
      if (!path || !g.appendChild) return;
      var NS = 'http://www.w3.org/2000/svg';
      var am = document.createElementNS(NS, 'animateMotion');
      am.setAttribute('dur', '2.6s'); am.setAttribute('begin', 'indefinite'); am.setAttribute('fill', 'freeze');
      am.setAttribute('calcMode', 'spline'); am.setAttribute('keyTimes', '0;1'); am.setAttribute('keyPoints', '0;1');
      am.setAttribute('keySplines', '.45 0 .2 1');
      var mp = document.createElementNS(NS, 'mpath');
      mp.setAttribute('href', '#' + path.id);
      mp.setAttributeNS('http://www.w3.org/1999/xlink', 'xlink:href', '#' + path.id);
      am.appendChild(mp); g.appendChild(am);
      setTimeout(function () {
        if (typeof am.beginElement !== 'function') return;
        am.beginElement(); g.classList.add('go');
        setTimeout(function () { g.classList.remove('go'); }, 2700);
      }, 200);
    });
  }

  /* ---------- scroll-progress fallback (no CSS scroll-driven animations) ---------- */
  if (!SDA) {
    // Same ranges as the @supports block in motion.css: [startRange, %, endRange, %].
    var RANGES = { 'in': ['entry', 0, 'cover', 45], words: ['cover', 12, 'cover', 52], pin: ['contain', 0, 'contain', 100], strip: ['cover', 10, 'cover', 60] };
    var sds = $('[data-sd]');
    // Viewport top of the element's box at a range point (view-timeline semantics).
    var at = function (name, pct, h, H) {
      var f = pct / 100;
      if (name === 'cover') return H - f * (H + h);
      if (name === 'entry') return H - f * Math.min(h, H);
      if (name === 'exit') return Math.min(0, H - h) - f * Math.min(h, H);
      var a = Math.max(H - h, 0), b = Math.min(0, H - h); // contain
      return a + f * (b - a);
    };
    var active = new Set(sds);
    var ticking = false;
    var compute = function (list) {
      var H = window.innerHeight, y = window.scrollY, max = Math.max(1, root.scrollHeight - H);
      var vals = [];
      list.forEach(function (el) { // read everything first, then write
        var kind = el.getAttribute('data-sd'), p;
        if (kind === 'page') p = y / max;
        else if (kind === 'top') p = y / H;
        else {
          var r = RANGES[kind] || RANGES['in'], rect = el.getBoundingClientRect();
          var s = at(r[0], r[1], rect.height, H), e = at(r[2], r[3], rect.height, H);
          p = s === e ? (rect.top <= e ? 1 : 0) : (s - rect.top) / (s - e);
        }
        vals.push([el, Math.min(1, Math.max(0, p)).toFixed(4)]);
      });
      vals.forEach(function (v) { if (v[0]._p !== v[1]) { v[0]._p = v[1]; v[0].style.setProperty('--p', v[1]); } });
    };
    var request = function () {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(function () { ticking = false; compute(active); });
    };
    if ('IntersectionObserver' in window) {
      // Only elements near the viewport are updated on scroll; one leaving it
      // gets a last update so it settles at 0 or 1.
      var near = new IntersectionObserver(function (es) {
        var changed = [];
        es.forEach(function (e) {
          var k = e.target.getAttribute('data-sd');
          changed.push(e.target);
          if (k === 'page' || k === 'top') return;
          if (e.isIntersecting) active.add(e.target); else active.delete(e.target);
        });
        compute(changed);
      }, { rootMargin: '25% 0px 25% 0px' });
      sds.forEach(function (el) { near.observe(el); });
    }
    compute(sds);
    window.addEventListener('scroll', request, { passive: true });
    window.addEventListener('resize', request);
    window.addEventListener('load', function () { compute(sds); });
  }

  /* ---------- hero: replay, pointer parallax ---------- */
  var heroFig = document.querySelector('.m-hero-fig');
  if (heroFig) {
    var replay = heroFig.querySelector('.m-replay');
    if (replay) {
      replay.hidden = false;
      replay.addEventListener('click', function () {
        heroFig.classList.add('m-hold');
        void heroFig.offsetWidth; // restart the CSS animations
        heroFig.classList.remove('m-hold');
      });
    }
    var stage = heroFig.querySelector('.m-stage');
    if (stage && finePointer) {
      var raf = 0, px = 0, py = 0;
      heroFig.addEventListener('pointermove', function (e) {
        var r = heroFig.getBoundingClientRect();
        px = (e.clientX - r.left) / r.width - 0.5; py = (e.clientY - r.top) / r.height - 0.5;
        if (!raf) raf = requestAnimationFrame(function () {
          raf = 0;
          stage.style.setProperty('--tx', (px * 5).toFixed(2) + 'deg');
          stage.style.setProperty('--ty', (py * -4).toFixed(2) + 'deg');
        });
      });
      heroFig.addEventListener('pointerleave', function () { stage.style.setProperty('--tx', '0deg'); stage.style.setProperty('--ty', '0deg'); });
    }
  }

  if (!finePointer) return;

  /* ---------- screenshot tilt on hover ---------- */
  $('.m-tilt').forEach(function (el) {
    var raf = 0, x = 0, y = 0;
    el.addEventListener('pointermove', function (e) {
      var r = el.getBoundingClientRect();
      x = (e.clientX - r.left) / r.width - 0.5; y = (e.clientY - r.top) / r.height - 0.5;
      if (!raf) raf = requestAnimationFrame(function () {
        raf = 0;
        el.style.setProperty('--rx', (x * 7).toFixed(2) + 'deg');
        el.style.setProperty('--ry', (y * -6).toFixed(2) + 'deg');
      });
    });
    el.addEventListener('pointerleave', function () { el.style.setProperty('--rx', '0deg'); el.style.setProperty('--ry', '0deg'); });
  });

  /* ---------- card spotlight ---------- */
  $('.m-spot').forEach(function (el) {
    el.addEventListener('pointermove', function (e) {
      var r = el.getBoundingClientRect();
      el.style.setProperty('--mx', (e.clientX - r.left).toFixed(0) + 'px');
      el.style.setProperty('--my', (e.clientY - r.top).toFixed(0) + 'px');
    });
  });

  /* ---------- magnetic buttons ---------- */
  $('.m-magnet').forEach(function (el) {
    var raf = 0, dx = 0, dy = 0;
    el.addEventListener('pointermove', function (e) {
      var r = el.getBoundingClientRect();
      dx = e.clientX - (r.left + r.width / 2); dy = e.clientY - (r.top + r.height / 2);
      if (!raf) raf = requestAnimationFrame(function () {
        raf = 0;
        el.style.transform = 'translate(' + (dx * 0.18).toFixed(1) + 'px,' + (dy * 0.28).toFixed(1) + 'px)';
      });
    });
    el.addEventListener('pointerleave', function () { el.style.transform = ''; });
  });
})();
