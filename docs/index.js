const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const clamp = (v, a, b) => Math.min(Math.max(v, a), b);
const reduce = matchMedia("(prefers-reduced-motion: reduce)");
const coarse = matchMedia("(pointer: coarse)").matches;
const sayEl = $("#announce");
function announce(text) { sayEl.textContent = ""; setTimeout(() => { sayEl.textContent = text; }, 40); }

// ---------- Menu bar clock ----------
const cDate = $("#cDate"), cTime = $("#cTime");
function tick() {
  const d = new Date();
  cDate.textContent = d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" }).replace(/,/g, "");
  cTime.textContent = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}
tick(); setInterval(tick, 15000);

// ---------- Wallpaper: a few stars for dusk, and a fine grain ----------
(() => {
  let s = "";
  for (let i = 0; i < 70; i++) {
    s += `<circle cx="${(Math.random() * 1600).toFixed(0)}" cy="${(Math.random() * 520).toFixed(0)}" r="${(Math.random() * 1.3 + .3).toFixed(2)}" opacity="${(Math.random() * .6 + .25).toFixed(2)}"/>`;
  }
  $("#stars").innerHTML = s;
  const c = document.createElement("canvas");
  c.width = c.height = 160;
  const x = c.getContext && c.getContext("2d");
  if (!x) return;
  const im = x.createImageData(160, 160);
  for (let i = 0; i < im.data.length; i += 4) {
    const v = Math.random() * 255 | 0;
    im.data[i] = im.data[i + 1] = im.data[i + 2] = v;
    im.data[i + 3] = 255;
  }
  x.putImageData(im, 0, 0);
  $(".grain").style.backgroundImage = `url(${c.toDataURL()})`;
})();

// ---------- Appearance: light is day, dark is dusk ----------
const root = document.documentElement, sysDark = matchMedia("(prefers-color-scheme: dark)"), themeBtn = $("#theme");
const isDark = () => root.dataset.theme ? root.dataset.theme === "dark" : sysDark.matches;
function syncTheme() { themeBtn.setAttribute("aria-label", isDark() ? "Switch to light appearance" : "Switch to dark appearance"); }
themeBtn.addEventListener("click", () => {
  // Remembered for this tab only (never sent anywhere), so the Privacy page opens in the same appearance.
  const flip = () => { root.dataset.theme = isDark() ? "light" : "dark"; syncTheme(); try { sessionStorage.setItem("shiftvert-theme", root.dataset.theme); } catch {} };
  if (document.startViewTransition && !reduce.matches) document.startViewTransition(flip); else flip();
});
if (sysDark.addEventListener) sysDark.addEventListener("change", syncTheme);
syncTheme();

// ---------- File icons (drawn, no images) ----------
const PAGE = "M15 4h24l13 13v41a3 3 0 0 1-3 3H15a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3z";
const TAG = { pdf: "#e5484d", doc_: "#2f6fec", aud: "#b544d6", zip: "#76768a" };
const HOLES = [18, 24.5, 31, 37.5, 44].map(y => `<rect x="5.6" y="${y}" width="3" height="3.6" rx=".8"/><rect x="55.4" y="${y}" width="3" height="3.6" rx=".8"/>`).join("");
function fileIcon(kind, ext = "") {
  if (kind === "img") return `<svg viewBox="0 0 64 64" aria-hidden="true"><rect x="5" y="12" width="54" height="42" rx="4" fill="#fff"/><rect x="8.5" y="15.5" width="47" height="35" rx="2" fill="url(#gPhoto)"/><circle cx="43" cy="25" r="4.6" fill="#fff4d6"/><path d="M8.5 42l11.5-12 9 8.5 7-6 19.5 15v1a2 2 0 0 1-2 2h-43a2 2 0 0 1-2-2z" fill="#5b2d8e" opacity=".85"/></svg>`;
  if (kind === "vid") return `<svg viewBox="0 0 64 64" aria-hidden="true"><rect x="4" y="14" width="56" height="38" rx="5" fill="#1d1b2b"/><rect x="10.5" y="17.5" width="43" height="31" rx="2" fill="url(#gVid)"/><g fill="#fff" opacity=".5">${HOLES}</g><path d="M28 26v14l12-7z" fill="#fff"/></svg>`;
  if (kind === "folder" || kind === "apps") {
    const glyph = kind === "apps" ? `<g fill="#fff" opacity=".75"><rect x="23" y="29" width="7.5" height="7.5" rx="2"/><rect x="33.5" y="29" width="7.5" height="7.5" rx="2"/><rect x="23" y="39.5" width="7.5" height="7.5" rx="2"/><rect x="33.5" y="39.5" width="7.5" height="7.5" rx="2"/></g>` : "";
    return `<svg viewBox="0 0 64 64" aria-hidden="true"><path d="M6 16a4 4 0 0 1 4-4h14l5 5h25a4 4 0 0 1 4 4v6H6z" fill="url(#gFoldB)"/><path d="M6 23a4 4 0 0 1 4-4h44a4 4 0 0 1 4 4v26a4 4 0 0 1-4 4H10a4 4 0 0 1-4-4z" fill="url(#gFold)"/>${glyph}</svg>`;
  }
  const c = TAG[kind] || TAG.zip;
  let body;
  if (kind === "aud") body = [6, 12, 19, 10, 22, 14, 8, 16].map((h, i) => `<rect x="${18.5 + i * 3.6}" y="${30 - h / 2}" width="2.2" height="${h}" rx="1.1" fill="${c}" opacity=".75"/>`).join("");
  else if (kind === "zip") body = `<path d="M32 6v30" stroke="#9a9aa8" stroke-width="3" stroke-dasharray="2.6 2.4"/><rect x="28.8" y="34" width="6.4" height="7" rx="1.6" fill="#9a9aa8"/>`;
  else body = `<path d="M19 21h15M19 26.5h26M19 32h26M19 37.5h19" stroke="#cfcedb" stroke-width="2.2" stroke-linecap="round"/>`;
  return `<svg viewBox="0 0 64 64" aria-hidden="true"><path d="${PAGE}" fill="#fff" stroke="rgba(0,0,0,.14)"/><path d="M39 4v10a3 3 0 0 0 3 3h10" fill="#e7e6ee" stroke="rgba(0,0,0,.1)"/>${body}` +
    `<rect x="15" y="44" width="34" height="11" rx="3" fill="${c}"/><text x="32" y="50" fill="#fff" font-size="7.6" font-weight="800" letter-spacing=".3" text-anchor="middle" dominant-baseline="middle">${ext}</text></svg>`;
}
$$("[data-icon]").forEach(s => { const [k, e] = s.dataset.icon.split(":"); s.innerHTML = fileIcon(k, e || ""); });

