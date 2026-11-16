// Spike or Stay: small progressive enhancements. The page works without this file:
// cards link to /trend pages and the stat cards are just counts.
(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  // ---------- 1. Stat cards filter the product grid ----------
  let activeFilter = null;

  function applyFilter(key, name) {
    activeFilter = key;
    $$(".stat[data-filter]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.filter === key)));
    let shown = 0;
    $$(".product-card").forEach((card) => {
      const visible = !key || card.dataset.group === key;
      card.hidden = !visible;
      if (visible) shown += 1;
    });
    const status = $(".filter-status");
    if (status) {
      status.hidden = !key;
      if (key) $("[data-filter-name]", status).textContent = name;
    }
    const empty = $(".filter-empty");
    if (empty) empty.hidden = shown > 0;
  }

  // ---------- 2. Clicking a card opens its trend panel in a dialog ----------
  const dialog = $(".trend-dialog");

  async function openTrend(url) {
    if (!dialog || !dialog.showModal) {
      window.location.href = url;
      return;
    }
    const body = $(".dialog-body", dialog);
    body.innerHTML = '<p class="dialog-loading">Loading trend…</p>';
    dialog.showModal();
    body.focus(); // start at the panel, not on the close button
    try {
      const response = await fetch(url, { headers: { "X-Requested-With": "XMLHttpRequest" } });
      if (!response.ok) throw new Error(String(response.status));
      body.innerHTML = await response.text(); // our own server-rendered partial
    } catch (error) {
      body.innerHTML = '<p class="dialog-loading">Couldn’t load this trend. Try again in a moment.</p>';
    }
  }

  // Clicking the dark backdrop (outside the panel) closes the dialog.
  if (dialog) {
    dialog.addEventListener("click", (event) => {
      if (event.target === dialog) dialog.close();
    });
  }

  document.addEventListener("click", (event) => {
    const stat = event.target.closest(".stat[data-filter]");
    if (stat) {
      const key = stat.dataset.filter;
      applyFilter(activeFilter === key ? null : key, $(".stat-label", stat).textContent);
      return;
    }
    if (event.target.closest("[data-filter-clear]")) {
      applyFilter(null);
      return;
    }

    // The card's own "View trend" link, or a click anywhere on the card that isn't a control.
    let link = event.target.closest("a[data-trend]");
    if (!link) {
      const card = event.target.closest(".product-card.is-clickable");
      const onControl = event.target.closest("a, button, input, label, details, summary, form");
      if (card && !onControl) link = $("a[data-trend]", card);
    }
    if (link && !event.metaKey && !event.ctrlKey && !event.shiftKey) {
      event.preventDefault();
      openTrend(link.href);
    }
  });

  // ---------- 3. Chart hover: crosshair, dot and tooltip ----------
  function hideHover(svg) {
    $$(".hover-line, .hover-dot", svg).forEach((el) => el.setAttribute("visibility", "hidden"));
    const tip = svg.parentElement.querySelector(".chart-tooltip");
    if (tip) tip.hidden = true;
  }

  document.addEventListener("pointermove", (event) => {
    const svg = event.target instanceof Element ? event.target.closest(".chart-svg") : null;
    $$(".chart-svg").forEach((other) => { if (other !== svg) hideHover(other); });
    if (!svg) return;

    if (!svg.points) svg.points = JSON.parse(svg.dataset.points); // [x, y, "Week of …", views]
    const box = svg.getBoundingClientRect();
    const viewBox = svg.viewBox.baseVal;
    const x = ((event.clientX - box.left) / box.width) * viewBox.width;
    const point = svg.points.reduce((best, p) => (Math.abs(p[0] - x) < Math.abs(best[0] - x) ? p : best));

    const line = $(".hover-line", svg);
    const dot = $(".hover-dot", svg);
    line.setAttribute("x1", point[0]);
    line.setAttribute("x2", point[0]);
    dot.setAttribute("cx", point[0]);
    dot.setAttribute("cy", point[1]);
    line.setAttribute("visibility", "visible");
    dot.setAttribute("visibility", "visible");

    const tip = svg.parentElement.querySelector(".chart-tooltip");
    const views = document.createElement("strong");
    views.textContent = point[3].toLocaleString() + " views";
    const week = document.createElement("span");
    week.textContent = point[2];
    tip.replaceChildren(views, week);
    tip.hidden = false;
    const left = (point[0] / viewBox.width) * box.width;
    tip.style.left = Math.min(Math.max(left, 70), box.width - 70) + "px";
    tip.style.top = (point[1] / viewBox.height) * box.height + "px";
  });
})();
