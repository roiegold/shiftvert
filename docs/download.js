// Download links, plus what each visitor sees after pressing one: next steps on a Mac, a link to send on a phone.
(() => {
  const $ = s => document.querySelector(s);

  // Links point at this repo's latest GitHub release. The repo is worked out from the Pages URL (user.github.io/repo).
  const host = location.hostname.endsWith(".github.io") ? location.hostname.split(".")[0] : null;
  const REPO = host ? `${host}/${location.pathname.split("/")[1] || host + ".github.io"}` : "roiegold/shiftvert";
  const links = {
    download: `https://github.com/${REPO}/releases/latest/download/Shiftvert.zip`,
    repo: `https://github.com/${REPO}`,
    issues: `https://github.com/${REPO}/issues`,
    releases: `https://github.com/${REPO}/releases/latest`,
  };
  for (const [k, url] of Object.entries(links)) document.querySelectorAll(`[data-${k}]`).forEach(a => a.href = url);

  const phone = /iPhone|iPad|iPod|Android/.test(navigator.userAgent) || (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1);
  if (phone) {
    // Phones and tablets: offer the link for a Mac instead of downloading a Mac app.
    const dlg = $("#macOnly"), send = $("#moSend"), SITE = "https://shiftvert.com/";
    document.addEventListener("click", e => {
      const a = e.target.closest("[data-download]");
      if (!a || !dlg.showModal) return;
      if (dlg.contains(a)) { dlg.close(); return; }
      e.preventDefault();
      send.textContent = navigator.share ? "Share Link…" : "Copy Link";
      dlg.showModal();
    }, true);
    send.addEventListener("click", () => {
      if (navigator.share) return navigator.share({ title: "Shiftvert", url: SITE }).catch(() => {});
      const done = () => { send.textContent = "Link Copied"; getSelection().removeAllRanges(); };
      // Some in-app browsers allow no copying at all: leave the link selected and say how.
      const fallback = () => {
        getSelection().selectAllChildren($("#moUrl"));
        if (document.execCommand("copy")) done(); else send.textContent = "Press and hold the link to copy";
      };
      if (navigator.clipboard) navigator.clipboard.writeText(SITE).then(done, fallback); else fallback();
    });
    $("#moClose").addEventListener("click", () => dlg.close());
    dlg.addEventListener("click", e => { if (e.target === dlg) dlg.close(); });
  } else {
    // Macs: the download starts as usual, then a short sheet says what to do with it.
    const ad = $("#afterDl");
    document.addEventListener("click", e => {
      if (!e.target.closest("[data-download]") || !ad.showModal || ad.open) return;
      setTimeout(() => ad.showModal(), 400);
    });
    $("#adClose").addEventListener("click", () => ad.close());
    $("#adMore").addEventListener("click", () => {
      ad.close();
      document.dispatchEvent(new CustomEvent("installstep", { detail: 1 }));  // the installer's "Move to Applications"
    });
    ad.addEventListener("click", e => { if (e.target === ad) ad.close(); });
  }
})();
