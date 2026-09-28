// Site-wide motion: page fade in/out, smooth scrolling, staggered reveal, press/hover feel.
// Include with <script src="js/motion.js"></script> at the end of <body>. Respects reduced-motion.
(function () {
  if (window.__motion) return; window.__motion = true;
  var reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  var doc = document.documentElement;
  var hasSplash = !!document.getElementById("intro");            // login + dashboard run their own intro
  var isExam = /\/exam\.html$/.test(location.pathname);          // keep the exam screen calm and fast

  var css = "\
html{scroll-behavior:smooth;-webkit-tap-highlight-color:transparent}\
@keyframes mo-page{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}\
body.mo-page{animation:mo-page .45s cubic-bezier(.2,.8,.3,1) both}\
body.mo-leave{opacity:0;transform:translateY(-6px);transition:opacity .2s ease,transform .2s ease;pointer-events:none}\
.mo-in{opacity:0;transform:translateY(16px);transition:opacity .55s cubic-bezier(.2,.8,.3,1),transform .55s cubic-bezier(.2,.8,.3,1);transition-delay:var(--mo-d,0s)}\
.mo-in.mo-show{opacity:1;transform:none}\
a.card,button.card{transition:transform .25s cubic-bezier(.2,.8,.3,1),box-shadow .25s ease,opacity .55s ease}\
a.card:hover{transform:translateY(-3px)}\
a.card:active,.pill:active,.option:active,.rail-item:active{transform:scale(.97)}\
.pill,.option,.rail-item,.back-btn,a.card{will-change:auto}\
.pill:hover{transform:translateY(-1px)}\
.bar span{transform-origin:left;animation:mo-grow .9s cubic-bezier(.2,.8,.3,1) .2s both}\
@keyframes mo-grow{from{transform:scaleX(0)}to{transform:none}}\
@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}body.mo-page{animation:none}.mo-in{opacity:1;transform:none;transition:none}.bar span{animation:none}}";
  var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);

  // ---- Page enter / leave ----
  if (!reduce && !hasSplash) document.body.classList.add("mo-page");
  window.addEventListener("pageshow", function (e) { if (e.persisted) document.body.classList.remove("mo-leave"); });
  if (!reduce) document.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("a[href]");
    if (!a || e.defaultPrevented || e.button || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if (a.target && a.target !== "_self" || a.hasAttribute("download")) return;
    var u; try { u = new URL(a.href, location.href); } catch (_) { return; }
    if (u.origin !== location.origin || (u.pathname === location.pathname && u.search === location.search)) return;
    e.preventDefault();
    document.body.classList.add("mo-leave");
    setTimeout(function () { location.href = u.href; }, 190);
  });

  // ---- Reveal (cards, headings, section labels), including content rendered later ----
  if (reduce || hasSplash || isExam) return;
  var SEL = ".card,.section-label,h1,.option-list>*";
  var io = new IntersectionObserver(function (es) {
    es.forEach(function (en) { if (en.isIntersecting) { en.target.classList.add("mo-show"); io.unobserve(en.target); } });
  }, { threshold: .06 });
  var queued = false;
  function scan() {
    queued = false;
    var n = 0;
    document.querySelectorAll(SEL).forEach(function (el) {
      if (el.dataset.mo || el.closest("#topbar,#rail,.rail,#footer,.no-motion") || (el.parentElement && el.parentElement.closest(".mo-in"))) return;
      el.dataset.mo = "1"; el.classList.add("mo-in");
      el.style.setProperty("--mo-d", Math.min(n++, 12) * .05 + "s");
      io.observe(el);
    });
  }
  function schedule() { if (!queued) { queued = true; requestAnimationFrame(scan); } }
  new MutationObserver(schedule).observe(document.body, { childList: true, subtree: true });
  scan();
})();