// ---------- The demo ----------
// Same wheels (and output names) the real app shows for each file type: formats first, ⌥ swaps to tools.
const FILES = [
  { name: "photo.heic", kind: "img", ext: "HEIC",
    formats: [["PNG", "photo.png"], ["JPG", "photo.jpg"], ["TIFF", "photo.tiff"], ["GIF", "photo.gif"], ["BMP", "photo.bmp"], ["PDF", "photo.pdf"]],
    tools: [["Compress", "photo compressed.heic"], ["Resize 50%", "photo 50%.heic"], ["Crop", "photo cropped.heic"], ["Strip EXIF", "photo clean.heic"], ["Zip", "photo.heic.zip"]] },
  { name: "clip.mov", kind: "vid", ext: "MOV",
    formats: [["MP4", "clip.mp4"], ["M4V", "clip.m4v"], ["GIF", "clip.gif"], ["M4A", "clip.m4a"]],
    tools: [["Compress", "clip compressed.mp4"], ["Trim", "clip trimmed.mov"], ["Zip", "clip.mov.zip"]] },
  { name: "report.pdf", kind: "pdf", ext: "PDF",
    formats: [["PNG", "report pages"], ["JPG", "report pages"], ["TXT", "report.txt"]],
    tools: [["Compress", "report compressed.pdf"], ["Split", "report split"], ["Zip", "report.pdf.zip"]] },
  { name: "notes.docx", kind: "doc_", ext: "DOCX",
    formats: [["PDF", "notes.pdf"], ["RTF", "notes.rtf"], ["TXT", "notes.txt"], ["HTML", "notes.html"], ["ODT", "notes.odt"]],
    tools: [["Zip", "notes.docx.zip"]] },
  { name: "song.wav", kind: "aud", ext: "WAV",
    formats: [["M4A", "song.m4a"], ["AIFF", "song.aiff"], ["FLAC", "song.flac"]],
    tools: [["Compress", "song compressed.m4a"], ["Trim", "song trimmed.wav"], ["Zip", "song.wav.zip"]] },
];
const KIND_OF = { png: "img", jpg: "img", heic: "img", tiff: "img", gif: "img", bmp: "img", pdf: "pdf", mp4: "vid", mov: "vid", m4v: "vid",
                  m4a: "aud", aiff: "aud", flac: "aud", txt: "doc_", rtf: "doc_", html: "doc_", odt: "doc_", zip: "zip",
                  webp: "img", avif: "img", docx: "doc_", wav: "aud", mp3: "aud" };
const KIND_NAME = { img: "Image", vid: "Movie", pdf: "PDF document", doc_: "Document", aud: "Audio" };
// Small line icons for the tool tiles (24×24 grid).
const ICONS = {
  "Compress": "M4 14h6v6M20 10h-6V4M14 10l7-7M3 21l7-7",
  "Resize 50%": "M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14zM21 21l-4.3-4.3M8 11h6",
  "Crop": "M6 2v14a2 2 0 0 0 2 2h14M18 22V8a2 2 0 0 0-2-2H2",
  "Strip EXIF": "M12 21s-7-6-7-11.5a7 7 0 0 1 11.6-5.3M18.6 7.6c.3.6.4 1.2.4 1.9 0 2.6-1.6 5.1-3.4 7.1M3 3l18 18",
  "Zip": "M3 4h18v4H3zM5 8v12h14V8M10 12h4",
  "Trim": "M6 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM20 4 8.1 15.9M14.5 14.5 20 20M8.1 8.1 12 12",
  "Split": "M4 3h6v18H4zM14 3h6v18h-6z",
  "Merge": "M9 3h7l4 4v9a2 2 0 0 1-2 2M6 7h7l4 4v8a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z",
};
ICONS["Merge PDF"] = ICONS.Merge;

const desk = $("#desktop"), iconsEl = $("#icons"), zone = $("#zone"), ring = $("#ring"), svg = $("#ringsvg"),
      hud = $("#hud"), hudText = $("#hudText"), hint = $("#hint"), kc = $("#kc"), keyBtns = $$(".keycap");
// Geometry in px, matching the app: glass disc, tile band, hub, rounded corners, gaps, hover pop.
const DISC = 150, OUT = 139, IN = 56, CORNER = 11, GAP = 6, POP = 9;
const ICON_W = 100, ICON_H = 96;
let cur = null, hovered = -1, center = [0, 0], scale = 1, used = false, mode = "formats", preferred = "formats", tiles = [];
let running = true, lastPick = 0, outs = [], closeT, hudT;

const f2 = n => n.toFixed(1);
const pt = (r, a) => [r * Math.sin(a), -r * Math.cos(a)];  // a = clockwise from 12 o'clock

function fileEl(name, kind, ext, tag) {
  const el = document.createElement(tag);
  if (tag === "button") el.type = "button";
  el.className = "file";
  el.innerHTML = `<span class="ic">${fileIcon(kind, ext)}</span><span class="name"></span>`;
  el.querySelector(".name").textContent = name;
  return el;
}

function deskPoint(e) {
  const b = desk.getBoundingClientRect();
  return [e.clientX - b.left, e.clientY - b.top];
}

function clampPos(p, d) {
  p.x = clamp(p.x, 4, Math.max(4, d.width - ICON_W - 4));
  p.y = clamp(p.y, 36, Math.max(36, d.height - ICON_H - 96));
}

// Where the icons sit until someone moves them: a loose scatter inside the zone.
const SPOTS_WIDE = [[.06, .12], [.52, 0], [.9, .3], [.26, .58], [.7, .86]];
const SPOTS_NARROW = [[.02, .04], [.4, 0], [.8, .06], [.18, .62], [.62, .68]];
function layout() {
  if (cur && cur.how === "drag") return;
  const d = desk.getBoundingClientRect(), z = zone.getBoundingClientRect();
  const spots = z.width > 460 ? SPOTS_WIDE : SPOTS_NARROW;
  // Start above the Dock in the first screenful when there's room (iPad portrait, half-screen windows).
  const room = document.documentElement.clientHeight - 96 - (z.top + scrollY), zh = room > ICON_H + 60 ? Math.min(z.height, room) : z.height;
  FILES.forEach((f, i) => {
    if (!f.moved) {
      f.x = z.left - d.left + spots[i][0] * Math.max(0, z.width - ICON_W);
      f.y = z.top - d.top + spots[i][1] * Math.max(0, zh - ICON_H);
    }
    clampPos(f, d);
    f.el.style.left = f2(f.x) + "px";
    f.el.style.top = f2(f.y) + "px";
  });
}

