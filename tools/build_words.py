# -*- coding: utf-8 -*-
"""
Erzeugt WoWChatDE/Words.lua aus dem Ding-Woerterbuch der TU Chemnitz.

Dies ist der "Quelltext" der Datei Words.lua im Sinne der GPL: mit diesem
Skript laesst sich die Datendatei aus der Originalquelle nachbauen.

Voraussetzungen (Debian/Ubuntu):
    sudo apt-get install trans-de-en
    pip install wordfreq

Aufruf:
    python3 tools/build_words.py > WoWChatDE/Words.lua
    python3 tools/clean_words.py WoWChatDE/Words.lua

Quelle: Ding - German-English Dictionary
        Copyright (C) Frank Richter 1995-2020, GNU GPL v2 oder spaeter
        https://www-user.tu-chemnitz.de/~fri/ding/
"""
import re, sys
from collections import defaultdict
from wordfreq import zipf_frequency

SRC          = "/usr/share/trans/de-en"
ZIPF_CEILING = 5.8      # haeufiger: Rohwoerterbuch greift daneben, siehe unten
TARGET       = 25000

BRACKETS = re.compile(r"\{[^{}]*\}|\[[^\[\]]*\]|\([^()]*\)|/[^/]*/")
WORD_EN  = re.compile(r"^[a-z][a-z'-]{1,19}$")
WORD_DE  = re.compile(r"^[A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß-]{1,24}$")

# Funktionswoerter sind nie eine brauchbare Uebersetzung eines Inhaltsworts
STOP_DE = set("""der die das den dem des ein eine einen einem einer eines und oder
aber mit von zu fuer für auf aus bei nach ueber über unter ist sind war waren hat
haben sein wird werden man sich nicht nur auch noch schon sehr mehr so als wie
wenn dann dass weil ich du er sie es wir ihr mein dein kein doch mal denn""".split())


def clean(s):
    prev = None
    while prev != s:                      # verschachtelte Klammern wiederholt weg
        prev = s
        s = BRACKETS.sub(" ", s)
    s = re.split(r"[(\[{/]", s)[0]        # unpaarige Klammer: davor abschneiden
    s = s.replace("...", " ").replace("…", " ")
    return re.sub(r"\s+", " ", s).strip(" ;,.:-")


def collect():
    """Sammelt alle deutschen Kandidaten je englischem Stichwort."""
    cand = defaultdict(lambda: defaultdict(int))
    for line in open(SRC, encoding="utf-8", errors="replace"):
        if line.startswith("#") or "::" not in line:
            continue
        de_raw, en_raw = line.split("::", 1)
        # nur die erste |-Gruppe: dort stehen die Grundformen,
        # danach folgen Beugung und Beispielsaetze
        de_list = [clean(x) for x in de_raw.split("|")[0].split(";")]
        en_list = [clean(x) for x in en_raw.split("|")[0].split(";")]
        for en in en_list:
            e = en[3:].strip() if en.lower().startswith("to ") else en
            if e[:1].isupper() and not e.isupper():      # Eigennamen raus
                continue
            e = e.lower()
            if not WORD_EN.match(e):
                continue
            for d in de_list:
                if d.lower().startswith(("etw. ", "jdn. ", "jdm. ", "sich ")):
                    d = d.split(" ", 1)[1]
                if not WORD_DE.match(d) or d.lower() == e.lower() or d.lower() in STOP_DE:
                    continue
                cand[e][d] += 1
    return cand


def choose(cand):
    """Unter mehreren Bedeutungen gewinnt die im Deutschen gebraeuchlichste.
    Ohne diesen Schritt hiesse "drag" hier "Dregganker" statt "ziehen"."""
    best = {}
    for en, opts in cand.items():
        best[en] = max(opts, key=lambda d: (round(zipf_frequency(d.lower(), "de"), 1),
                                            opts[d]))
    return best


def main():
    best = choose(collect())
    # Die haeufigsten englischen Woerter werden ausgelassen: dort waehlt ein
    # Rohwoerterbuch regelmaessig die falsche Bedeutung ("have" -> "bringen").
    # Fuer die ist die handgepflegte Dictionary.lua zustaendig.
    sel = []
    for en in sorted(best, key=lambda w: -zipf_frequency(w, "en")):
        if zipf_frequency(en, "en") >= ZIPF_CEILING:
            continue
        sel.append((en, best[en]))
        if len(sel) >= TARGET:
            break

    out = sys.stdout
    out.write('''-- WoWChatDE - Grundwortschatz Englisch -> Deutsch
--
-- Erzeugt von tools/build_words.py, danach tools/clean_words.py.
--
-- Quelle: Ding-Woerterbuch der TU Chemnitz
--   Copyright (C) Frank Richter 1995-2020
--   Lizenz: GNU General Public License, Version 2 oder spaeter
--   https://www-user.tu-chemnitz.de/~fri/ding/
--
-- Dictionary.lua und der WoW-Slang haben immer Vorrang vor dieser Datei.

local ADDON, ns = ...

ns.BIG = {
''')
    row = []
    for en, de in sel:
        row.append('["%s"]="%s",' % (en, de))
        if len(row) == 8:
            out.write("".join(row) + "\n"); row = []
    if row:
        out.write("".join(row) + "\n")
    out.write("}\n")
    print(f"{len(sel)} Eintraege erzeugt", file=sys.stderr)


if __name__ == "__main__":
    main()
