// SheServed share-link landing page.
// Caddy rewrites /emergency/* and /sport-club/* (share-link namespaces) here so
// chat recipients get a real page instead of the bare Flutter shell.
// - "เปิดในแอป"      → sheserved:// custom scheme (user gesture; works on iOS
//                     debug builds that cannot sign Associated Domains)
// - "เปิดในเว็บ"      → /?go=<route> — SPA loads, app_links hands the URL to
//                     _handleIncomingUri which unwraps `go` and routes in-app
(function () {
  'use strict';

  var KNOWN_PREFIXES = ['/emergency/incident/', '/sport-club/group/'];
  var path = window.location.pathname;
  var search = window.location.search;

  var card = document.getElementById('card');
  var ref = document.getElementById('ref');
  var subtitle = document.getElementById('subtitle');
  var openApp = document.getElementById('openApp');
  var openWeb = document.getElementById('openWeb');
  var status = document.getElementById('status');

  var matched = KNOWN_PREFIXES.some(function (prefix) {
    return path.indexOf(prefix) === 0 && path.length > prefix.length;
  });
  if (!matched) {
    card.classList.add('invalid');
    return;
  }

  // sheserved:/ + '/emergency/...' = 'sheserved://emergency/...' (canonical)
  var appUrl = 'sheserved:/' + path + search;
  var webUrl = '/?go=' + encodeURIComponent(path + search);

  openApp.href = appUrl;
  openWeb.href = webUrl;

  if (path.indexOf('/emergency/') === 0) {
    subtitle.textContent = 'มีคนแชร์เหตุการณ์ฉุกเฉินถึงคุณจากแอป SheServed';
  } else if (path.indexOf('/sport-club/') === 0) {
    subtitle.textContent = 'มีคนเชิญคุณเข้าก๊วนกีฬาบน SheServed';
  }
  ref.textContent = path.split('/').filter(Boolean).pop();

  // Auto-attempt the app open on mobile devices. If the app is not installed
  // (or the scheme is blocked, e.g. LINE in-app browser) nothing happens and
  // the buttons below remain as the fallback.
  var isMobile = /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
  if (!isMobile) return;

  status.textContent = 'กำลังพยายามเปิดในแอป…';
  setTimeout(function () {
    if (document.hidden) return;
    window.location.assign(appUrl);
    setTimeout(function () {
      if (!document.hidden) {
        status.textContent =
          'เปิดแอปไม่สำเร็จ — แตะ "เปิดในแอป" อีกครั้ง หรือดูผ่านเว็บ';
      }
    }, 1800);
  }, 700);
})();
