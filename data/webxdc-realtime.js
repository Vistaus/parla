/* Shared by WebKitGTK, WKWebView and WebView2. No direct browser networking. */
(function () {
    'use strict';
    const handler = window.webkit.messageHandlers.webxdc;
    const documentId = Date.now() + ':' + Math.random() + ':';
    let sequence = 0;
    let current = null;
    function post(type, channel, data) {
        handler.postMessage(JSON.stringify({ type, channel, data }));
    }
    window.__webxdc_realtime_receive = function (id, data) {
        if (current && current.id === id && !current.left && current.listener)
            current.listener(new Uint8Array(data));
    };
    window.__webxdc_realtime_closed = function (id, message) {
        if (current && current.id === id) {
            current.left = true;
            current.listener = null;
            console.warn('Webxdc realtime: ' + message);
        }
    };
    window.webxdc.joinRealtimeChannel = function () {
        if (current && !current.left)
            throw new Error('A realtime channel is already joined');
        const state = { id: documentId + (++sequence), left: false, listener: null };
        current = state;
        function checkOpen() {
            if (state.left) throw new Error('This realtime channel has been left');
        }
        const channel = {
            setListener(callback) {
                checkOpen();
                if (typeof callback !== 'function') throw new TypeError('Expected a listener');
                state.listener = callback;
            },
            send(data) {
                checkOpen();
                if (!(data instanceof Uint8Array)) throw new TypeError('Expected Uint8Array');
                if (data.length > 128000) throw new RangeError('Realtime data exceeds 128000 bytes');
                post('realtime-send', state.id, Array.from(data));
            },
            leave() {
                if (state.left) return;
                state.left = true;
                state.listener = null;
                post('realtime-leave', state.id);
            }
        };
        state.channel = channel;
        post('realtime-join', state.id);
        return channel;
    };
    window.addEventListener('pagehide', function () {
        if (current) current.channel.leave();
    });
})();
