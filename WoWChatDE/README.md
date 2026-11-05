# Chat DE 3.0 – Chatübersetzung und Claude-Hilfe für WoW Forever

> [!WARNING]
> **In Entwicklung – Nutzung auf eigene Verantwortung.** Diese Version ist eine Vorab-Version und kann Fehler enthalten. Es wird keine Haftung übernommen, weder für Schäden noch für Datenverlust oder Kosten.

> [!IMPORTANT]
> **Die Claude-Funktionen kosten Geld.** Sie brauchen ein eigenes API-Konto bei Anthropic mit Guthaben und einen eigenen API-Schlüssel. Jede Anfrage wird nach Tokens über **dein** Konto abgerechnet (Preise: https://www.anthropic.com/pricing). Chat DE sendet nur, wenn du auf einen Claude-Knopf klickst. Die Offline-Übersetzung ist kostenlos.

> **Entwickelt von Veni_Vidi_Witti gemeinsam mit Claude von Anthropic.**

## Was es kann

**Ohne Internet, direkt im Chat:**
- Hängt hinter eingehende Chatnachrichten eine Übersetzung: **Englisch → Deutsch** oder **Deutsch → Englisch**
- Großes Einstellungsfenster: An/Aus-Schalter, Kanäle einzeln wählbar, Anzeige (Original + Übersetzung oder nur Übersetzung), Testfeld
- Rund 25.000 Wörter Grundwortschatz plus WoW-Jargon (`lfm`, `wts`, `pst`, `oom` …)

**Mit Claude (optional, nur auf Knopfdruck):**
- **Übersetzen:** Ausgewählte Chatzeilen werden sinngemäß in eine Sprache deiner Wahl übersetzt.
- **Questhilfe:** Quest auswählen, optional eine Frage stellen, Tipps bekommen.
- **Talentberater:** Vorschläge, wohin die nächsten Talentpunkte gehen sollen (Leveln, Dungeons, Schlachtzug, PvP …).
- Vor jeder Übertragung erscheint ein **Datenschutz-Hinweis**. Abschalten geht per Kästchen; nach jedem Update erscheint er wieder.
- Die Antworten werden **im Spiel** angezeigt (Claude-Hilfe > Antworten), zusammen mit dem Tokenverbrauch.

## Installation

1. Den Ordner `WoWChatDE` nach `World of Warcraft\_forever_\Interface\AddOns\` kopieren.
2. Spiel starten und **Chat DE** in der AddOn-Liste aktivieren.

Für die Offline-Übersetzung ist das alles.

## Claude-Funktionen einrichten (optional)

WoW-Addons können selbst nicht ins Internet. Darum gibt es den **Chat DE Companion** im Ordner `Companion`: ein kleines Programm ohne Konsolenfenster, das nur als Symbol neben der Uhr läuft (wie der WeakAuras Companion).

Du brauchst:
- **Python 3.10 oder neuer** (python.org)
- ein **API-Konto bei Anthropic** mit Guthaben (console.anthropic.com). Abgerechnet wird pro Nutzung über dein Konto.

Einrichtung:
1. Pakete einmal installieren: im Ordner `Companion` `py -m pip install -r requirements.txt` ausführen.
2. `chatde_companion.pyw` doppelklicken. Es öffnet sich kein schwarzes Fenster, nur das Einrichtungsfenster.
3. Die Datenschutz-Erklärung lesen und bestätigen, dann den API-Schlüssel eintragen. Der WoW-Ordner wird automatisch erkannt.
4. Fertig. Der Companion läuft unsichtbar weiter (Symbol neben der Uhr). Auf Wunsch startet er mit Windows.

### So läuft eine Claude-Anfrage ab

1. Im Spiel `/chatde hilfe` öffnen und z. B. bei einer Quest auf **„Claude fragen“** klicken.
2. Der Datenschutz-Hinweis zeigt, was gesendet wird. Mit **„Senden“** wird das Interface kurz neu geladen (WoW gibt Addon-Daten nur so weiter).
3. Der Companion fragt Claude und meldet nach einigen Sekunden **„Antwort bereit“**.
4. Im Spiel auf **„Antwort laden“** klicken. Nach dem kurzen Neuladen steht die Antwort im Reiter **Antworten**.

## Befehle

| Befehl | Wirkung |
|---|---|
| `/chatde` | Einstellungen öffnen |
| `/chatde hilfe` | Claude-Hilfe öffnen |
| `/chatde an` / `aus` | Übersetzung ein- oder ausschalten |
| `/chatde test <text>` | Übersetzung ausprobieren |
| `/chatde pruefen` | Selbsttest |
| `/chatde status` | aktuelle Einstellungen |
| `/chatde minimap` | Minikarten-Knopf ein/aus |
| `/chatde info` | wer das gemacht hat |

Minikarten-Knopf: Linksklick öffnet die Einstellungen, Rechtsklick die Claude-Hilfe.

## Kosten

- **Offline-Übersetzung:** kostenlos, ohne Konto, ohne Internet.
- **Claude-Funktionen:** kostenpflichtig über dein eigenes Anthropic-API-Konto. Abgerechnet wird pro Token, also nach der Länge von Frage und Antwort.
- **Kosten im Blick behalten:** Den Verbrauch jeder Antwort siehst du im Spiel (Claude-Hilfe > Antworten, Einstellungen > Claude) und im Companion (Status & Protokoll). Im Companion lässt sich für jede Funktion ein günstigeres oder stärkeres Modell wählen.
- **Ausgabenlimit:** Lege in der Anthropic Console (console.anthropic.com) ein Monatslimit fest. Dann können nie mehr Kosten entstehen, als du willst.
- **API-Schlüssel:** Gib deinen Schlüssel niemals weiter, er ist so viel wert wie dein Guthaben. Der Companion speichert ihn verschlüsselt auf deinem PC. Er gehört nie in den Addon-Ordner, in Screenshots oder auf GitHub.

## Datenschutz

Siehe **[Companion/DATENSCHUTZ.md](Companion/DATENSCHUTZ.md)**. Kurz gesagt: Nur auf Knopfdruck wird übertragen, und nur die Daten der jeweiligen Anfrage. Nie übertragen werden Charaktername, Realm, Konto, BattleTag, Gilde, Freunde, Chat-Absender oder deine Position.

## Grenzen

- Die Offline-Übersetzung arbeitet Wort für Wort. Der Sinn kommt an, der Satzbau nicht.
- Claude kann nicht live im Chatfenster übersetzen, weil Addons keine Verbindung nach außen haben. Claude übersetzt ausgewählte Zeilen auf Knopfdruck.
- WoW Forever ist neu. Bei Quest- und Talentdetails kann Claude falsch liegen. Es ist angewiesen, Unsicheres als unsicher zu kennzeichnen.
- Talente verteilen musst du selbst. Addons dürfen das nicht automatisch.

## Lizenz

**GNU General Public License v2 oder später.** `Words.lua` stammt aus dem Ding-Wörterbuch der TU Chemnitz, Copyright (C) Frank Richter 1995–2020, GPL v2. Details stehen in `LIZENZ-Woerterbuch.txt`, der Volltext in `LICENSE`.
