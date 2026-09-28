const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const bridge = fs.readFileSync(process.argv[2], 'utf8');

function app() {
    const sent = [];
    const events = {};
    const context = vm.createContext({
        console, Uint8Array,
        webxdc: {},
        webkit: { messageHandlers: { webxdc: {
            postMessage(json) { sent.push(JSON.parse(json)); }
        } } },
        addEventListener(name, callback) { events[name] = callback; }
    });
    context.window = context;
    vm.runInContext(bridge, context);
    return { context, sent, events, join: context.webxdc.joinRealtimeChannel };
}

const alice = app();
const bob = app();
const a = alice.join();
const b = bob.join();
assert.throws(() => alice.join(), /already joined/);
assert.throws(() => a.setListener(null), /Expected a listener/);
assert.throws(() => a.send([1, 2]), /Uint8Array/);
assert.throws(() => a.send(new Uint8Array(128001)), /128000/);
let aliceData, bobData;
a.setListener(data => { aliceData = data; });
b.setListener(() => { throw new Error('Replaced listener was called'); });
b.setListener(data => { bobData = data; });

// The same bytes make a round trip between isolated JS app contexts through
// the native bridge's JSON representation, including NUL and non-UTF-8 bytes.
const bytes = Uint8Array.from({ length: 256 }, (_, i) => i);
a.send(bytes);
assert.equal(alice.sent[1].type, 'realtime-send');
assert.deepEqual(alice.sent[1].data, Array.from(bytes));
bob.context.__webxdc_realtime_receive(bob.sent[0].channel, alice.sent[1].data);
assert.deepEqual(bobData, bytes);
b.send(bobData.subarray(128));
alice.context.__webxdc_realtime_receive(alice.sent[0].channel, bob.sent[1].data);
assert.deepEqual(aliceData, bytes.subarray(128));
a.send(new Uint8Array(128000));
assert.equal(alice.sent.at(-1).data.length, 128000);
a.send(new Uint8Array());
assert.deepEqual(alice.sent.at(-1).data, []);

const oldId = alice.sent[0].channel;
a.leave();
const afterLeave = alice.sent.length;
a.leave();
assert.equal(alice.sent.length, afterLeave);
assert.throws(() => a.send(bytes), /has been left/);
assert.throws(() => a.setListener(() => {}), /has been left/);
const again = alice.join();
assert.notEqual(alice.sent.at(-1).channel, oldId);
let received = false;
again.setListener(() => { received = true; });
alice.context.__webxdc_realtime_receive(oldId, [1]);
alice.context.__webxdc_realtime_closed(oldId, 'Stale failure');
assert.equal(received, false);
again.send(bytes);
alice.events.pagehide();
assert.equal(alice.sent.at(-1).type, 'realtime-leave');
assert.throws(() => again.send(bytes), /has been left/);
console.log('Webxdc realtime JS contract and two-peer binary exchange: PASS');
