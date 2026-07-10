// fastcast-ws.mjs — the shared hand-rolled FastCast websocket client + frame
// decode, extracted from capture-fastcast.mjs so the capture tool and the
// long-running protocol monitor (monitor-fastcast.mjs) use ONE implementation.
// Pure Node, no dependencies — hand-rolled because Node's built-in WebSocket
// can't send the Origin/User-Agent headers the server requires on upgrade.
//
// Protocol recap (verified live 2026-07-08; fastcast-plan.md is authoritative):
//   GET websockethost → {ip, securePort, token}; token is short-lived.
//   wss://{ip}:{securePort}/FastcastService/pubsub/profiles/12000?TrafficManager-Token={token}
//     (token raw/unencoded; needs Origin: https://www.espn.com + browser UA).
//   {"op":"C"} → {"rc":200,"sid":...}; {"op":"S","sid","tc":topic} per topic.
//   Per topic: op "H" carries the checkpoint URL; op "P"/"R" carry deltas whose
//   pl is a JSON string {ts,"~c",pl} — "~c":1 → base64 + zlib-deflate, then an
//   RFC 6902 patch array. Server pings; we answer pongs.

import { connect as tlsConnect } from 'node:tls';
import { get as httpsGet } from 'node:https';
import { randomBytes, createHash } from 'node:crypto';
import { inflateSync, inflateRawSync, gunzipSync } from 'node:zlib';

export const HOST_URL = 'https://fastcast.semfs.engsvc.go.com/public/websockethost';
export const ORIGIN = 'https://www.espn.com';
export const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

// ---- minimal https JSON GET ---------------------------------------------------
export function getJson(url) {
  return new Promise((res, rej) => {
    httpsGet(url, { headers: { 'User-Agent': UA, Origin: ORIGIN, 'Accept-Encoding': 'gzip' } }, (r) => {
      if (r.statusCode !== 200) { r.resume(); return rej(new Error(`GET ${url} -> ${r.statusCode}`)); }
      const chunks = [];
      r.on('data', (c) => chunks.push(c));
      r.on('end', () => {
        try {
          let buf = Buffer.concat(chunks);
          if (r.headers['content-encoding'] === 'gzip') buf = gunzipSync(buf);
          res(JSON.parse(buf.toString('utf8')));
        } catch (e) { rej(e); }
      });
      r.on('error', rej);
    }).on('error', rej);
  });
}

// ---- hand-rolled ws client ----------------------------------------------------
// Client→server frames MUST be masked; server→client frames arrive unmasked.
function encodeFrame(opcode, payload) {
  const len = payload.length;
  let header;
  if (len < 126) header = Buffer.from([0x80 | opcode, 0x80 | len]);
  else if (len < 65536) { header = Buffer.alloc(4); header[0] = 0x80 | opcode; header[1] = 0x80 | 126; header.writeUInt16BE(len, 2); }
  else { header = Buffer.alloc(10); header[0] = 0x80 | opcode; header[1] = 0x80 | 127; header.writeBigUInt64BE(BigInt(len), 2); }
  const mask = randomBytes(4);
  const masked = Buffer.from(payload);
  for (let i = 0; i < masked.length; i++) masked[i] ^= mask[i & 3];
  return Buffer.concat([header, mask, masked]);
}

export class FastcastSocket {
  constructor() {
    this.buf = Buffer.alloc(0);
    this.frags = [];
    // 'message' (parsed JSON), 'close', 'ping' (payload Buffer), 'raw' (non-JSON text)
    this.handlers = { message: [], close: [], ping: [], raw: [] };
    this.sock = null;
    this.sid = null;
    this.bytesIn = 0;
  }

  on(ev, fn) { this.handlers[ev].push(fn); }
  emit(ev, ...args) { for (const fn of this.handlers[ev] ?? []) fn(...args); }

