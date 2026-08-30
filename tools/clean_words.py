# -*- coding: utf-8 -*-
"""Entfernt Vulgaersprache und Beleidigungen aus Words.lua.
Blizzards Add-On-Policy verlangt Inhalte gemaess ESRB-Freigabe "T"."""
import re, sys

VULGAR_EN = set("""anus arse arsed arsehole ass asshole bastard bellend bitch bloody
bollocks bonk bone boner boob boobs bop brothel bugger bullshit bum butt cock
cocksucker coon crap cripple cum cunt damn dammit dick dildo dipshit dong dyke fag
faggot fanny fuck fucker fucking gash gay gook hell hooker hooters horny jerk jizz
kike knob masturbate masturbation midget mong nigga nigger orgasm penis piss pissed
poof porn porno pornography prick prostitute pussy queer rape rapist retard retarded
scrotum screw semen shag shemale shit shite shithead slag slut sodomy spastic spic
spunk testicle testicles tit tits titties tranny turd twat vagina wank wanker wetback
whore willy""".split())

VULGAR_SUB = ("fuck", "shit", "cunt", "nigg", "whore", "porn", "wank", "masturb",
              "bugger", "arsch", "titt", "penis", "vagina", "rape", "slut")

VULGAR_DE = set("""Arsch Arschloch Arschficker Scheiße Scheisse Scheiß scheiß Fotze
Muschi Schwanz Titte Titten Möpse Nutte Hure Hurensohn Wichser wichsen Fick ficken
Pisse pissen Kacke kacken Penis Vagina Hoden Sperma abspritzen Bordell Puff Nigger
Neger Schwuchtel Spast Krüppel Missgeburt Vergewaltigung vergewaltigen bumsen
Orgasmus onanieren Möse Miststück Kuhscheiße Latte Dreck Schlampe Nutte""".split())

def offensive(en, de):
    e = en.lower()
    if e in VULGAR_EN or any(v in e for v in VULGAR_SUB):
        return True
    if de in VULGAR_DE or any(v in de.lower() for v in VULGAR_SUB):
        return True
    return False

src = sys.argv[1] if len(sys.argv) > 1 else "Words.lua"
text = open(src, encoding="utf-8").read()
head, body = text.split("ns.BIG = {\n", 1)
body = body.rsplit("}\n", 1)[0]

entries = re.findall(r'\["([^"]+)"\]="([^"]+)"', body)
kept = [(en, de) for en, de in entries if not offensive(en, de)]
removed = len(entries) - len(kept)

lines, row = [], []
for en, de in kept:
    row.append('["%s"]="%s",' % (en, de))
    if len(row) == 8:
        lines.append("".join(row)); row = []
if row: lines.append("".join(row))

head = re.sub(r"-- [\d.,]+ Eintraege\.", "-- %s Eintraege." % f"{len(kept):,}".replace(",", "."), head)
open(src, "w", encoding="utf-8").write(head + "ns.BIG = {\n" + "\n".join(lines) + "\n}\n")
print(f"entfernt: {removed}   verbleibend: {len(kept):,}")