FILES.forEach((f, i) => {
  const el = fileEl(f.name, f.kind, f.ext, "button");
  f.el = el;
  el.classList.add("enter");
  el.style.setProperty("--i", i);
  el.setAttribute("aria-describedby", "fileHelp");
  iconsEl.append(el);

  el.addEventListener("pointerdown", e => {
    if (e.button !== 0 || (cur && cur.how === "drag")) return;
    delete el.dataset.dragged;
    if (cur) { closeWheel(); cur = null; }
    e.preventDefault();
    try { el.setPointerCapture(e.pointerId); } catch {}
    el.classList.remove("back");
    stopIdle();
    cur = { el, f, how: "drag", sx: e.clientX, sy: e.clientY, started: false, open: false, pid: e.pointerId };
  });
  el.addEventListener("pointermove", e => {
    if (!cur || cur.el !== el || cur.how !== "drag" || e.pointerId !== cur.pid) return;
    const dx = e.clientX - cur.sx, dy = e.clientY - cur.sy;
    if (!cur.started && Math.hypot(dx, dy) > 6) {
      cur.started = true;
      el.classList.add("dragging");
      if (running) {
        const [x, y] = deskPoint(e);
        cur.open = true;
        openWheel(f, x, y);
      }
    }
    if (!cur.started) return;
    el.style.transform = `translate(${dx}px, ${dy}px)`;
    cur.last = e;
    if (cur.open) setHover(hitTest(e));
  });
  el.addEventListener("pointerup", e => finish(el, e));
  el.addEventListener("pointercancel", () => finish(el, null));
  // If capture is lost without a pointerup (window switch, OS gesture), end the drag so the icons don't get stuck.
  el.addEventListener("lostpointercapture", () => { if (cur && cur.el === el && cur.how === "drag") finish(el, null); });

  // A click (or Enter) opens the wheel around the file in click mode, like Convert Files… in the app.
  el.addEventListener("click", e => {
    e.stopPropagation();
    if (el.dataset.dragged) { delete el.dataset.dragged; return; }
    if (performance.now() - lastPick < 350) return;
    if (cur && cur.how === "click" && cur.el === el) return;
    if (cur) { closeWheel(); cur = null; }
    stopIdle();
    if (!running) { nudgeHint(); return; }
    const b = desk.getBoundingClientRect(), r = el.getBoundingClientRect();
    openClick(f, r.left - b.left + r.width / 2, r.top - b.top + 32, e.detail === 0);
  });
});

if ("ResizeObserver" in window) new ResizeObserver(() => layout()).observe(desk);
else addEventListener("resize", layout);
layout();
setTimeout(() => {
  FILES.forEach(f => f.el.classList.remove("enter"));
  if (!used && !cur) FILES[0].el.classList.add("idle");
}, 1700);
function stopIdle() { FILES.forEach(f => f.el.classList.remove("idle", "enter")); }

function openClick(f, x, y, kb) {
  cur = { el: f.el, f, how: "click", open: true, kb };
  openWheel(f, x, y);
  ring.classList.add("click");
  f.el.classList.add("sel");
  if (kb) kbHover(0, true);
}

function finish(el, e) {
  if (!cur || cur.el !== el || cur.how !== "drag") return;
  const c = cur;
  if (!c.started) { cur = null; return; }  // a plain click: the click handler takes it from here
  el.dataset.dragged = "1";
  el.classList.remove("dragging");
  const picked = e && c.open ? hitTest(e) : -1;
  if (picked >= 0) {
    const [x, y] = deskPoint(e);
    springBack(el);
    cur = null;
    convert(c.f, picked, x, y);
  } else if (e && (!c.open || distance(e) > DISC + 30)) {
    // Dropped on the desktop itself: the file just moves there, like in Finder.
    const f = c.f;
    f.x += e.clientX - c.sx;
    f.y += e.clientY - c.sy;
    f.moved = true;
    clampPos(f, desk.getBoundingClientRect());
    el.classList.remove("back");
    el.style.transform = "";
    el.style.left = f2(f.x) + "px";
    el.style.top = f2(f.y) + "px";
    cur = null;
    closeWheel();
  } else {
    // Dropped in the hub (or the drag was cancelled): nothing happens.
    springBack(el);
    cur = null;
    closeWheel();
  }
}

function springBack(el) {
  el.classList.add("back");
  el.style.transform = "";
}

function distance(e) {
  const [x, y] = deskPoint(e);
  return Math.hypot(x - center[0], y - center[1]) / scale;
}

// ⌥ swaps to tools and ⇧ back to formats mid-drag, like the app; the keycaps do the same on touch screens.
function setMode(m, prefer = false) {
  if (prefer) preferred = m;
  if (cur && cur.open && m !== mode && cur.f[m].length) {
    mode = m;
    renderWheel(cur.f);
    if (cur.how === "drag" && cur.last) setHover(hitTest(cur.last));
    if (cur.how === "click" && cur.kb) kbHover(0, false, m === "tools" ? "Tools. " : "Formats. ");
  }
  syncKeys();
}

function syncKeys() {
  const m = cur && cur.open ? mode : preferred;
  keyBtns.forEach(b => b.setAttribute("aria-pressed", String(b.dataset.mode === m)));
  kc.classList.toggle("held", !!(cur && cur.open && mode === "formats"));
}

function pressKey(m, down) {
  keyBtns.forEach(b => { if (b.dataset.mode === m) b.classList.toggle("down", down); });
  if (m === "formats") kc.classList.toggle("down", down);
}

keyBtns.forEach(b => b.addEventListener("click", e => {
  e.stopPropagation();
  setMode(b.dataset.mode, true);
}));
kc.addEventListener("pointerdown", () => kc.classList.add("down"));
["pointerup", "pointerleave", "pointercancel"].forEach(t => kc.addEventListener(t, () => kc.classList.remove("down")));

/// A tile: the band between IN and OUT for this slice, pulled in by the corner size; the same-colour stroke with
/// round joins grows it back with evenly rounded corners (the group's opacity keeps the overlap invisible).
function tilePath(a, s) {
  const r0 = IN + CORNER, r1 = OUT - CORNER, side = GAP / 2 + CORNER;
  const h1 = Math.max(0.01, s / 2 - side / r1), h0 = Math.max(0.01, s / 2 - side / r0);
  const [x0, y0] = pt(r1, a - h1), [x1, y1] = pt(r1, a + h1), [x2, y2] = pt(r0, a + h0), [x3, y3] = pt(r0, a - h0);
  return `M${f2(x0)} ${f2(y0)}A${r1} ${r1} 0 ${2 * h1 > Math.PI ? 1 : 0} 1 ${f2(x1)} ${f2(y1)}` +
         `L${f2(x2)} ${f2(y2)}A${r0} ${r0} 0 ${2 * h0 > Math.PI ? 1 : 0} 0 ${f2(x3)} ${f2(y3)}Z`;
}

function place(t, out) {
  const [x, y] = pt(out, +t.dataset.a);
  t.style.transform = `translate(${f2(x)}px, ${f2(y)}px)`;
}

// Draws a wheel into an <svg>: hub, one tile per option, the pill and its hint. Used by the desktop and the Finder preview.
function drawWheel(el, list, isTools, hintText, gid) {
  const s = 2 * Math.PI / list.length, mid = (IN + OUT) / 2;
  el.innerHTML = `<defs>
      <linearGradient id="${gid}t" x1="0" y1="0" x2="0" y2="1"><stop offset="0" class="st-t"/><stop offset="1" class="st-b"/></linearGradient>
      <linearGradient id="${gid}h" x1="0" y1="0" x2="0" y2="1"><stop offset="0" class="st-ht"/><stop offset="1" class="st-hb"/></linearGradient>
    </defs>
    <circle class="hub" r="${IN - 6}"/>` +
    list.map(([title], i) => {
      const a = i * s, [lx, ly] = pt(mid, a), d = tilePath(a, s);
      const label = isTools
        ? `<g transform="translate(${f2(lx - 8.4)} ${f2(ly - 15)}) scale(.7)"><path class="ico" d="${ICONS[title] || ICONS.Zip}"/></g>` +
          `<text class="small" x="${f2(lx)}" y="${f2(ly + 9)}">${title.toUpperCase()}</text>`
        : `<text${title.length > 4 ? ' class="long"' : ""} x="${f2(lx)}" y="${f2(ly + 1)}">${title.toUpperCase()}</text>`;
      return `<g class="tile" data-a="${a}"><g class="body"><path d="${d}" fill="url(#${gid}t)" stroke="url(#${gid}t)"/>` +
             `<path class="hot-p" d="${d}" fill="url(#${gid}h)" stroke="url(#${gid}h)"/></g>${label}</g>`;
    }).join("") +
    `<rect class="pill" height="26" rx="13"/><text class="pill-text"></text>` +
    `<text class="pill-hint" y="17">${hintText}</text>`;
  return [...el.querySelectorAll(".tile")];
}

