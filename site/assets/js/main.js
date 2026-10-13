/* BULBVPN site — interactive layer */

(function () {
  "use strict";

  /* ------------------------------------------------------------------ *
   * Download links. Set each store URL once the app is published; buttons
   * render as disabled "Coming soon" while null.
   * ------------------------------------------------------------------ */
  var DOWNLOADS = {
    android: null
  };

  var SERVERS_API =
    "https://raw.githubusercontent.com/alihusains/apigate/main/response.json";

  var FALLBACK_SERVERS = [
    { host: "vpn430861125", cc: "HR", country: "Croatia", ping: "1", sessions: "41" },
    { host: "vpn155661302", cc: "JP", country: "Japan", ping: "2", sessions: "27" },
    { host: "vpn258922262", cc: "TH", country: "Thailand", ping: "4", sessions: "104" },
    { host: "vpn451190753", cc: "US", country: "United States", ping: "7", sessions: "0" },
    { host: "vpn860205220", cc: "LV", country: "Latvia", ping: "7", sessions: "6" },
    { host: "vpn421416087", cc: "CA", country: "Canada", ping: "23", sessions: "284" }
  ];

  function cleanCountry(raw) {
    if (!raw) return "";
    return String(raw).split(" (LOCAL")[0].trim();
  }

  function toNum(v) {
    var n = parseInt(v, 10);
    return isNaN(n) ? 9999 : n;
  }

  function renderServers(list) {
    var rows = document.querySelectorAll("[data-server-rows]");
    if (!rows.length) return;

    var sorted = list.slice().sort(function (a, b) {
      return toNum(a.ping) - toNum(b.ping);
    });

    var shown = sorted.slice(0, 8);

    rows.forEach(function (tbody) {
      var html = "";
      shown.forEach(function (s) {
        var name = s.host || s.ip || "node";
        var cc = (s.cc || s.countryShort || "??").toUpperCase();
        var country = s.country || cleanCountry(s.countryLong) || cc;
        var ping = s.ping === "-" ? "—" : s.ping;
        html +=
          '<div class="server-row" role="row">' +
          '<img src="assets/flags/' + cc.toLowerCase() + '.svg" alt="" loading="lazy" ' +
          'onerror="this.style.visibility=\'hidden\'">' +
          '<span class="name">' + name + "</span>" +
          '<span class="cc">' + cc + " · " + country + "</span>" +
          '<span class="num ping">' + ping + " ms</span>" +
          '<span class="num sessions">' + (s.sessions || s.numSessions || "—") + "</span>" +
          "</div>";
      });
      tbody.innerHTML = html;
    });

    document.querySelectorAll("[data-server-count]").forEach(function (el) {
      el.textContent = String(list.length);
    });
  }

  function loadServers() {
    var cached = null;
    try {
      cached = JSON.parse(localStorage.getItem("bulb_servers") || "null");
    } catch (e) {}

    if (cached && Array.isArray(cached.list) && cached.list.length) {
      if (Date.now() - cached.at < 6 * 60 * 60 * 1000) {
        renderServers(cached.list);
      }
    }

    var ctrl = typeof AbortController !== "undefined" ? new AbortController() : null;
    var timer = setTimeout(function () {
      if (ctrl) ctrl.abort();
    }, 8000);

    fetch(SERVERS_API, ctrl ? { signal: ctrl.signal } : {})
      .then(function (r) {
        if (!r.ok) throw new Error("http " + r.status);
        return r.json();
      })
      .then(function (data) {
        clearTimeout(timer);
        if (!Array.isArray(data) || !data.length) throw new Error("bad shape");
        var list = data.map(function (s) {
          return {
            host: s["#HostName"],
            ip: s.IP,
            cc: s.CountryShort,
            countryLong: s.CountryLong,
            ping: s.Ping,
            sessions: s.NumVpnSessions
          };
        });
        renderServers(list);
        try {
          localStorage.setItem(
            "bulb_servers",
            JSON.stringify({ at: Date.now(), list: list })
          );
        } catch (e) {}
      })
      .catch(function () {
        clearTimeout(timer);
        if (!document.querySelector("[data-server-rows] .server-row")) {
          renderServers(FALLBACK_SERVERS);
        }
      });
  }

  function renderDownloads() {
    document.querySelectorAll("[data-download]").forEach(function (el) {
      var key = el.getAttribute("data-download");
      var url = DOWNLOADS[key];
      if (url) {
        el.outerHTML =
          '<a class="btn btn-primary" href="' + url + '" rel="noopener">Download APK</a>';
      } else {
        el.outerHTML =
          '<span class="btn btn-disabled" role="button" aria-disabled="true" ' +
          'title="No signed build published yet">Coming soon</span>';
      }
    });
  }

  function setupReveal() {
    var els = document.querySelectorAll(".reveal");
    if (!els.length) return;

    if (
      !("IntersectionObserver" in window) ||
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      els.forEach(function (el) {
        el.classList.add("in");
      });
      return;
    }

    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            entry.target.classList.add("in");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12, rootMargin: "0px 0px -6% 0px" }
    );

    els.forEach(function (el) {
      io.observe(el);
    });
  }

  function setYear() {
    document.querySelectorAll("[data-year]").forEach(function (el) {
      el.textContent = String(new Date().getFullYear());
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    setYear();
    renderDownloads();
    loadServers();
    setupReveal();
  });
})();
