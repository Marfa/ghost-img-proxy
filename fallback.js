/**
 * Ghost CDN image failover: try storage.ghost.io first; on error use img.themarfa.name.
 * Paste into Ghost Admin → Settings → Code injection → Site Footer.
 */
(function () {
  var ORIGIN = "https://storage.ghost.io";
  var PROXY = "https://img.themarfa.name";
  var FLAG = "ghostImgProxy";
  var ATTR = "data-ghost-img-proxy";

  function preferProxy() {
    try {
      return sessionStorage.getItem(FLAG) === "1";
    } catch (e) {
      return false;
    }
  }

  function markPreferProxy() {
    try {
      sessionStorage.setItem(FLAG, "1");
    } catch (e) {
      /* ignore */
    }
  }

  function toProxy(url) {
    if (!url || url.indexOf(ORIGIN) !== 0) return url;
    return PROXY + url.slice(ORIGIN.length);
  }

  function rewriteSrcset(srcset) {
    if (!srcset) return srcset;
    return srcset
      .split(",")
      .map(function (part) {
        var bits = part.trim().split(/\s+/);
        if (!bits.length) return part;
        bits[0] = toProxy(bits[0]);
        return bits.join(" ");
      })
      .join(", ");
  }

  function applyProxyToImg(img) {
    if (!img || img.getAttribute(ATTR) === "1") return;
    var src = img.getAttribute("src") || "";
    var srcset = img.getAttribute("srcset") || "";
    var current = img.currentSrc || src;
    if (
      current.indexOf(ORIGIN) !== 0 &&
      src.indexOf(ORIGIN) !== 0 &&
      srcset.indexOf(ORIGIN) === -1
    ) {
      return;
    }
    img.setAttribute(ATTR, "1");
    if (src.indexOf(ORIGIN) === 0) img.setAttribute("src", toProxy(src));
    if (srcset.indexOf(ORIGIN) !== -1) {
      img.setAttribute("srcset", rewriteSrcset(srcset));
    }
  }

  function applyProxyToSource(el) {
    if (!el || el.getAttribute(ATTR) === "1") return;
    var srcset = el.getAttribute("srcset") || "";
    if (srcset.indexOf(ORIGIN) === -1) return;
    el.setAttribute(ATTR, "1");
    el.setAttribute("srcset", rewriteSrcset(srcset));
  }

  function rewriteAll() {
    var imgs = document.querySelectorAll("img");
    for (var i = 0; i < imgs.length; i++) applyProxyToImg(imgs[i]);
    var sources = document.querySelectorAll("source[srcset]");
    for (var j = 0; j < sources.length; j++) applyProxyToSource(sources[j]);
  }

  function onError(ev) {
    var t = ev.target;
    if (!t || t.tagName !== "IMG") return;
    var probe = t.currentSrc || t.getAttribute("src") || "";
    if (probe.indexOf(ORIGIN) !== 0) return;
    markPreferProxy();
    applyProxyToImg(t);
    rewriteAll();
  }

  document.addEventListener("error", onError, true);

  if (preferProxy()) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", rewriteAll);
    } else {
      rewriteAll();
    }
  }

  // Late-loaded images (infinite scroll / portals)
  if (typeof MutationObserver !== "undefined") {
    var obs = new MutationObserver(function (mutations) {
      if (!preferProxy()) return;
      for (var i = 0; i < mutations.length; i++) {
        var nodes = mutations[i].addedNodes;
        for (var j = 0; j < nodes.length; j++) {
          var n = nodes[j];
          if (n.nodeType !== 1) continue;
          if (n.tagName === "IMG") applyProxyToImg(n);
          if (n.tagName === "SOURCE") applyProxyToSource(n);
          if (n.querySelectorAll) {
            var imgs = n.querySelectorAll("img");
            for (var k = 0; k < imgs.length; k++) applyProxyToImg(imgs[k]);
            var sources = n.querySelectorAll("source[srcset]");
            for (var m = 0; m < sources.length; m++) applyProxyToSource(sources[m]);
          }
        }
      }
    });
    obs.observe(document.documentElement, { childList: true, subtree: true });
  }
})();
