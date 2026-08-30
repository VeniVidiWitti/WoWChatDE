# Chat DE — Chatübersetzung für World of Warcraft

> **Entwickelt von Veni_Vidi_Witti gemeinsam mit Claude von Anthropic.**
> Veni_Vidi_Witti kam mit der Idee, hat die Anforderungen gesetzt, jede Fassung
> im Spiel erprobt und die Fehler gefunden. Claude hat den Code geschrieben und
> das Wörterbuch aufbereitet. Ohne das Hin und Her zwischen beiden wäre daraus
> nichts geworden.

Hängt hinter jede eingehende englische Chatnachricht die deutsche Übersetzung —
direkt in der Chatzeile.

```
[2. Handel] Thrallbro: lfm 1 healer for scholo, pst for inv ty
  » suche Mitspieler 1 Heiler für Scholomance, anflüstern für Einladung danke
```

Reines Addon. Kein Fremdprogramm, kein API-Schlüssel, kein Internetzugang. Das
gesamte Wörterbuch steckt im Addon.

## Was es kann

* Übersetzt in **allen** Chatkanälen: Sagen, Rufen, Emote, Gruppe, Schlachtzug,
  Schlachtzugswarnung, Instanzchat, Gilde, Offizier, Flüstern (auch Battle.net),
  alle nummerierten Kanäle sowie AFK- und DND-Antworten.
* **25.000 Wörter** Grundwortschatz plus eine handgepflegte Liste mit WoW-Jargon,
  Redewendungen und Abkürzungen (`lfm`, `wts`, `pst`, `oom`, `brez`, …).
* **Beugungserkennung**: `potions` findet `potion`, `selling` findet `sell`,
  `pulled` findet `pull`, `faster` findet `fast`.
* Lässt deutsche Nachrichten in Ruhe, deine eigenen ebenfalls (umschaltbar).
* Gegenstandslinks, Farbcodes und Symbole bleiben unangetastet.
* Sendet nichts, empfängt nichts, spricht mit niemandem. Rein lokal.

## Was es nicht kann

Das ist ein Wörterbuch, kein Übersetzer. Es ersetzt Wörter und Wendungen einzeln
und kennt keine Grammatik:

```
that mob hits like a truck, use your defensive cooldowns
  » das Gegner trifft wie Laster, benutzen dein defensiv Abklingzeit
```

Der Sinn kommt an, der Satzbau nicht. Für WoW-Sprache und kurze Zeilen trifft es
gut, bei langen freien Sätzen wird es holprig.

Mehr ist ohne Internetzugang nicht möglich, und den haben WoW-Addons nicht: die
Lua-Sandbox von Blizzard kennt weder Sockets noch Dateizugriff. Jedes Addon, das
echte Satzübersetzung verspricht, braucht dafür ein Programm außerhalb des Spiels.

## Getestet mit

Entwickelt und erprobt auf **Burning Crusade Classic (Anniversary), Interface
20506**. Der Code benutzt nur Schnittstellen, die es in allen Spielfassungen
gibt, und die mitgelieferten TOC-Dateien decken auch Classic Era, Mists Classic
und Retail ab — dort ist es aber **nicht erprobt**. Rückmeldungen willkommen.

## Installation

Den Ordner `WoWChatDE` nach `Interface\AddOns\` kopieren, WoW neu starten.

## Befehle

| Befehl | Wirkung |
|---|---|
| `/chatde` | Befehlsübersicht |
| `/chatde an` \| `aus` | Übersetzung ein-/ausschalten |
| `/chatde modus append` | Original + Übersetzung (Standard) |
| `/chatde modus ersetzen` | nur die Übersetzung anzeigen |
| `/chatde min 2` | erst ab 2 erkannten Wörtern übersetzen |
| `/chatde eigene` | eigene Nachrichten mitübersetzen |
| `/chatde test <text>` | Übersetzung ausprobieren |
| `/chatde pruefen` | Selbsttest, zeigt jeden Schritt einzeln |
| `/chatde debug` | jede Nachricht kommentieren |
| `/chatde status` | aktuelle Einstellungen |
| `/chatde info` | wer das Addon gemacht hat, Herkunft des Wörterbuchs |

## Wenn etwas nicht geht

| Problem | Was tun |
|---|---|
| Addon steht auf „Veraltet" | „Veraltete Addons laden" ankreuzen |
| Es übersetzt gar nichts | `/chatde pruefen` — der Selbsttest zeigt jeden Schritt einzeln |
| Eine bestimmte Zeile bleibt englisch | `/chatde debug`, dann nennt es den Grund |
| Eigene Zeilen bleiben englisch | so gewollt; `/chatde eigene` schaltet sie dazu |
| Übersetzung fehlt, obwohl Wörter bekannt sind | wäre sie wortgleich mit dem Original, wird sie unterdrückt |

## Aufbau des Wortschatzes

Drei Ebenen, die obere gewinnt:

| Datei | Inhalt |
|---|---|
| `Dictionary.lua` | WoW-Jargon, Abkürzungen, Redewendungen, häufige Wörter, gezielte Korrekturen — von Hand gepflegt |
| `Words.lua` | 24.835 Wörter Grundwortschatz aus dem Ding-Wörterbuch |

Die rund 250 häufigsten englischen Wörter stehen bewusst **nicht** in `Words.lua`.
Dort greift ein Rohwörterbuch regelmäßig daneben — es würde `have` mit „bringen"
und `the` mit „dahingehend" übersetzen. Diese Wörter sind von Hand gepflegt.

Bei mehreren möglichen Bedeutungen gewinnt die im Deutschen gebräuchlichste.
Ohne diesen Schritt hieße `drag` hier „Dregganker" statt „ziehen".

## Wörterbuch nachbauen

`Words.lua` ist erzeugt, nicht getippt. So entsteht die Datei neu:

```bash
sudo apt-get install trans-de-en
pip install wordfreq
python3 tools/build_words.py > WoWChatDE/Words.lua
python3 tools/clean_words.py WoWChatDE/Words.lua
```

`clean_words.py` entfernt Vulgärsprache und Beleidigungen — Blizzards
Add-On-Policy verlangt Inhalte gemäß ESRB-Freigabe „T".

## Wer das gemacht hat

**Veni_Vidi_Witti** — Idee, Anforderungen, Erprobung im Spiel, Fehlersuche.
**Claude von Anthropic** — Umsetzung des Codes, Aufbereitung des Wörterbuchs.

Entstanden ist es im Wechselspiel: Veni_Vidi_Witti hat gesagt, was gebraucht
wird und was im Spiel nicht funktioniert, Claude hat gebaut und nachgebessert.

Im Spiel steht die Nennung unter `/chatde info`.

## Lizenz

**GNU General Public License v2 oder später.**

`Words.lua` ist aus dem Ding-Wörterbuch der TU Chemnitz abgeleitet, Copyright (C)
Frank Richter 1995–2020, GPL v2. Damit steht das gesamte Addon unter der GPL v2.
Volltext in `LICENSE`, Einzelheiten zur Herkunft in
`WoWChatDE/LIZENZ-Woerterbuch.txt`.
