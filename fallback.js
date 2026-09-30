/**
 * Ghost CDN image failover: try storage.ghost.io first; on error use img.themarfa.name,
 * then feeds.themarfa.name/gimg if the dedicated host is unreachable.
 * Paste into Ghost Admin → Settings → Code injection → Site Footer.
 */
(function () {
  var ORIGIN = "https://storage.ghost.io";
  var PROXY = "https://img.themarfa.name";
  var PROXY_FALLBACK = "https://feeds.themarfa.name/gimg";
  var FLAG = "ghostImgProxyBase";
  var ATTR = "data-ghost-img-proxy";

  function getActiveProxy() {
    try {
      var v = sessionStorage.getItem(FLAG);
      if (v === PROXY || v === PROXY_FALLBACK) return v;
    } catch (e) {
      /* ignore */
    }
    return null;
  }

  function setActiveProxy(base) {
    try {
      sessionStorage.setItem(FLAG, base);
    } catch (e) {
      /* ignore */
    }
  }

  function stripKnownProxy(url) {
    if (url.indexOf(PROXY_FALLBACK) === 0) return ORIGIN + url.slice(PROXY_FALLBACK.length);
    if (url.indexOf(PROXY) === 0) return ORIGIN + url.slice(PROXY.length);
    return url;
  }

  function toProxy(url, base) {
    if (!url) return url;
    var originUrl = stripKnownProxy(url);
    if (originUrl.indexOf(ORIGIN) !== 0) return url;
    return base + originUrl.slice(ORIGIN.length);
  }

  function rewriteSrcset(srcset, base) {
    if (!srcset) return srcset;
    return srcset
      .split(",")
      .map(function (part) {
        var bits = part.trim().split(/\s+/);
        if (!bits.length) return part;
        bits[0] = toProxy(bits[0], base);
        return bits.join(" ");
      })
      .join(", ");
  }

  function applyProxyToImg(img, base) {
    if (!img) return;
    base = base || getActiveProxy();
    if (!base) return;
    var src = img.getAttribute("src") || "";
    var srcset = img.getAttribute("srcset") || "";
    var current = img.currentSrc || src;
    var involved =
      current.indexOf(ORIGIN) === 0 ||
      src.indexOf(ORIGIN) === 0 ||
      srcset.indexOf(ORIGIN) !== -1 ||
      current.indexOf(PROXY) === 0 ||
      src.indexOf(PROXY) === 0 ||
      current.indexOf(PROXY_FALLBACK) === 0 ||
      src.indexOf(PROXY_FALLBACK) === 0 ||
      srcset.indexOf(PROXY) !== -1 ||
      srcset.indexOf(PROXY_FALLBACK) !== -1;
    if (!involved) return;
    img.setAttribute(ATTR, base);
    if (src) img.setAttribute("src", toProxy(src, base));
    if (srcset) img.setAttribute("srcset", rewriteSrcset(srcset, base));
  }

  function applyProxyToSource(el, base) {
    if (!el) return;
    base = base || getActiveProxy();
    if (!base) return;
    var srcset = el.getAttribute("srcset") || "";
    if (
      srcset.indexOf(ORIGIN) === -1 &&
      srcset.indexOf(PROXY) === -1 &&
      srcset.indexOf(PROXY_FALLBACK) === -1
    ) {
      return;
    }
    el.setAttribute(ATTR, base);
    el.setAttribute("srcset", rewriteSrcset(srcset, base));
  }

  function rewriteAll(base) {
    base = base || getActiveProxy();
    if (!base) return;
    var imgs = document.querySelectorAll("img");
    for (var i = 0; i < imgs.length; i++) applyProxyToImg(imgs[i], base);
    var sources = document.querySelectorAll("source[srcset]");
    for (var j = 0; j < sources.length; j++) applyProxyToSource(sources[j], base);
  }

  function onError(ev) {
    var t = ev.target;
    if (!t || t.tagName !== "IMG") return;
    var probe = t.currentSrc || t.getAttribute("src") || "";

    if (probe.indexOf(ORIGIN) === 0) {
      setActiveProxy(PROXY);
      t.removeAttribute(ATTR);
      applyProxyToImg(t, PROXY);
      rewriteAll(PROXY);
      return;
    }

    if (probe.indexOf(PROXY) === 0 && probe.indexOf(PROXY_FALLBACK) !== 0) {
      setActiveProxy(PROXY_FALLBACK);
      t.removeAttribute(ATTR);
      applyProxyToImg(t, PROXY_FALLBACK);
      rewriteAll(PROXY_FALLBACK);
    }
  }

  document.addEventListener("error", onError, true);

  var existing = getActiveProxy();
  if (existing) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function () {
        rewriteAll(existing);
      });
    } else {
      rewriteAll(existing);
    }
  }

  if (typeof MutationObserver !== "undefined") {
    var obs = new MutationObserver(function (mutations) {
      var base = getActiveProxy();
      if (!base) return;
      for (var i = 0; i < mutations.length; i++) {
        var nodes = mutations[i].addedNodes;
        for (var j = 0; j < nodes.length; j++) {
          var n = nodes[j];
          if (n.nodeType !== 1) continue;
          if (n.tagName === "IMG") applyProxyToImg(n, base);
          if (n.tagName === "SOURCE") applyProxyToSource(n, base);
          if (n.querySelectorAll) {
            var imgs = n.querySelectorAll("img");
            for (var k = 0; k < imgs.length; k++) applyProxyToImg(imgs[k], base);
            var sources = n.querySelectorAll("source[srcset]");
            for (var m = 0; m < sources.length; m++) applyProxyToSource(sources[m], base);
          }
        }
      }
    });
    obs.observe(document.documentElement, { childList: true, subtree: true });
  }
})();