// Tiles pop out of the hub one after another.
function popTiles(list) {
  list.forEach((t, i) => {
    place(t, -14);
    t.style.opacity = 0;
    setTimeout(() => { if (t.isConnected) { place(t, t.classList.contains("hot") ? POP : 0); t.style.opacity = 1; } }, 30 + 22 * i);
  });
}

function setPill(el, text, bold) {
  const hasHint = !!el.querySelector(".pill-hint").textContent;
  const w = Math.min(Math.max(70, text.length * 7.8 + 28), (IN - 10) * 2), y = hasHint ? -7 : 0;
  const rect = el.querySelector(".pill"), label = el.querySelector(".pill-text");
  rect.setAttribute("x", f2(-w / 2));
  rect.setAttribute("y", f2(y - 13));
  rect.setAttribute("width", f2(w));
  label.setAttribute("y", f2(y + 1));
  label.textContent = text.toUpperCase();
  label.classList.toggle("em", !!bold);
}

function renderWheel(f) {
  const list = f[mode], other = f[mode === "formats" ? "tools" : "formats"];
  tiles = drawWheel(svg, list, mode === "tools", other.length ? (mode === "tools" ? "⇧  formats" : "⌥  tools") : "", "h");
  hovered = -1;
  setPill(svg, mode === "tools" ? "Tools" : "Convert", false);
  popTiles(tiles);
}

function openWheel(f, x, y, again) {
  mode = f[preferred].length ? preferred : (f.formats.length ? "formats" : "tools");
  // Keep the whole wheel on screen: inside the desktop, below the menu bar and above the Dock or the bottom edge.
  const b = desk.getBoundingClientRect(), dk = $("#dock").getBoundingClientRect(), w = $(".widget").getBoundingClientRect();
  scale = Math.min(1, (b.width - 16) / 340, (b.height - 40) / 340, ((dk.top < innerHeight ? dk.top : innerHeight) - 44) / 340);
  let half = 170 * scale, top = Math.max(half + 36, 36 + half - b.top);
  const cx = clamp(x, half + 8, b.width - half - 8);
  const floor = dk.top < innerHeight && dk.left < b.left + cx + half && dk.right > b.left + cx - half ? dk.top : innerHeight;
  const low = Math.min(b.height, floor - b.top) - 8, wb = w.bottom - b.top + 8, fit = (low - wb) / 340;
  const kl = keyBtns[0].getBoundingClientRect().left, kr = keyBtns[keyBtns.length - 1].getBoundingClientRect().right;
  // In click mode keep the wheel below the ⇧/⌥ keycaps, so tapping them switches wheels instead of picking a tile:
  // scroll down a little if that makes room, and make the wheel a little smaller if need be.
  if (cur && cur.how === "click" && y > wb - 8 && kl < b.left + cx + half + 10 && kr > b.left + cx - half - 10) {
    const gain = Math.min(340 * (scale - fit), w.top - 36);
    if (!again && gain > 0 && fit + gain / 340 > scale * .75) {
      try { scrollBy({ top: gain, behavior: "instant" }); } catch { scrollBy(0, gain); }
      return openWheel(f, x, y, true);
    }
    if (fit > scale * .75) {
      scale = Math.min(scale, fit);
      half = 170 * scale;
      top = Math.max(half + 36, 36 + half - b.top, wb + half);
    }
  }
  center = [cx, clamp(y, top, Math.max(top, low - half))];
  renderWheel(f);
  ring.style.left = center[0] + "px";
  ring.style.top = center[1] + "px";
  ring.style.setProperty("--k", scale);
  clearTimeout(closeT);
  ring.classList.remove("closing");
  ring.classList.add("on");
  syncKeys();
}

function closeWheel(picked = -1) {
  if (picked >= 0 && tiles[picked]) place(tiles[picked], 18);
  if (ring.classList.contains("on")) {
    ring.classList.add("closing");
    clearTimeout(closeT);
    closeT = setTimeout(() => ring.classList.remove("closing"), 260);
  }
  ring.classList.remove("on", "click");
  FILES.forEach(f => f.el.classList.remove("sel"));
  if (cur) cur.open = false;
  hovered = -1;
  syncKeys();
}

function hitTest(e) {
  if (!cur) return -1;
  const [x, y] = deskPoint(e);
  const dx = (x - center[0]) / scale, dy = (y - center[1]) / scale, d = Math.hypot(dx, dy);
  const n = cur.f[mode].length, s = 2 * Math.PI / n;
  if (d < IN - 4 || d > DISC + 30) return -1;
  let a = Math.atan2(dx, -dy);
  if (a < 0) a += 2 * Math.PI;
  return Math.floor((a + s / 2) / s) % n;
}

function setHover(i) {
  if (i === hovered) return;
  hovered = i;
  tiles.forEach((t, j) => {
    t.classList.toggle("hot", j === i);
    if (t.style.opacity === "1") place(t, j === i ? POP : 0);
  });
  setPill(svg, i >= 0 && cur ? cur.f[mode][i][0] : (mode === "tools" ? "Tools" : "Convert"), i >= 0);
}

function kbHover(i, opening, prefix = "") {
  if (!cur) return;
  setHover(i);
  const list = cur.f[mode], n = list.length;
  announce(opening
    ? `Wheel open for ${cur.f.name}: ${n} ${mode === "tools" ? "tools" : "formats"}. ${list[i][0]}, 1 of ${n}. Arrow keys choose, Enter converts, Option shows tools, Shift shows formats, Escape cancels.`
    : `${prefix}${list[i][0]}, ${i + 1} of ${n}`);
}

function pickKb(i) {
  const c = cur, a = +tiles[i].dataset.a, [lx, ly] = pt((IN + OUT) / 2 + POP, a);
  cur = null;
  lastPick = performance.now();
  convert(c.f, i, center[0] + lx * scale, center[1] + ly * scale);
  c.el.focus({ preventScroll: true });
}

function convert(f, i, x, y) {
  const [title, out] = f[mode][i];
  closeWheel(i);
  used = true;
  stopIdle();
  updateHint();
  showHud(`${title}…`, x, y, false);
  setTimeout(() => {
    showHud(out, x, y, true);
    addOutput(out, f, x, y);
    announce(`Saved ${out} next to ${f.name}.`);
  }, reduce.matches ? 60 : 560);
}

function showHud(text, x, y, done) {
  const b = desk.getBoundingClientRect();
  hudText.textContent = text;
  hud.classList.toggle("done", done);
  hud.style.left = f2(clamp(x, 130, Math.max(130, b.width - 130))) + "px";
  hud.style.top = f2(y) + "px";
  hud.classList.add("on");
  clearTimeout(hudT);
  if (done) hudT = setTimeout(() => hud.classList.remove("on"), 1800);
}

