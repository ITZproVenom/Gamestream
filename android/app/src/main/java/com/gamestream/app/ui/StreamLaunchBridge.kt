package com.gamestream.app.ui

import android.webkit.WebView

/**
 * The script that starts a stream.
 *
 * Xbox's cloud gaming does not start by itself. The launch page settles on
 * the product page, and the only way into the game from there is the
 * "Play with cloud" button - which the site renders in whatever wording it
 * likes. After that, Xbox asks for a controller before it will allocate a
 * session, and that question has to be answered with "Connect later" or the
 * session never starts.
 *
 * The iOS app does both of these, and this is the same thing for Android.
 */
internal object StreamLaunchBridge {

    fun install(view: WebView?) {
        view?.evaluateJavascript(SCRIPT, null)
    }

    private val SCRIPT = """
(function(){
  if (window.__gsLaunchBridge) return;
  window.__gsLaunchBridge = true;

  // The button that starts the stream. On a product page the plain word
  // "Play" belongs to the store - it buys the game - so only the cloud
  // wording is accepted there.
  var CLOUD = ["play with cloud", "play with cloud (with ads)", "play with cloud (no ads)", "stream with ads", "start streaming", "play for free"];
  var PLAY = ["play", "play now", "play with ads", "resume", "continue playing"];
  // The controller question, and the fullscreen prompt that sits over the
  // game once it has started.
  var GATE = ["connect later", "play without controller", "continue without controller", "play without a controller", "not now", "skip"];
  var DISMISS = ["continue anyway", "remind me later"];

  var pressedAt = 0;
  var gateAt = 0;
  var dismissAt = 0;

  function label(node){
    return ((node.innerText || node.textContent || node.getAttribute('aria-label') || '') + '').trim().toLowerCase();
  }
  function visible(node){
    var box = node.getBoundingClientRect();
    return box.width > 0 && box.height > 0;
  }
  function report(message){
    try {
      if (window.GameStreamBridge && window.GameStreamBridge.onLog) window.GameStreamBridge.onLog(message);
    } catch (e) {}
  }
  function matches(text, list){
    for (var i = 0; i < list.length; i++) {
      if (text === list[i]) return true;
      // "Play with cloud (with ads)" and "Play with cloud" both start with
      // the same words, so a prefix is accepted for the longer ones.
      if (list[i].length > 8 && text.indexOf(list[i]) === 0) return true;
    }
    return false;
  }
  function dialogText(){
    var dialogs = document.querySelectorAll('[role="dialog"],[class*="ErrorScreen"],[class*="error-screen"]');
    var text = '';
    for (var i = 0; i < dialogs.length; i++) {
      var body = (dialogs[i].innerText || '');
      if (body) text += ' ' + body.toLowerCase();
    }
    return text;
  }
  function playing(){
    var videos = document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      if (!videos[i].paused && videos[i].readyState >= 3) return true;
    }
    return false;
  }

  function tick(){
    try {
      var href = (location.href || '').toLowerCase();
      var onProduct = href.indexOf('/products/') !== -1 || href.indexOf('/play/games') !== -1;
      var onLaunch = href.indexOf('/play/launch') !== -1 || href.indexOf('/stream/') !== -1;
      if (!onProduct && !onLaunch) return;
      if (playing()) return;

      var now = Date.now();
      var nodes = document.querySelectorAll('button,[role="button"]');
      if (!nodes.length) return;

      // 1. The controller question comes first: while it is up the page is
      // waiting for an answer and not for another press.
      if (now - gateAt > 4000) {
        for (var g = 0; g < nodes.length; g++) {
          var gateLabel = label(nodes[g]);
          if (!gateLabel || !visible(nodes[g])) continue;
          if (!matches(gateLabel, GATE)) continue;
          nodes[g].click();
          gateAt = now;
          report('answered the controller gate with "' + gateLabel + '"');
          return;
        }
      }

      // 2. The fullscreen prompt, which sits over the game once it starts.
      if (now - dismissAt > 4000) {
        var dialogs = dialogText();
        if (dialogs.indexOf('fullscreen') !== -1) {
          for (var d = 0; d < nodes.length; d++) {
            var dismissLabel = label(nodes[d]);
            if (!matches(dismissLabel, DISMISS)) continue;
            nodes[d].click();
            dismissAt = now;
            report('answered the fullscreen prompt');
            return;
          }
        }
      }

      // 3. The button that starts the stream.
      if (now - pressedAt < 5000) return;
      for (var p = 0; p < nodes.length; p++) {
        var text = label(nodes[p]);
        if (!text || !visible(nodes[p])) continue;
        var hit = onProduct ? matches(text, CLOUD) : matches(text, PLAY) || matches(text, CLOUD);
        if (!hit) continue;
        nodes[p].click();
        pressedAt = now;
        report('pressed "' + text + '"');
        return;
      }
    } catch (e) {}
  }

  setInterval(tick, 750);
  tick();
})();
""".trimIndent()
}