  async connect() {
    const host = await getJson(HOST_URL);
    const { ip, securePort, token } = host;
    const path = `/FastcastService/pubsub/profiles/12000?TrafficManager-Token=${token}`;
    const key = randomBytes(16).toString('base64');
    const expectAccept = createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');

    await new Promise((res, rej) => {
      const sock = tlsConnect({ host: ip, port: securePort, rejectUnauthorized: false }, () => {
        sock.write(
          `GET ${path} HTTP/1.1\r\n` +
          `Host: ${ip}:${securePort}\r\n` +
          'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
          `Sec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n` +
          `Origin: ${ORIGIN}\r\nUser-Agent: ${UA}\r\n\r\n`,
        );
      });
      sock.on('error', rej);
      let head = Buffer.alloc(0);
      const onData = (d) => {
        head = Buffer.concat([head, d]);
        const end = head.indexOf('\r\n\r\n');
        if (end === -1) return;
        sock.off('data', onData);
        const response = head.subarray(0, end).toString('latin1');
        if (!/^HTTP\/1\.1 101/.test(response)) return rej(new Error(`upgrade rejected: ${response.split('\r\n')[0]}`));
        if (!response.includes(expectAccept)) return rej(new Error('bad Sec-WebSocket-Accept'));
        this.sock = sock;
        this.buf = head.subarray(end + 4);
        sock.on('data', (c) => { this.bytesIn += c.length; this.buf = Buffer.concat([this.buf, c]); this.drain(); });
        sock.on('close', () => this.emit('close'));
        sock.on('error', () => {/* surfaced via close */});
        res();
      };
      sock.on('data', onData);
    });

    // handshake: {"op":"C"} → sid
    this.sid = await new Promise((res, rej) => {
      const t = setTimeout(() => rej(new Error('no C ack')), 10000);
      const h = (msg) => {
        if (msg.op === 'C' && msg.sid) { clearTimeout(t); this.handlers.message = this.handlers.message.filter((f) => f !== h); res(msg.sid); }
      };
      this.on('message', h);
      this.sendJson({ op: 'C' });
    });
    if (this.buf.length) this.drain();
    return this;
  }

  drain() {
    for (;;) {
      if (this.buf.length < 2) return;
      const fin = (this.buf[0] & 0x80) !== 0;
      const opcode = this.buf[0] & 0x0f;
      let len = this.buf[1] & 0x7f;
      let off = 2;
      if (len === 126) { if (this.buf.length < 4) return; len = this.buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (this.buf.length < 10) return; len = Number(this.buf.readBigUInt64BE(2)); off = 10; }
      if (this.buf.length < off + len) return;
      const payload = this.buf.subarray(off, off + len);
      this.buf = this.buf.subarray(off + len);
      if (opcode === 9) { this.emit('ping', payload); this.sock.write(encodeFrame(10, payload)); continue; } // ping → pong
      if (opcode === 10) continue;                                               // pong
      if (opcode === 8) { try { this.sock.end(); } catch { /* closing */ } continue; }
      if (opcode === 1 || opcode === 2 || opcode === 0) {
        this.frags.push(payload);
        if (!fin) continue;
        const text = Buffer.concat(this.frags).toString('utf8');
        this.frags = [];
        try { this.emit('message', JSON.parse(text)); } catch { this.emit('raw', text); }
      }
    }
  }

  sendJson(obj) { this.sock.write(encodeFrame(1, Buffer.from(JSON.stringify(obj)))); }
  subscribe(topic) { this.sendJson({ op: 'S', sid: this.sid, tc: topic }); }
  close() { try { this.sock.destroy(); } catch { /* already gone */ } }
}

// Decode an op:"P"/"R" delta frame's pl → {ts, ops, compressFlag}.
// Throws on undecodable payloads — callers classify.
export function decodeDelta(msg) {
  let inner = msg.pl;
  if (typeof inner === 'string') inner = JSON.parse(inner);
  let pl = inner.pl;
  const compressFlag = inner['~c'];
  if (compressFlag) {
    const raw = Buffer.from(pl, 'base64');
    let out;
    try { out = inflateSync(raw); } catch { out = inflateRawSync(raw); }
    pl = out.toString('utf8');
  }
  return { ts: inner.ts ?? null, ops: typeof pl === 'string' ? JSON.parse(pl) : pl, compressFlag };
}

// ---- topic naming -------------------------------------------------------------
// event-{sport}-{league} using the registry slug verbatim (dots included).
export function eventTopicFor(key) {
  const [sport, league] = key.split('/');
  return `event-${sport}-${league}`;
}