// The converted copy flies out of the wheel and lands next to the original with a little bounce.
function addOutput(name, src, fromX, fromY) {
  const ext = name.includes(".") ? name.split(".").pop() : "";
  const el = fileEl(name, ext ? (KIND_OF[ext] || "zip") : "folder", ext.toUpperCase(), "div");
  el.classList.add("out");
  el.setAttribute("aria-hidden", "true");
  const p = landingSpot(src);
  el.style.left = f2(p.x) + "px";
  el.style.top = f2(p.y) + "px";
  iconsEl.append(el);
  const o = { el, src, x: p.x, y: p.y };
  outs.push(o);
  if (outs.length > 5) dropOut(outs[0]);
  if (!reduce.matches && el.animate) {
    const dx = fromX - p.x - ICON_W / 2, dy = fromY - p.y - 34;
    el.animate([
      { transform: `translate(${f2(dx)}px, ${f2(dy)}px) scale(.3)`, opacity: 0 },
      { transform: `translate(${f2(dx * .45)}px, ${f2(dy * .45 - 80)}px) scale(.8)`, opacity: 1, offset: .42 },
      { transform: "translate(0px, 0px) scale(1.12, .84)", offset: .7 },
      { transform: "translate(0px, -9px) scale(.95, 1.05)", offset: .85 },
      { transform: "translate(0px, 0px) scale(1)" },
    ], { duration: 760, easing: "cubic-bezier(.25, .7, .35, 1)" });
  }
  o.t = setTimeout(() => dropOut(o), 9000);
}

// The free spot closest to the original (sideways first), around the icon area and off the widget; else a small stack beside it.
function landingSpot(src) {
  const d = desk.getBoundingClientRect(), z = zone.getBoundingClientRect(), wr = $(".widget").getBoundingClientRect();
  const W = { l: wr.left - d.left, r: wr.right - d.left, t: wr.top - d.top, b: wr.bottom - d.top };
  const x0 = Math.max(4, Math.min(z.left - d.left - 20, src.x - 2 * ICON_W)), x1 = Math.min(d.width - ICON_W - 4, Math.max(z.right - d.left - ICON_W + 20, src.x + 2 * ICON_W));
  const y0 = Math.max(36, Math.min(z.top - d.top - 10, src.y - 2 * ICON_H)), y1 = Math.min(d.height - ICON_H - 96, Math.max(z.bottom - d.top - ICON_H + 30, src.y + 2 * ICON_H));
  const taken = FILES.map(f => [f.x, f.y]).concat(outs.map(o => [o.x, o.y]));
  const free = (x, y) => !taken.some(([tx, ty]) => Math.abs(tx - x) < ICON_W - 4 && Math.abs(ty - y) < ICON_H - 16) &&
    !(x < W.r && x + ICON_W > W.l && y < W.b && y + ICON_H - 12 > W.t);
  let best = null, bestD = Infinity;
  for (let y = y0; y <= y1; y += 12) {
    for (let x = x0; x <= x1; x += 12) {
      const dist = Math.hypot(x - src.x, (y - src.y) * 1.35);
      if (dist < bestD && free(x, y)) { bestD = dist; best = { x, y }; }
    }
  }
  if (best) return best;
  const n = outs.filter(o => o.src === src).length, p = { x: src.x + ICON_W + 6 + n * 10, y: src.y + n * 22 };
  clampPos(p, d);
  return p;
}

function dropOut(o) {
  if (!outs.includes(o)) return;
  outs = outs.filter(x => x !== o);
  clearTimeout(o.t);
  o.el.classList.add("gone");
  setTimeout(() => o.el.remove(), 450);
}

function updateHint() {
  hint.textContent = !running ? "Shiftvert quit, so files just move."
    : used ? (coarse ? "Nice! Tap outside the wheel to cancel." : "Nice! Drop in the middle to cancel.")
    : coarse ? "Drag or tap a file to try it."
    : "Drag any file (no ⇧ needed here). Tap ⌥ for tools.";
}
function nudgeHint() {
  const w = $("#openApp");
  w.classList.remove("nope");
  void w.offsetWidth;
  w.classList.add("nope");
}
updateHint();

// Click mode: hover, click a tile to convert, click anywhere else to cancel.
desk.addEventListener("pointermove", e => {
  if (cur && cur.how === "click" && cur.open && e.pointerType !== "touch") setHover(hitTest(e));
});
document.addEventListener("click", e => {
  if (!cur || cur.how !== "click" || !cur.open) return;
  if (e.target.closest(".keys")) return;
  const i = e.target.closest("#ring") ? hitTest(e) : -1;
  if (i >= 0) {
    const c = cur, [x, y] = deskPoint(e);
    if (e.pointerType === "touch" || !e.pointerType) setHover(i);
    cur = null;
    lastPick = performance.now();
    convert(c.f, i, x, y);
  } else {
    closeWheel();
    cur = null;
  }
});

// Keyboard: ⇧ / ⌥ like the app, plus arrows, Enter and Escape for the wheel in click mode.
addEventListener("keydown", e => {
  if (!picker.hidden) return;
  if (e.key === "Shift") { pressKey("formats", true); setMode("formats", !(cur && cur.open)); return; }
  if (e.key === "Alt") { e.preventDefault(); pressKey("tools", true); setMode("tools", !(cur && cur.open)); return; }
  if (e.key === "Escape") {
    if (openMenu) { closeMenus(true); return; }
    if (cur && cur.how === "click") {
      e.preventDefault();
      const el = cur.el;
      closeWheel();
      cur = null;
      el.focus({ preventScroll: true });
      announce("Cancelled.");
    }
    return;
  }
  if (!cur || cur.how !== "click" || !cur.open) return;
  const n = cur.f[mode].length;
  if (e.key === "ArrowRight" || e.key === "ArrowDown") { e.preventDefault(); cur.kb = true; kbHover(hovered < 0 ? 0 : (hovered + 1) % n); }
  else if (e.key === "ArrowLeft" || e.key === "ArrowUp") { e.preventDefault(); cur.kb = true; kbHover(hovered <= 0 ? n - 1 : hovered - 1); }
  else if (e.key === "Enter" || e.key === " ") { e.preventDefault(); if (hovered >= 0) pickKb(hovered); else { cur.kb = true; kbHover(0); } }
  else if (e.key === "Tab") { closeWheel(); cur = null; }
});
addEventListener("keyup", e => {
  if (e.key === "Shift") pressKey("formats", false);
  if (e.key === "Alt") pressKey("tools", false);
});
addEventListener("blur", () => { pressKey("formats", false); pressKey("tools", false); });

