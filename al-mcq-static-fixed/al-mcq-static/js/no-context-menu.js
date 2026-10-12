/* Disables the right-click / long-press menu on public and student pages.
 * Text fields keep it so people can still paste. Admin pages are excluded.
 * Note: this is a deterrent only — it can't stop view-source or dev tools. */
(function () {
  document.addEventListener("contextmenu", function (e) {
    if (e.target.closest && e.target.closest("input,textarea,select,[contenteditable='true']")) return;
    e.preventDefault();
  });
  document.addEventListener("dragstart", function (e) {
    if (e.target.tagName === "IMG") e.preventDefault();
  });
})();
