/* RAW Select – Erklär-Animation. Kein Framework, keine externen Dateien.
   Jeder Frame ist eine reine Funktion der Zeit t (render(t)): dadurch lässt sich die
   Schleife jederzeit anhalten, fortsetzen und für das Standbild an einer festen Stelle zeigen.
   Animiert werden nur transform und opacity. */
(function () {
  'use strict';
  var root = document.querySelector('[data-tut]');
  if (!root) return;

  function q(s) { return root.querySelector(s); }
  function qa(s) { return Array.prototype.slice.call(root.querySelectorAll(s)); }

  // ── Kurven (Levins Stil: Easy Ease ohne Nachfedern) ──
  function bezier(x1, y1, x2, y2) {
    function a(p1, p2) { return 1 - 3 * p2 + 3 * p1; }
    function b(p1, p2) { return 3 * p2 - 6 * p1; }
    function c(p1) { return 3 * p1; }
    function at(t, p1, p2) { return ((a(p1, p2) * t + b(p1, p2)) * t + c(p1)) * t; }
    return function (x) {
      if (x <= 0) return 0;
      if (x >= 1) return 1;
      var lo = 0, hi = 1, t = x;
      for (var i = 0; i < 24; i++) {
        var cx = at(t, x1, x2);
        if (Math.abs(cx - x) < 1e-5) break;
        if (cx < x) lo = t; else hi = t;
        t = (lo + hi) / 2;
      }
      return at(t, y1, y2);
    };
  }
  var LAND = bezier(0.22, 1, 0.36, 1);   // Landungen
  var MOVE = bezier(0.65, 0, 0.35, 1);   // Mauszeiger-Wege
  var DOWN = bezier(0.33, 1, 0.68, 1);   // schnelles Drücken
  function ACCEL(t) { return Math.pow(t, 2.6); } // Abgänge
  function LIN(t) { return t; }

  function seg(t, t0, d, e) {
    if (t <= t0) return 0;
    if (t >= t0 + d) return 1;
    return (e || LIN)((t - t0) / d);
  }
  function mix(a, b, p) { return a + (b - a) * p; }
  // Tastendruck: in 0.1 s runter, in 0.3 s wieder hoch. tUp = Zeitpunkt des Loslassens.
  function press(t, tDown, tUp) {
    if (tUp === undefined) tUp = tDown;
    return seg(t, tDown - 0.1, 0.1, DOWN) * (1 - seg(t, tUp, 0.3, LAND));
  }

  // ── Drehbuch (Sekunden) ──
  var T = {
    moves: [[1.2, 1], [2.75, 2], [4.05, 3], [5.2, 4]],
    marks: [{ cell: 1, at: 2.45, b: 1 }, { cell: 2, at: 3.75, b: 4 }, { cell: 3, at: 4.9, b: 1 }],
    ret: 6.3, z1: 7.65, esc1: 9.35, esc2: 9.9,
    curIn: 10.45, click1: 11.45, filt: 11.5,
    cmdA: 12.95, mv2: 13.85, click2: 14.6, toast: 14.8,
    end: 16.6, L: 16.95
  };
  var PTR = '<svg viewBox="0 0 17 25" aria-hidden="true"><path d="M1.2 1.2v19.6l4.9-4.7 3.2 7.2 3.3-1.4-3.2-7.1h6.9z"/></svg>';
  var STEPS = [
    { t: 0.55, keys: ['→'], press: [1.2], cap: 'Mit den Pfeiltasten wechselst du das Bild' },
    { t: 2.0, keys: ['1'], press: [2.45], cap: 'Die Tasten 1 bis 7 setzen einen Farbpunkt' },
    { t: 3.3, keys: ['4'], press: [3.75], cap: 'Danach springt die Auswahl zum nächsten Bild' },
    { t: 4.5, keys: ['1'], press: [4.9], cap: 'Danach springt die Auswahl zum nächsten Bild' },
    { t: 5.8, keys: ['Return'], press: [6.3], cap: 'Return öffnet die grosse Ansicht' },
    { t: 7.2, keys: ['Z'], press: [7.65], cap: 'Z zeigt das Bild bei 100 % für die Schärfekontrolle' },
    { t: 8.85, keys: ['Esc'], press: [9.35, 9.9], cap: 'Esc führt Schritt für Schritt zurück ins Raster' },
    { t: 10.45, keys: ['⌥'], hold: [11.35, 11.75], cap: '⌥-Klick auf einen Farbpunkt zeigt nur diese Bilder' },
    { t: 12.5, keys: ['⌘', 'A'], press: [12.95], cap: '⌘A wählt alle angezeigten Bilder aus' },
    { t: 13.75, keys: ['ptr'], press: [T.click2], cap: '«Auswahl kopieren» legt die Originale in einen Zielordner' }
  ];
  // Bildunterschriften: gleiche Texte hintereinander bilden einen Abschnitt (kein Wechsel).
  var CAPS = [];
  STEPS.forEach(function (s) {
    if (!CAPS.length || CAPS[CAPS.length - 1].cap !== s.cap) CAPS.push({ t: s.t, cap: s.cap });
  });

  // ── Elemente ──
  var win = q('.tut-win'), scaler = q('.tut__scaler'), viewport = q('.tut__viewport');
  var content = q('.tut-content');
  var cells = qa('.tut-cell'), thumbs = qa('.tut-thumb');
  var flashes = qa('.tut-flash');
  var selA = q('.tut-sel--a'), selB = q('.tut-sel--b'), selC = q('.tut-sel--c');
  var loupe = q('.tut-loupe'), loupeBg = q('.tut-loupe__bg'), loupeImg = q('.tut-loupe__img');
  var loupeName = q('.tut-loupe__name'), hud = q('.tut-hud');
  var segPill = q('.tut-seg__pill'), segs = qa('.tut-seg span');
  var copyBtn = q('.tut-copy'), copyFlash = q('.tut-copy__flash');
  var cursor = q('.tut-cursor');
  var chips = qa('.tut-chip[data-b]'), chipAll = q('.tut-chip--all');
  var allOn = q('.tut-all-on'), allOff = q('.tut-all-off');
  var stSel = q('[data-tut-sel]'), stPos = q('[data-tut-pos]'), stMsg = q('[data-tut-msg]');
  var keysEl = q('.tut__keys'), capEl = q('.tut__cap');
  var RED = [1, 3];                       // Zellen mit rotem Punkt
  var LOUPE_CELL = 4, IMG_ASPECT = 288 / 360;
  var FOCUS = { x: 0.47, y: 0.27 };       // Detail für den 100-%-Zoom (Gesicht/Wappen)
  var ZOOM = 2.3;

  function chipOf(b) { return chips.filter(function (c) { return +c.getAttribute('data-b') === b; })[0]; }
  function dotOf(i) { return thumbs[i].querySelector('.tut-dot'); }

  // ── Schreibhelfer: nur bei Änderung ins DOM ──
  function tf(el, x, y, s, o) {
    var v = 'translate3d(' + x.toFixed(2) + 'px,' + y.toFixed(2) + 'px,0) scale(' + s.toFixed(4) + ')';
    if (el._tf !== v) { el.style.transform = v; el._tf = v; }
    if (o !== undefined) op(el, o);
  }
  function op(el, o) {
    var v = Math.max(0, Math.min(1, o)).toFixed(3);
    if (el._op !== v) { el.style.opacity = v; el._op = v; }
  }
  function txt(el, s) { if (el._tx !== s) { el.textContent = s; el._tx = s; } }
  function vis(el, on) { var v = on ? 'visible' : 'hidden'; if (el._vis !== v) { el.style.visibility = v; el._vis = v; } }

  // ── Geometrie (in internen Fensterpixeln; Transforms beeinflussen offset* nicht) ──
  var G = null;
  function offsetIn(el, anc) {
    var x = 0, y = 0;
    while (el && el !== anc) { x += el.offsetLeft; y += el.offsetTop; el = el.offsetParent; }
    return { x: x, y: y };
  }
  function measure() {
    var w = viewport.clientWidth;
    if (!w) return;
    root.classList.toggle('is-compact', w < 600);
    var W = scaler.offsetWidth, H = scaler.offsetHeight;
    var k = w / W;
    scaler.style.transform = 'scale(' + k.toFixed(5) + ')';
    viewport.style.height = (H * k).toFixed(1) + 'px';

    var pos = thumbs.map(function (th, i) {
      var p = offsetIn(cells[i], content);
      return { x: p.x + th.offsetLeft, y: p.y + th.offsetTop, w: th.offsetWidth, h: th.offsetHeight };
    });
    [selA, selB, selC].forEach(function (s) {
      s.style.width = (pos[0].w + 6) + 'px';
      s.style.height = (pos[0].h + 6) + 'px';
    });
    var cw = content.clientWidth, ch = content.clientHeight;
    var lh = ch - 24, lw = lh * IMG_ASPECT;
    var L = { x: (cw - lw) / 2, y: 12, w: lw, h: lh };
    loupeImg.style.left = L.x + 'px'; loupeImg.style.top = L.y + 'px';
    loupeImg.style.width = L.w + 'px'; loupeImg.style.height = L.h + 'px';
    // Bild im Rasterfeld (object-fit: contain, Hochformat)
    var c = pos[LOUPE_CELL], th = c.h, tw = th * IMG_ASPECT;
    var Tr = { x: c.x + (c.w - tw) / 2, y: c.y, w: tw, h: th };

    function center(el) { var p = offsetIn(el, win); return { x: p.x + el.offsetWidth / 2, y: p.y + el.offsetHeight / 2 }; }
    var red = center(chipOf(1).querySelector('.tut-chip__icon'));
    var copy = center(copyBtn);
    var seg0 = segs[0].offsetLeft, seg1 = segs[1].offsetLeft;
    G = {
      pos: pos, cw: cw, ch: ch, L: L, Tr: Tr, red: red, copy: copy,
      curStart: { x: W * 0.72, y: H * 0.56 }, seg0: seg0 - 2, seg1: seg1 - 2
    };
  }

  // ── Ein Frame ──
  var lastKeys = -2, lastCap = -2;
  function render(t, still) {
    if (!G) return;
    var P = G.pos;

    // Fenster: Eintritt, unmerkliche Drift (wächst bis exakt 1, ragt nie über die Spalte), Abgang
    var pin = seg(t, 0, 0.7, LAND), pout = seg(t, T.end, 0.3, ACCEL);
    var drift = still ? 0 : seg(t, 0, T.end, LIN);
    if (still) { pin = 1; pout = 0; }
    tf(win, 0, mix(18, 0, pin) - 8 * pout - 3 * drift,
      mix(0.975, 1, pin) * (1 - 0.015 * pout) * (still ? 1 : 0.992 + 0.008 * drift),
      (still ? 1 : seg(t, 0, 0.3, LIN)) * (1 - pout));

    // Punkte, Aufhellen, Zähler
    var counts = { 0: 9, 1: 0, 4: 0 }, changed = {};
    T.marks.forEach(function (m) {
      var p = seg(t, m.at, 0.36, LAND);
      tf(dotOf(m.cell), 0, 0, mix(0.3, 1, p), seg(t, m.at, 0.1, LIN));
      op(flashes[m.cell], t >= m.at ? 0.22 * (1 - seg(t, m.at, 0.45, LIN)) : 0);
      if (t >= m.at) { counts[0]--; counts[m.b]++; changed[0] = m.at; changed[m.b] = m.at; }
    });
    chips.forEach(function (chip) {
      var b = +chip.getAttribute('data-b');
      var n = counts[b] || 0;
      var lbl = chip.querySelector('b');
      txt(lbl, n > 0 ? String(n) : '·');
      var pop = changed[b] !== undefined ? 1 - seg(t, changed[b], 0.35, LAND) : 0;
      tf(lbl, 0, 0, 1 + 0.4 * pop);
      // ⌥-Klick: nur Rot bleibt gefüllt, die anderen werden zum Ring
      var off = b === 1 ? 0 : seg(t, T.filt, 0.14, LIN);
      var icon = chip.querySelector('.tut-chip__icon');
      op(icon.children[0], 1 - off);
      op(icon.children[1], off * 0.7);
      op(lbl, 1 - 0.5 * off);
      if (b === 1) tf(icon, 0, 0, 1 - 0.1 * press(t, T.click1));
    });
    var allOffP = seg(t, T.filt, 0.14, LIN);
    op(allOn, 1 - allOffP); op(allOff, allOffP);

    // Auswahlrahmen: gleitet mit den Pfeil-/Farbtasten weiter
    var x = P[0].x, y = P[0].y, idx = 0;
    T.moves.forEach(function (m) {
      var p = seg(t, m[0], 0.3, LAND);
      x = mix(x, P[m[1]].x, p); y = mix(y, P[m[1]].y, p);
      if (t >= m[0]) idx = m[1];
    });
    // Filtern: wie in der App springt die Auswahl auf das erste sichtbare Bild
    var toFirst = seg(t, T.filt + 0.08, 0.5, LAND);
    tf(selA, mix(x, P[0].x, toFirst) - 3, mix(y, P[0].y, toFirst) - 3, 1, 1);

    // Raster filtern: Nicht-Rote gehen, Rote rücken auf die ersten Plätze
    var moveP = seg(t, T.filt + 0.08, 0.5, LAND);
    cells.forEach(function (cell, i) {
      var slot = RED.indexOf(i);
      if (slot < 0) {
        var h = seg(t, T.filt, 0.22, ACCEL);
        tf(cell, 0, 0, mix(1, 0.92, h), 1 - h);
      } else {
        tf(cell, (P[slot].x - P[i].x) * moveP, (P[slot].y - P[i].y) * moveP, 1, 1);
      }
    });
    // ⌘A: beide roten Bilder ausgewählt
    var pa = seg(t, T.cmdA, 0.3, LAND), oa = seg(t, T.cmdA, 0.1, LIN);
    tf(selB, P[0].x - 3, P[0].y - 3, mix(1.06, 1, pa), oa);
    tf(selC, P[1].x - 3, P[1].y - 3, mix(1.06, 1, pa), oa);

    // Grosse Ansicht: Bild wächst aus dem Rasterfeld, Hintergrund deckt das Raster ab
    var open = seg(t, T.ret, 0.5, LAND), close = seg(t, T.esc2, 0.3, ACCEL);
    var a = open * (1 - close);
    var lv = t >= T.ret && t < T.esc2 + 0.3;
    vis(loupe, lv);
    if (lv) {
      op(loupeBg, seg(t, T.ret, 0.14, LIN) * (1 - seg(t, T.esc2, 0.1, LIN)));
      op(loupeName, seg(t, T.ret + 0.25, 0.25, LIN) * (1 - seg(t, T.esc2, 0.1, LIN)));
      var L = G.L, Tr = G.Tr;
      var zin = seg(t, T.z1, 0.6, LAND), zout = seg(t, T.esc1, 0.4, LAND);
      var zp = zin * (1 - zout);
      if (zp > 0) {
        // 100 %: um das Detail zoomen und es dabei Richtung Mitte holen
        var z = mix(1, ZOOM, zp);
        var fx = L.x + FOCUS.x * L.w, fy = L.y + FOCUS.y * L.h;
        var gx = mix(fx, G.cw / 2, zp), gy = mix(fy, G.ch * 0.42, zp);
        tf(loupeImg, gx + z * (L.x - fx) - L.x, gy + z * (L.y - fy) - L.y, z, 1);
      } else {
        var s = mix(Tr.h / L.h, 1, a);
        tf(loupeImg, mix(Tr.x, L.x, a) - L.x, mix(Tr.y, L.y, a) - L.y, s, close >= 1 ? 0 : 1);
      }
      var hp = seg(t, T.z1 + 0.1, 0.35, LAND), hx = seg(t, T.esc1, 0.15, ACCEL);
      tf(hud, 0, mix(6, 0, hp) - 4 * hx, 1, seg(t, T.z1 + 0.1, 0.15, LIN) * (1 - hx));
    }
    tf(segPill, mix(G.seg0, G.seg1, a), 0, 1);

    // Mauszeiger
    var cIn = seg(t, T.curIn, 0.45, LAND);
    var cx = G.curStart.x + 40 * (1 - cIn), cy = G.curStart.y + 30 * (1 - cIn);
    var m1 = seg(t, T.curIn + 0.2, 0.7, MOVE);
    cx = mix(cx, G.red.x, m1); cy = mix(cy, G.red.y, m1);
    var m2 = seg(t, T.mv2, 0.65, MOVE);
    cx = mix(cx, G.copy.x, m2); cy = mix(cy, G.copy.y + 2, m2);
    var cp = Math.max(press(t, T.click1), press(t, T.click2));
    tf(cursor, cx - 1, cy - 1, 1 - 0.1 * cp, seg(t, T.curIn, 0.2, LIN));

    // Knopf „Auswahl kopieren": drücken, hell werden
    tf(copyBtn, 0, 0, 1 - 0.05 * press(t, T.click2));
    op(copyFlash, t >= T.click2 - 0.1 ? 0.3 * press(t, T.click2) + (t >= T.click2 ? 0.18 * (1 - seg(t, T.click2, 0.5, LIN)) : 0) : 0);

    // Statusleiste
    txt(stSel, t >= T.cmdA ? '2 ausgewählt' : '1 ausgewählt');
    txt(stPos, t >= T.filt ? '1 / 2' : (idx + 1) + ' / 9');
    txt(stMsg, t >= T.toast ? '2 Bilder (2 Dateien) kopiert.' : '9 Bilder gefunden');

    if (still) return;

    // Tastenkappe
    var ki = -1;
    for (var i = 0; i < STEPS.length; i++) if (t >= STEPS[i].t) ki = i;
    if (ki !== lastKeys) {
      lastKeys = ki;
      keysEl.innerHTML = ki < 0 ? '' : STEPS[ki].keys.map(function (k) {
        if (k === 'ptr') return '<span class="tut-key">' + PTR + '</span>';
        return '<span class="tut-key' + (k.length > 1 ? ' tut-key--wide' : '') + '">' + k + '</span>';
      }).join('');
    }
    if (ki >= 0) {
      var st = STEPS[ki], next = STEPS[ki + 1];
      var kp = seg(t, st.t, 0.32, LAND);
      var kx = next ? seg(t, next.t - 0.16, 0.16, ACCEL) : seg(t, T.end, 0.3, ACCEL);
      var d = 0;
      if (st.press) st.press.forEach(function (tp2) { d = Math.max(d, press(t, tp2)); });
      if (st.hold) d = press(t, st.hold[0], st.hold[1]);
      tf(keysEl, 0, mix(8, 0, kp) - 6 * kx + 2 * d, mix(0.92, 1, kp) * (1 - 0.06 * d), seg(t, st.t, 0.16, LIN) * (1 - kx));
    } else {
      op(keysEl, 0);
    }
    // Bildunterschrift
    var ci = -1;
    for (var j = 0; j < CAPS.length; j++) if (t >= CAPS[j].t) ci = j;
    if (ci !== lastCap) { lastCap = ci; txt(capEl, ci < 0 ? '' : CAPS[ci].cap); }
    if (ci >= 0) {
      var cs = CAPS[ci], cn = CAPS[ci + 1];
      var cpi = seg(t, cs.t, 0.36, LAND);
      var cxo = cn ? seg(t, cn.t - 0.16, 0.16, ACCEL) : seg(t, T.end, 0.3, ACCEL);
      tf(capEl, 0, mix(6, 0, cpi) - 5 * cxo, 1, seg(t, cs.t, 0.18, LIN) * (1 - cxo));
    } else {
      op(capEl, 0);
    }
  }

  // ── Reduzierte Bewegung: ruhiges Standbild des markierten Rasters ──
  var reduce = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  var STILL_T = 5.7;

  measure();
  if (reduce || !('IntersectionObserver' in window)) {
    render(STILL_T, true);
    var relayout = function () { measure(); render(STILL_T, true); };
    if ('ResizeObserver' in window) new ResizeObserver(relayout).observe(viewport);
    else window.addEventListener('resize', relayout);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(relayout);
    return;
  }

  // Grosses Bild vorab dekodieren, damit die grosse Ansicht nie leer aufgeht.
  var big = loupeImg.querySelector('img');
  if (big && big.decode) big.decode().catch(function () {});

  // ── Uhr: läuft nur, wenn sichtbar und der Tab aktiv ist ──
  root.classList.add('is-live');
  var t = 0, inView = false, frozen = false, raf = 0, last = 0;
  render(0);

  function running() { return inView && !frozen && !document.hidden; }
  function tick(now) {
    raf = 0;
    if (!running()) return;
    var dt = last ? Math.min((now - last) / 1000, 0.1) : 0;
    last = now;
    t += dt;
    if (t >= T.L) t -= T.L;
    render(t);
    raf = requestAnimationFrame(tick);
  }
  function update() {
    if (running()) {
      if (!raf) { last = 0; raf = requestAnimationFrame(tick); }
    } else if (raf) {
      cancelAnimationFrame(raf); raf = 0;
    }
  }
  new IntersectionObserver(function (entries) {
    inView = entries[entries.length - 1].isIntersecting;
    update();
  }, { threshold: 0.2 }).observe(viewport);
  document.addEventListener('visibilitychange', update);

  var onResize = function () { measure(); render(t); };
  if ('ResizeObserver' in window) new ResizeObserver(onResize).observe(viewport);
  else window.addEventListener('resize', onResize);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(onResize);
})();
