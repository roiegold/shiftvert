const $ = (s, r = document) => r.querySelector(s);
const reduce = matchMedia("(prefers-reduced-motion: reduce)");

// Menu bar clock
const cDate = $("#cDate"), cTime = $("#cTime");
function tick() {
  const d = new Date();
  cDate.textContent = d.toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" }).replace(/,/g, "");
  cTime.textContent = d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}
tick(); setInterval(tick, 15000);

// Wallpaper: a few stars for dusk, and a fine grain
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

// Appearance: light is day, dark is dusk
const root = document.documentElement, sysDark = matchMedia("(prefers-color-scheme: dark)"), themeBtn = $("#theme");
const isDark = () => root.dataset.theme ? root.dataset.theme === "dark" : sysDark.matches;
function syncTheme() { themeBtn.setAttribute("aria-label", isDark() ? "Switch to light appearance" : "Switch to dark appearance"); }
themeBtn.addEventListener("click", () => {
  // Remembered for this tab only (never sent anywhere), so the main page opens in the same appearance.
  const flip = () => { root.dataset.theme = isDark() ? "light" : "dark"; syncTheme(); try { sessionStorage.setItem("shiftvert-theme", root.dataset.theme); } catch {} };
  if (document.startViewTransition && !reduce.matches) document.startViewTransition(flip); else flip();
});
if (sysDark.addEventListener) sysDark.addEventListener("change", syncTheme);
syncTheme();

// Dock: magnify on hover, like on the main page
(() => {
  const dock = $("#dock"), dks = [...dock.querySelectorAll(".dk")], fine = matchMedia("(hover: hover) and (pointer: fine)");
  let raf = 0, dockX = null;
  function magnify() {
    raf = 0;
    const kids = [...dock.children], size = dks[0].offsetWidth, base = dock.getBoundingClientRect().left;
    const s = kids.map(k => {
      if (dockX === null || !k.classList.contains("dk")) return 1;
      const dist = Math.abs(dockX - (base + k.offsetLeft + k.offsetWidth / 2));
      return 1 + .5 * Math.pow(Math.max(0, 1 - dist / (size * 2.6)), 1.6);
    });
    const extra = s.map(v => (v - 1) * size), total = extra.reduce((a, b) => a + b, 0);
    let acc = 0;
    kids.forEach((k, i) => {
      k.style.setProperty("--tx", (acc + extra[i] / 2 - total / 2).toFixed(1) + "px");
      acc += extra[i];
      k.style.setProperty("--s", s[i].toFixed(3));
      k.style.setProperty("--lift", extra[i].toFixed(1));
    });
    dock.style.setProperty("--grow", ((dock.offsetWidth + total) / dock.offsetWidth).toFixed(3));
  }
  dock.addEventListener("pointermove", e => {
    if (!fine.matches || reduce.matches) return;
    dockX = e.clientX;
    if (!raf) raf = requestAnimationFrame(magnify);
  });
  dock.addEventListener("pointerleave", () => { dockX = null; if (!raf) raf = requestAnimationFrame(magnify); });
  // On phones the Dock tucks away while scrolling down, so it doesn't cover the text.
  let lastY = scrollY;
  addEventListener("scroll", () => {
    const y = scrollY;
    if (Math.abs(y - lastY) < 6) return;
    dock.classList.toggle("tuck", innerWidth < 760 && y > lastY && y > 300 && !dock.matches(":focus-within"));
    lastY = y;
  }, { passive: true });
})();