// ---------- Menus (menu bar) ----------
let openMenu = null;
const menuItems = m => $$(".mi:not([aria-disabled='true'])", m);
function closeMenus(focusTrigger = false) {
  if (!openMenu) return;
  const m = openMenu, t = m.querySelector("[aria-haspopup]");
  openMenu = null;
  m.querySelector(".dropdown").hidden = true;
  t.setAttribute("aria-expanded", "false");
  if (focusTrigger) t.focus();
}
function showMenu(m, focusFirst) {
  if (openMenu !== m) closeMenus();
  openMenu = m;
  m.querySelector(".dropdown").hidden = false;
  m.querySelector("[aria-haspopup]").setAttribute("aria-expanded", "true");
  if (focusFirst) { const first = menuItems(m)[0]; if (first) first.focus(); }
}
$$(".menu").forEach(m => {
  const t = m.querySelector("[aria-haspopup]"), dd = m.querySelector(".dropdown");
  t.addEventListener("click", e => {
    e.stopPropagation();
    if (openMenu === m) closeMenus(); else showMenu(m, e.detail === 0);
  });
  t.addEventListener("pointerenter", e => { if (e.pointerType === "mouse" && openMenu && openMenu !== m) showMenu(m, false); });
  t.addEventListener("keydown", e => { if (e.key === "ArrowDown") { e.preventDefault(); showMenu(m, true); } });
  dd.addEventListener("keydown", e => {
    const list = menuItems(m), i = list.indexOf(document.activeElement);
    if (e.key === "ArrowDown") { e.preventDefault(); list[(i + 1) % list.length].focus(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); list[(i - 1 + list.length) % list.length].focus(); }
    else if (e.key === "Home") { e.preventDefault(); list[0].focus(); }
    else if (e.key === "End") { e.preventDefault(); list[list.length - 1].focus(); }
    else if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); closeMenus(true); }
    else if (e.key === "Tab") closeMenus();
  });
  dd.addEventListener("click", e => {
    const it = e.target.closest(".mi");
    if (!it || it.getAttribute("aria-disabled") === "true") { e.stopPropagation(); return; }
    closeMenus(e.detail === 0 && !it.href);
  });
});
document.addEventListener("click", e => { if (openMenu && !openMenu.contains(e.target)) closeMenus(); });

// The ⟳ menu does what the app's menu does.
const statusMenu = $("#statusMenu"), loginItem = $("#mLogin"), openApp = $("#openApp");
$("#mConvert").addEventListener("click", () => openPicker());
loginItem.addEventListener("click", () => loginItem.setAttribute("aria-checked", loginItem.getAttribute("aria-checked") === "true" ? "false" : "true"));
$("#mQuit").addEventListener("click", e => setRunning(false, e.detail === 0));
openApp.addEventListener("click", e => { e.stopPropagation(); setRunning(true, e.detail === 0); });
function setRunning(on, kb) {
  running = on;
  if (cur && cur.how === "click") { closeWheel(); cur = null; }
  statusMenu.hidden = !on;
  statusMenu.classList.toggle("pop", on);
  openApp.hidden = on;
  updateHint();
  if (!on && kb) openApp.focus({ preventScroll: true });
  if (on && kb) $("#statusBtn").focus();
  announce(on ? "Shiftvert is running. Its menu is back in the menu bar." : "Shiftvert quit. Use Open Shiftvert to start it again.");
}

// ---------- Convert Files… picker ----------
const picker = $("#picker"), pList = $("#pList");
let pSel = 0, pReturn = null;
FILES.forEach((f, i) => {
  const li = document.createElement("li");
  li.id = "po" + i;
  li.className = "p-row";
  li.setAttribute("role", "option");
  li.innerHTML = `${fileIcon(f.kind, f.ext)}<span class="p-n"></span><span class="p-k"></span>`;
  li.querySelector(".p-n").textContent = f.name;
  li.querySelector(".p-k").textContent = KIND_NAME[f.kind];
  li.addEventListener("click", () => pickRow(i));
  li.addEventListener("dblclick", () => { pickRow(i); pickerOpen(); });
  pList.append(li);
});
function pickRow(i) {
  pSel = i;
  $$(".p-row", pList).forEach((r, j) => r.setAttribute("aria-selected", String(j === i)));
  pList.setAttribute("aria-activedescendant", "po" + i);
}
function openPicker() {
  if (!running) return;
  closeMenus();
  if (cur) { closeWheel(); cur = null; }
  pReturn = $("#statusBtn");  // the picker only opens from the ⟳ menu, which is closed by now
  scrollTo({ top: 0, behavior: reduce.matches ? "auto" : "smooth" });
  picker.hidden = false;
  pickRow(pSel);
  pList.focus({ preventScroll: true });
}
function closePicker(restore) {
  picker.hidden = true;
  if (restore && pReturn && pReturn.focus) pReturn.focus({ preventScroll: true });
}
function pickerOpen() {
  // Finish the scroll up to the desktop first, or the wheel would be placed mid-scroll and end up off screen.
  if (scrollY) try { scrollTo({ top: 0, behavior: "instant" }); } catch { scrollTo(0, 0); }
  const f = FILES[pSel], b = desk.getBoundingClientRect();
  closePicker(false);
  openClick(f, b.width / 2, clamp(innerHeight / 2 - b.top, 0, b.height), true);
  f.el.focus({ preventScroll: true });
}
picker.addEventListener("keydown", e => {
  e.stopPropagation();
  if (e.key === "Escape") { e.preventDefault(); closePicker(true); }
  else if (e.target === pList && (e.key === "ArrowDown" || e.key === "ArrowUp")) {
    e.preventDefault();
    pickRow((pSel + (e.key === "ArrowDown" ? 1 : FILES.length - 1)) % FILES.length);
  }
  else if (e.target === pList && e.key === "Enter") { e.preventDefault(); pickerOpen(); }
  else if (e.key === "Tab") {
    const stops = [pList, $("#pCancel"), $("#pOpen")], i = stops.indexOf(document.activeElement);
    e.preventDefault();
    stops[(i + (e.shiftKey ? stops.length - 1 : 1)) % stops.length].focus();
  }
});
picker.addEventListener("click", e => { e.stopPropagation(); if (e.target === picker) closePicker(true); });
$("#pCancel").addEventListener("click", () => closePicker(true));
$("#pOpen").addEventListener("click", pickerOpen);

