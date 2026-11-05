# Änderungen

## 3.0.0-beta (in Entwicklung)
* Für **WoW Forever** (Interface 16001). Der Chatfilter nutzt `ChatFrameUtil.AddMessageEventFilter`, der alte Name bleibt als Rückfall.
* **Einstellungsfenster** mit den Reitern Allgemein, Kanäle, Sprachen und Claude. Großer An/Aus-Schalter, Kanäle einzeln wählbar, Testfeld.
* Offline jetzt auch **Deutsch → Englisch** (umgekehrtes Wörterbuch).
* **Claude-Hilfe** (`/chatde hilfe`): ausgewählte Chatzeilen übersetzen, Questhilfe, Talentberater. Die Antworten erscheinen im Spiel.
* **Datenschutz-Hinweis** vor jeder Übertragung. Abschaltbar bis zum nächsten Update.
* **Chat DE Companion** (Python, Symbol in der Taskleiste, ohne Konsolenfenster). Er überträgt Anfragen an die Anthropic-API. Der API-Schlüssel wird mit Windows-DPAPI verschlüsselt.
* Minikarten-Knopf und Addon-Sammelknopf.
* Fehler behoben: `|` in den Hilfetexten wurde von WoW als Steuerzeichen gelesen.

## 2.1
* Erste Veröffentlichung. Entwickelt von Veni_Vidi_Witti gemeinsam mit Claude von Anthropic.
* Grundwortschatz mit 24.835 Wörtern aus dem Ding-Wörterbuch der TU Chemnitz.
* Handgepflegte Liste mit WoW-Jargon, Abkürzungen und Redewendungen.
* Beugungserkennung für Plural, `-ing`, `-ed` und Steigerungsformen.
* Vulgärsprache und Beleidigungen aus dem Grundwortschatz entfernt.
* Selbsttest `/chatde pruefen` und Fehlersuche `/chatde debug`.
