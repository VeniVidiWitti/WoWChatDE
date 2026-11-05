"""Chat DE Companion - SavedVariables lesen und Inbox.lua schreiben.

Liest die von WoW geschriebenen Dateien mit einem eigenen, kleinen Parser.
Es wird KEIN Lua-Code ausgefuehrt: erlaubt sind nur Tabellen, Zeichenketten,
Zahlen, true/false/nil und Zuweisungen auf oberster Ebene.

Lizenz: GNU General Public License v2 oder spaeter.
"""

from __future__ import annotations

import os
import re
import tempfile

_TOKEN = re.compile(
    rb"""
    (?P<ws>\s+)
  | (?P<comment>--[^\n]*)
  | (?P<string>"(?:\\.|[^"\\])*")
  | (?P<number>-?(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?))
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<punct>[{}\[\]=,;])
    """,
    re.VERBOSE | re.DOTALL,
)

_ESCAPES = {
    ord("n"): b"\n", ord("t"): b"\t", ord("r"): b"\r", ord("a"): b"\a",
    ord("b"): b"\b", ord("f"): b"\f", ord("v"): b"\v",
    ord("\\"): b"\\", ord('"'): b'"', ord("'"): b"'", ord("\n"): b"\n",
}


class ParseError(ValueError):
    pass


def _unescape(raw: bytes) -> str:
    out = bytearray()
    i, n = 0, len(raw)
    while i < n:
        c = raw[i]
        if c != 0x5C:  # Backslash
            out.append(c)
            i += 1
            continue
        i += 1
        if i >= n:
            break
        e = raw[i]
        if 0x30 <= e <= 0x39:  # \ddd (dezimal)
            j = i
            while j < n and j < i + 3 and 0x30 <= raw[j] <= 0x39:
                j += 1
            out.append(int(raw[i:j]) & 0xFF)
            i = j
        else:
            out += _ESCAPES.get(e, bytes([e]))
            i += 1
    return out.decode("utf-8", errors="replace")


def _tokenize(data: bytes):
    pos, n = 0, len(data)
    while pos < n:
        m = _TOKEN.match(data, pos)
        if not m:
            raise ParseError(f"Unbekanntes Zeichen an Position {pos}")
        pos = m.end()
        kind = m.lastgroup
        if kind in ("ws", "comment"):
            continue
        yield kind, m.group(kind)


class _Parser:
    def __init__(self, data: bytes):
        self.tokens = list(_tokenize(data))
        self.i = 0

    def peek(self):
        return self.tokens[self.i] if self.i < len(self.tokens) else (None, None)

    def take(self, kind=None, value=None):
        tok = self.peek()
        if tok[0] is None:
            raise ParseError("Unerwartetes Dateiende")
        if kind and tok[0] != kind:
            raise ParseError(f"Erwartet {kind}, gefunden {tok[1]!r}")
        if value is not None and tok[1] != value:
            raise ParseError(f"Erwartet {value!r}, gefunden {tok[1]!r}")
        self.i += 1
        return tok

    def value(self):
        kind, val = self.peek()
        if kind == "string":
            self.i += 1
            return _unescape(val[1:-1])
        if kind == "number":
            self.i += 1
            s = val.decode()
            if s.lower().startswith(("0x", "-0x")):
                return int(s, 16)
            f = float(s)
            return int(f) if f.is_integer() and "." not in s and "e" not in s.lower() else f
        if kind == "name":
            self.i += 1
            if val == b"true":
                return True
            if val == b"false":
                return False
            if val == b"nil":
                return None
            raise ParseError(f"Unerlaubter Name {val!r}")
        if kind == "punct" and val == b"{":
            return self.table()
        raise ParseError(f"Unerwarteter Wert {val!r}")

    def table(self):
        self.take("punct", b"{")
        result: dict = {}
        array_index = 1
        while True:
            kind, val = self.peek()
            if kind == "punct" and val == b"}":
                self.i += 1
                break
            if kind == "punct" and val == b"[":
                self.i += 1
                key = self.value()
                self.take("punct", b"]")
                self.take("punct", b"=")
                result[key] = self.value()
            elif kind == "name" and self.i + 1 < len(self.tokens) and self.tokens[self.i + 1] == ("punct", b"="):
                key = val.decode()
                self.i += 2
                result[key] = self.value()
            else:
                result[array_index] = self.value()
                array_index += 1
            kind, val = self.peek()
            if kind == "punct" and val in (b",", b";"):
                self.i += 1
        return _as_list_if_array(result)

    def chunk(self):
        out = {}
        while self.peek()[0] is not None:
            kind, name = self.take("name")
            self.take("punct", b"=")
            out[name.decode()] = self.value()
        return out


def _as_list_if_array(d: dict):
    if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
        return [d[k] for k in range(1, len(d) + 1)]
    if not d:
        return {}
    return d


def parse_savedvariables(data: bytes) -> dict:
    """Liest eine SavedVariables-Datei und gibt {Variablenname: Wert} zurueck."""
    return _Parser(data).chunk()


def read_savedvariables(path: str) -> dict:
    with open(path, "rb") as f:
        return parse_savedvariables(f.read())


# ---------------------------------------------------------------------------
# Lua schreiben
# ---------------------------------------------------------------------------

def lua_string(s: str) -> str:
    out = ['"']
    for ch in str(s):
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            continue
        elif ch == "\t":
            out.append("\\t")
        elif o < 32 or o == 127:
            out.append(f"\\{o:03d}")
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def lua_value(v, indent: int = 1) -> str:
    pad = "    " * indent
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return lua_string(v)
    if isinstance(v, (list, tuple)):
        items = [f"{pad}{lua_value(x, indent + 1)}," for x in v]
        return "{\n" + "\n".join(items) + "\n" + "    " * (indent - 1) + "}"
    if isinstance(v, dict):
        items = []
        for k, x in v.items():
            key = f"[{lua_string(k)}]" if isinstance(k, str) else f"[{int(k)}]"
            items.append(f"{pad}{key} = {lua_value(x, indent + 1)},")
        return "{\n" + "\n".join(items) + "\n" + "    " * (indent - 1) + "}"
    raise TypeError(f"Nicht darstellbar: {type(v)}")


INBOX_HEADER = (
    "-- Chat DE - Posteingang fuer Antworten von Claude.\n"
    "-- Geschrieben vom Chat DE Companion. Enthaelt nur Daten, keinen Programmcode.\n"
)


def write_inbox(path: str, inbox: dict) -> None:
    """Schreibt Inbox.lua atomar (erst Temp-Datei, dann ersetzen)."""
    text = INBOX_HEADER + "WoWChatDE_Inbox = " + lua_value(inbox) + "\n"
    folder = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix=".inbox-", suffix=".tmp", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