// ---------- What it converts (Finder column view) ----------
const KINDS = [
  { name: "Images", icon: ["img", ""], reads: "HEIC, PNG, JPG, TIFF, GIF, BMP, WebP and more", example: "photo.heic → photo.png",
    formats: [["PNG"], ["JPG"], ["HEIC"], ["AVIF", "if macOS can"], ["TIFF"], ["GIF"], ["BMP"], ["PDF"]],
    tools: [["Compress", "as JPG or HEIC"], ["Resize 50%"], ["Crop"], ["Strip EXIF", "removes location"], ["Merge PDF", "2+ images"], ["Zip"]] },
  { name: "Video", icon: ["vid", ""], reads: "MOV, MP4, M4V, AVI", example: "clip.mov → clip.mp4",
    formats: [["MP4"], ["MOV"], ["M4V"], ["GIF", "first 15 s"], ["M4A", "audio only"]],
    tools: [["Compress", "to 720p"], ["Trim"], ["Zip"]],
    note: "No MKV or WebM. AVI only if QuickTime Player can play it." },
  { name: "Audio", icon: ["aud", "WAV"], reads: "MP3, WAV, AIFF, M4A, FLAC", example: "song.wav → song.m4a",
    formats: [["M4A"], ["WAV"], ["AIFF"], ["FLAC"]],
    tools: [["Compress"], ["Trim"], ["Zip"]],
    note: "Opens MP3, but can't save as MP3." },
  { name: "PDF", icon: ["pdf", "PDF"], reads: "Any PDF, including multi-page", example: "report.pdf → report.txt",
    formats: [["PNG", "per page"], ["JPG", "per page"], ["TXT"]],
    tools: [["Compress"], ["Split"], ["Merge", "2+ PDFs"], ["Zip"]],
    note: "No password-protected PDFs." },
  { name: "Documents", icon: ["doc_", "DOCX"], reads: "Word, RTF, ODT, HTML, TXT, Markdown (as plain text)", example: "notes.docx → notes.pdf",
    formats: [["PDF"], ["DOCX"], ["RTF"], ["TXT"], ["HTML"], ["ODT"]],
    tools: [["Zip"]],
    note: "Word or ODT files with pictures: TXT only." },
  { name: "Anything", icon: ["folder", ""], reads: "Any file or folder", example: "Project → Project.zip",
    formats: [],
    tools: [["Zip"]],
    note: "Several files become one Archive.zip." },
];
const kTabs = $("#kinds"), kPanel = $("#kpanel"), fRows = $("#fRows"), tRows = $("#tRows"), mini = $("#mini");
let kSel = 0, mMode = "formats", mTiles = [];
const CHEV = `<svg class="chev" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7"/></svg>`;
KINDS.forEach((k, i) => {
  const b = document.createElement("button");
  b.type = "button";
  b.className = "kind";
  b.id = "kt" + i;
  b.setAttribute("role", "tab");
  b.setAttribute("aria-controls", "kpanel");
  b.innerHTML = `<span class="k-ic">${fileIcon(k.icon[0], k.icon[1])}</span><span>${k.name}</span>${CHEV}`;
  b.addEventListener("click", () => showKind(i));
  kTabs.append(b);
});
kTabs.addEventListener("keydown", e => {
  const step = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[e.key];
  if (!step) return;
  e.preventDefault();
  const n = (kSel + step + KINDS.length) % KINDS.length;
  showKind(n);
  $("#kt" + n).focus();
});
const rowKind = t => KIND_OF[t.toLowerCase()] || "doc_";
function rowHTML([t, note], m, i) {
  const ic = m === "tools"
    ? `<svg class="tool-ic" viewBox="0 0 24 24" aria-hidden="true"><path d="${ICONS[t] || ICONS.Zip}"/></svg>`
    : `<span class="row-file">${fileIcon(rowKind(t), t)}</span>`;
  return `<li class="row" data-m="${m}" data-i="${i}">${ic}<span class="row-t">${t}</span>${note ? `<span class="row-n">${note}</span>` : ""}</li>`;
}
function showKind(i) {
  kSel = i;
  const k = KINDS[i];
  $$(".kind", kTabs).forEach((b, j) => { b.setAttribute("aria-selected", String(j === i)); b.tabIndex = j === i ? 0 : -1; });
  kPanel.setAttribute("aria-labelledby", "kt" + i);
  fRows.innerHTML = k.formats.length ? k.formats.map((r, j) => rowHTML(r, "formats", j)).join("") : `<li class="row empty">No format changes.</li>`;
  tRows.innerHTML = k.tools.map((r, j) => rowHTML(r, "tools", j)).join("");
  $("#pvName").textContent = k.name;
  $("#pvReads").textContent = k.reads;
  $("#pvEx").textContent = k.example;
  $("#pvNote").textContent = k.note || "";
  $("#pvNoteT").hidden = $("#pvNote").hidden = !k.note;
  const nf = k.formats.length, nt = k.tools.length;
  $("#fStat").textContent = `${nf} format${nf === 1 ? "" : "s"}, ${nt} tool${nt === 1 ? "" : "s"}`;
  drawMini(nf ? "formats" : "tools");
}
function drawMini(m) {
  const k = KINDS[kSel], other = k[m === "formats" ? "tools" : "formats"];
  mMode = m;
  mTiles = drawWheel(mini, k[m], m === "tools", other.length ? (m === "tools" ? "⇧  formats" : "⌥  tools") : "", "m");
  setPill(mini, m === "tools" ? "Tools" : "Convert", false);
  popTiles(mTiles);
}
function miniHover(m, i) {
  if (m && m !== mMode) drawMini(m);
  mTiles.forEach((t, j) => {
    t.classList.toggle("hot", j === i);
    if (t.style.opacity === "1") place(t, j === i ? POP : 0);
  });
  setPill(mini, i >= 0 ? KINDS[kSel][mMode][i][0] : (mMode === "tools" ? "Tools" : "Convert"), i >= 0);
  $$(".row", kPanel).forEach(r => r.classList.toggle("hl", r.dataset.m === mMode && +r.dataset.i === i));
}
kPanel.addEventListener("pointerover", e => {
  const r = e.target.closest(".row[data-m]");
  if (r) miniHover(r.dataset.m, +r.dataset.i);
});
kPanel.addEventListener("pointerleave", () => miniHover(null, -1));
showKind(0);

// ---------- Install steps ----------
const steps = $$(".step"), stepBtns = $$(".i-steps button"), iBack = $("#iBack"), iNext = $("#iNext"), iDl = $("#iDl");
let st = 0;
function go(n) {
  const wasNext = document.activeElement === iNext, wasBack = document.activeElement === iBack;
  const moved = n !== st;
  st = clamp(n, 0, steps.length - 1);
  steps.forEach((s, i) => { s.classList.toggle("off", i !== st); s.classList.toggle("cur", i === st); });
  if (moved) announce(`Step ${st + 1} of ${steps.length}: ${steps[st].querySelector("h3").textContent}`);
  stepBtns.forEach((b, i) => {
    b.setAttribute("aria-current", i === st ? "step" : "false");
    b.classList.toggle("done", i < st);
  });
  iBack.disabled = st === 0;
  iNext.hidden = st === steps.length - 1;
  iDl.hidden = st !== steps.length - 1;
  if (wasNext && iNext.hidden) iDl.focus();
  if (wasBack && iBack.disabled) iNext.focus();
}
stepBtns.forEach((b, i) => b.addEventListener("click", () => go(i)));
iBack.addEventListener("click", () => go(st - 1));
iNext.addEventListener("click", () => go(st + 1));
$$("[data-go]").forEach(b => b.addEventListener("click", () => go(+b.dataset.go)));
$$("[data-nope]").forEach(b => b.addEventListener("click", () => { b.classList.remove("nope"); void b.offsetWidth; b.classList.add("nope"); }));
go(Math.max(0, (+new URLSearchParams(location.search).get("step") || 1) - 1));  // ?step=2 from the privacy page's after-download sheet

// ---------- Windows: slide up into view; the one in the middle of the screen is the key window ----------
const mbApp = $("#mbApp"), dock = $("#dock"), dks = $$(".dk", dock);
function setKey(sec) {
  mbApp.textContent = sec.dataset.app;
  $$(".space .win").forEach(w => w.classList.toggle("key", sec.contains(w)));
  dks.forEach(d => d.classList.toggle("on", d.dataset.sec === sec.id));
}
if ("IntersectionObserver" in window) {
  const io = new IntersectionObserver(es => es.forEach(en => {
    if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
  }), { threshold: .08, rootMargin: "0px 0px -6% 0px" });
  $$(".space .win").forEach(w => io.observe(w));
  const ko = new IntersectionObserver(es => es.forEach(en => { if (en.isIntersecting) setKey(en.target); }), { rootMargin: "-48% 0px -48% 0px" });
  $$("[data-app]").forEach(s => ko.observe(s));
} else {
  $$(".space .win").forEach(w => w.classList.add("in"));
}
setKey(desk);

