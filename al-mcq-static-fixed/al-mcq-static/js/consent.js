/*
 * Cookie / ads consent + deferred third-party loading.  Classic script (no import needed):
 *   <script src="js/consent.js" defer></script>
 *
 *  - Google AdSense (which sets cookies) is only loaded after the visitor clicks "Accept".
 *  - Vercel Web Analytics is cookie-free, so it loads for everyone (turn it on in Vercel → Analytics;
 *    set ANALYTICS: false in config.js to disable).
 *  - Not used on exam.html — nothing should interrupt a timed paper.
 *  - window.Consent.allowsAds()  → true once accepted
 *  - window.Consent.open()       → re-open the banner (footer "Cookie settings" link)
 */
(function () {
  if (window.Consent) return;
  var KEY = "consent_v1";
  var cfg = window.APP_CONFIG || {};

  function read() {
    try { return JSON.parse(localStorage.getItem(KEY) || "null"); } catch (e) { return null; }
  }
  function write(ads) {
    try { localStorage.setItem(KEY, JSON.stringify({ ads: !!ads, at: Date.now() })); } catch (e) {}
  }

  var adsLoaded = false;
  function loadAds() {
    if (adsLoaded || !cfg.ADSENSE_CLIENT) return;
    adsLoaded = true;
    var s = document.createElement("script");
    s.async = true;
    s.crossOrigin = "anonymous";
    s.src = "https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=" + encodeURIComponent(cfg.ADSENSE_CLIENT);
    document.head.appendChild(s);
  }

  function loadAnalytics() {
    if (cfg.ANALYTICS === false || window.__vaLoaded) return;
    window.__vaLoaded = true;
    window.va = window.va || function () { (window.vaq = window.vaq || []).push(arguments); };
    var s = document.createElement("script");
    s.defer = true;
    s.src = "/_vercel/insights/script.js";
    document.head.appendChild(s);
  }

  var banner = null;
  function close() { if (banner) { banner.remove(); banner = null; } }

  function open() {
    if (banner) return;
    banner = document.createElement("div");
    banner.className = "cc";
    banner.setAttribute("role", "dialog");
    banner.setAttribute("aria-label", "Cookie preferences");
    banner.innerHTML =
      '<h2>Cookies &amp; ads</h2>' +
      '<p>We show Google ads, which use cookies to pick relevant ads. We also remember your theme and sign-in on this device. ' +
      'Change your choice any time from “Cookie settings” in the footer. See our <a class="link" href="privacy.html">Privacy Policy</a>.</p>' +
      '<div class="cc-actions">' +
      '<button type="button" class="pill pill-brand" data-cc="yes">Accept</button>' +
      '<button type="button" class="pill pill-soft" data-cc="no">Essential only</button>' +
      '</div>';
    document.body.appendChild(banner);
    banner.addEventListener("click", function (e) {
      var b = e.target.closest && e.target.closest("[data-cc]");
      if (!b) return;
      var yes = b.getAttribute("data-cc") === "yes";
      write(yes);
      if (yes) loadAds();
      close();
      try { window.dispatchEvent(new CustomEvent("consent-change", { detail: { ads: yes } })); } catch (err) {}
      if (!yes && adsLoaded) location.reload();      // already-loaded ad scripts can't be unloaded
    });
  }

  window.Consent = {
    allowsAds: function () { var c = read(); return !!(c && c.ads); },
    open: open,
  };

  function init() {
    var isExam = /\/exam\.html$/.test(location.pathname);
    if (isExam) return;                                // no banner, no third parties during a paper
    loadAnalytics();
    var c = read();
    if (c && c.ads) loadAds();
    if (!c) open();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init); else init();
})();
