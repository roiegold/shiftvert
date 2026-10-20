document.documentElement.classList.add("js");
try {
  const t = sessionStorage.getItem("shiftvert-theme");
  if (t === "light" || t === "dark") document.documentElement.dataset.theme = t;
} catch (e) {}
