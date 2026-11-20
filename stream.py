#!/usr/bin/env python3
# Yahoo's price stream for the listings on screen, read with Python's
# standard library alone. Stonks runs it under Commands.priceStream and
# writes a line to its input whenever what it wants changes: the seconds
# between reports, then the symbols, as "1 AAPL,MSFT". Every report prints,
# for each symbol traded since the last, its newest trade, as
# "SYMBOL TIME PRICE SESSION": TIME in seconds, PRICE as Yahoo sent it (a
# 32-bit float), SESSION Yahoo's market-hours code. A line "! WHY" says why
# it ends. A frame every 10 s keeps the connection open: Yahoo closes one
# whose client sends nothing after a minute or so.
#
# With --frames it reads Yahoo's messages one a line from its input instead
# of the network, and reports them all at the end: how a test feeds it
# saved messages.
import base64, os, re, select, socket, ssl, struct, sys, time

HOST = "streamer.finance.yahoo.com"
KEEP_ALIVE = 10
# Well over any frame Yahoo sends (300 bytes), and any line Stonks writes
# (100 symbols).
MOST_FRAME = 65536
MOST_LINE = 4096
SYMBOL = re.compile(r"^[A-Z0-9.^=-]{1,32}$")


def varint(b, p):
    r = s = 0
    while True:
        x = b[p]
        p += 1
        r |= (x & 0x7F) << s
        s += 7
        if not x & 0x80:
            return r, p


# Yahoo's PricingData: 1 the symbol, 2 the price (float), 3 the time in
# milliseconds (zigzag), 7 the market hours.
def decode(b):
    out, p = {}, 0
    while p < len(b):
        key, p = varint(b, p)
        field, wire = key >> 3, key & 7
        if wire == 0:
            v, p = varint(b, p)
        elif wire == 5:
            v = struct.unpack_from("<f", b, p)[0]
            p += 4
        elif wire == 1:
            v = struct.unpack_from("<d", b, p)[0]
            p += 8
        elif wire == 2:
            n, p = varint(b, p)
            v = b[p:p + n]
            p += n
        else:
            break
        out[field] = v
    return out


# A message's trade, or None for one that can't be read.
def trade(text):
    try:
        at = text.index('"message":"') + 11
        msg = decode(base64.b64decode(text[at:text.index('"', at)], validate=True))
        symbol = msg[1].decode("ascii")
        t = msg[3]
        t = ((t >> 1) ^ -(t & 1)) // 1000
        price = msg[2]
        hours = msg.get(7, 0)
    except (ValueError, KeyError, IndexError, UnicodeDecodeError, AttributeError, TypeError, struct.error):
        return None
    if not SYMBOL.match(symbol) or not isinstance(price, float) or not price > 0 or price == float("inf") or t <= 0:
        return None
    return symbol, t, price, hours


def report(newest, out):
    for symbol, (t, price, hours) in newest.items():
        out.write("%s %d %r %d\n" % (symbol, t, price, hours))
    newest.clear()
    out.flush()


def heard(newest, text):
    got = trade(text)
    if got and (got[0] not in newest or got[1] >= newest[got[0]][0]):
        newest[got[0]] = got[1:]


def frames():
    newest = {}
    for line in sys.stdin:
        heard(newest, line.strip())
    report(newest, sys.stdout)
    return 0


def send(sock, text):
    data = text.encode()
    n = len(data)
    head = bytes([0x81, 0x80 | n]) if n < 126 else bytes([0x81, 0x80 | 126]) + struct.pack(">H", n)
    mask = os.urandom(4)
    sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))


def connect():
    sock = ssl.create_default_context().wrap_socket(socket.create_connection((HOST, 443), timeout=10), server_hostname=HOST)
    key = base64.b64encode(os.urandom(16)).decode()
    sock.sendall(("GET /?version=2 HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nUser-Agent: Mozilla/5.0 (Omarchy Stonks)\r\n\r\n"
                  % (HOST, key)).encode())
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk or len(buf) > MOST_FRAME:
            raise ConnectionError("no answer")
        buf += chunk
    head, rest = buf.split(b"\r\n\r\n", 1)
    status = head.split(b"\r\n", 1)[0].split(b" ")
    code = status[1] if len(status) > 1 else b""
    if code in (b"429", b"503"):
        return None, b"refused"
    if code != b"101":
        raise ConnectionError("answered " + code.decode(errors="replace"))
    sock.settimeout(None)
    return sock, rest


def stream():
    try:
        sock, buf = connect()
    except (OSError, ConnectionError) as e:
        print("! none %s" % e, flush=True)
        return 1
    if sock is None:
        print("! refused", flush=True)
        return 2
    out = sys.stdout
    pace, wanted, newest = 1, set(), {}
    sent = reported = time.monotonic()
    pending = b""
    while True:
        wait = max(0.0, min(sent + KEEP_ALIVE, reported + pace) - time.monotonic())
        ready = select.select([sock, sys.stdin.buffer], [], [], wait)[0]
        if sys.stdin.buffer in ready:
            got = os.read(sys.stdin.fileno(), MOST_LINE)
            if not got:
                return 0
            pending += got
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                parts = line.decode("ascii", "replace").split(" ")
                if len(parts) != 2 or not parts[0].isdigit():
                    continue
                pace = max(1, int(parts[0]))
                symbols = {s for s in parts[1].split(",") if SYMBOL.match(s)}
                if symbols - wanted:
                    send(sock, '{"subscribe":[%s]}' % ",".join('"%s"' % s for s in sorted(symbols - wanted)))
                if wanted - symbols:
                    send(sock, '{"unsubscribe":[%s]}' % ",".join('"%s"' % s for s in sorted(wanted - symbols)))
                for gone in wanted - symbols:
                    newest.pop(gone, None)
                wanted = symbols
                sent = time.monotonic()
            if len(pending) > MOST_LINE:
                pending = b""
        if sock in ready or sock.pending():
            chunk = sock.recv(MOST_FRAME)
            if not chunk:
                print("! closed", flush=True)
                return 4
            buf += chunk
            while len(buf) >= 2:
                op, n, p = buf[0] & 0x0F, buf[1] & 0x7F, 2
                if n == 126:
                    if len(buf) < 4:
                        break
                    n, p = struct.unpack(">H", buf[2:4])[0], 4
                elif n == 127:
                    print("! frame too long", flush=True)
                    return 5
                if len(buf) < p + n:
                    break
                payload, buf = buf[p:p + n], buf[p + n:]
                if op == 8:
                    print("! closed", flush=True)
                    return 4
                if op == 9:
                    sock.sendall(bytes([0x8A, 0x80 | min(len(payload), 125)]) + b"\0\0\0\0" + payload[:125])
                elif op == 1:
                    heard(newest, payload.decode("ascii", "replace"))
            if len(buf) > MOST_FRAME:
                print("! frame too long", flush=True)
                return 5
        now = time.monotonic()
        if now - sent >= KEEP_ALIVE:
            send(sock, '{"subscribe":[]}')
            sent = now
        if now - reported >= pace:
            newest = {s: v for s, v in newest.items() if s in wanted}
            if newest:
                report(newest, out)
            reported = now


if __name__ == "__main__":
    try:
        sys.exit(frames() if sys.argv[1:] == ["--frames"] else stream())
    except (OSError, ssl.SSLError) as e:
        print("! none %s" % e, flush=True)
        sys.exit(1)