// ---------- Dock: magnify on hover, bounce on click, tuck away while scrolling down on phones ----------
const fine = matchMedia("(hover: hover) and (pointer: fine)");
let dockRaf = 0, dockX = null;
function magnify() {
  dockRaf = 0;
  const kids = [...dock.children], size = dks[0].offsetWidth, base = dock.getBoundingClientRect().left;
  const s = kids.map(k => {
    if (dockX === null || !k.classList.contains("dk")) return 1;
    const dist = Math.abs(dockX - (base + k.offsetLeft + k.offsetWidth / 2));
    return 1 + .5 * Math.pow(Math.max(0, 1 - dist / (size * 2.6)), 1.6);
  });
  const extra = s.map(v => (v - 1) * size), total = extra.reduce((a, b) => a + b, 0);
  let acc = 0;
  kids.forEach((k, i) => {
    k.style.setProperty("--tx", f2(acc + extra[i] / 2 - total / 2) + "px");
    acc += extra[i];
    k.style.setProperty("--s", s[i].toFixed(3));
    k.style.setProperty("--lift", f2(extra[i]));
  });
  dock.style.setProperty("--grow", ((dock.offsetWidth + total) / dock.offsetWidth).toFixed(3));
}
dock.addEventListener("pointermove", e => {
  if (!fine.matches || reduce.matches) return;
  dockX = e.clientX;
  if (!dockRaf) dockRaf = requestAnimationFrame(magnify);
});
dock.addEventListener("pointerleave", () => {
  dockX = null;
  if (!dockRaf) dockRaf = requestAnimationFrame(magnify);
});
dks.forEach(d => d.addEventListener("click", () => {
  if (reduce.matches) return;
  d.classList.remove("bounce");
  void d.offsetWidth;
  d.classList.add("bounce");
}));
let lastY = scrollY;
addEventListener("scroll", () => {
  const y = scrollY;
  if (Math.abs(y - lastY) < 6) return;
  dock.classList.toggle("tuck", innerWidth < 760 && y > lastY && y > 300 && !dock.matches(":focus-within"));
  lastY = y;
}, { passive: true });

// "Show me step by step" in the after-download sheet (download.js) opens the installer at Move to Applications.
document.addEventListener("installstep", e => go(e.detail));

// Shiftvert in action: the film loads lazily, plays muted while on screen, and never scroll-jacks.
// If the browser won't autoplay it (Safari in Low Power Mode, reduced motion), a big ▶ sits on the poster instead.
(() => {
  const box = $(".film"), film = $("#film"), play = $("#filmPlay"), sound = $("#filmSound"), big = $("#filmBig"), msg = $("#filmMsg");
  const PAUSE = '<rect x="3.5" y="2.5" width="3" height="11" rx="1"/><rect x="9.5" y="2.5" width="3" height="11" rx="1"/>';
  const PLAY = '<path d="M4.5 2.8v10.4a.6.6 0 0 0 .9.5l8.4-5.2a.6.6 0 0 0 0-1L5.4 2.3a.6.6 0 0 0-.9.5z"/>';
  // Like Pause/Play, the sound button names what it does; its icon shows whether the video is silent right now.
  const SPEAKER = '<path d="M2.5 6h2.5l3.5-3v10l-3.5-3H2.5z" fill="currentColor"/>';
  const SILENT = SPEAKER + '<path d="M11 6l4 4M15 6l-4 4"/>', LOUD = SPEAKER + '<path d="M11 5.5a3.5 3.5 0 0 1 0 5M12.8 3.6a6 6 0 0 1 0 8.8"/>';
  let wanted = !reduce.matches, onScreen = false, failed = false;
  const ui = () => {
    play.querySelector("span").textContent = wanted ? "Pause" : "Play";
    play.setAttribute("aria-label", wanted ? "Pause video" : "Play video");
    play.querySelector("svg").innerHTML = wanted ? PAUSE : PLAY;
    if (wanted && document.activeElement === big) play.focus({ preventScroll: true });
    big.hidden = wanted || failed;
    if (!wanted || !onScreen || failed) box.classList.remove("loading");
  };
  // The file is missing or can't be read (e.g. the page opened as a preview without its files next to it).
  const fail = () => { failed = true; wanted = false; box.classList.add("failed"); msg.hidden = false; ui(); };
  const sync = () => {
    if (failed) return;
    if (wanted && onScreen) {
      film.preload = "auto";
      if (film.paused) box.classList.add("loading");
      const p = film.play();
      if (p && p.catch) p.catch(err => {
        if (err && err.name === "AbortError") return;  // interrupted by a pause or a reload, not a failure
        if (err && err.name === "NotSupportedError") return fail();  // no playable source
        wanted = false;  // autoplay blocked: show the ▶ so one click starts it
        ui();
      });
    } else film.pause();
    ui();
  };
  const toggle = () => { wanted = !wanted; if (wanted) onScreen = true; sync(); };
  play.addEventListener("click", toggle);
  film.addEventListener("click", toggle);
  big.addEventListener("click", () => { wanted = true; onScreen = true; sync(); });
  film.addEventListener("playing", () => box.classList.remove("loading"));
  film.addEventListener("waiting", () => { if (wanted && onScreen) box.classList.add("loading"); });
  film.querySelector("source").addEventListener("error", fail);
  sound.addEventListener("click", () => {
    film.muted = !film.muted;
    sound.querySelector("span").textContent = film.muted ? "Turn on sound" : "Mute";
    sound.querySelector("svg").innerHTML = film.muted ? SILENT : LOUD;
    sound.setAttribute("aria-pressed", String(!film.muted));
    if (!film.muted) { wanted = true; onScreen = true; sync(); }
  });
  if ("IntersectionObserver" in window) {
    new IntersectionObserver(([en]) => { if (en.isIntersecting && wanted) film.preload = "auto"; }, { rootMargin: "600px 0px" }).observe(film);
    new IntersectionObserver(([en]) => { onScreen = en.isIntersecting; sync(); }, { threshold: .35 }).observe(film);
  } else { onScreen = true; film.preload = "auto"; }
  sync();
})();

// About window: the wheel turns slowly around the app icon while it's on screen.
(() => {
  const el = $("#embWheel"), photo = FILES.find(f => f.ext === "HEIC") || FILES[0], list = photo.formats;
  const tiles = drawWheel(el, list, false, "", "em");
  let i = 0, timer = 0;
  const tick = () => { tiles.forEach((t, j) => { t.classList.toggle("hot", j === i); place(t, j === i ? POP : 0); }); i = (i + 1) % tiles.length; };
  tick();
  if (reduce.matches || !("IntersectionObserver" in window)) return;
  new IntersectionObserver(([en]) => {
    clearInterval(timer);
    if (en.isIntersecting) timer = setInterval(tick, 1400);
  }).observe(el);
})();
