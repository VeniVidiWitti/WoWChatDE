# Datenschutz – Chat DE und Chat DE Companion

Stand: Chat DE 3.0.0-beta / Companion 1.0.0-beta

## Kurz gesagt

- Die normale Chat-Übersetzung von Chat DE läuft **komplett offline**, über das Wörterbuch im Addon. Dabei wird nichts übertragen.
- Nur wenn du im Spiel selbst auf einen **Claude-Knopf** klickst („Mit Claude übersetzen“, „Claude fragen“, „Talentvorschlag holen“), überträgt der Companion diese eine Anfrage an **Anthropic** (api.anthropic.com, USA).
- Vor jeder Übertragung zeigt Chat DE im Spiel einen Hinweis mit genau den Daten, die gesendet werden. Du kannst ihn abschalten. Nach jedem Update erscheint er wieder.
- Es gibt keine Hintergrundübertragung, keine Statistik und keine Werbung, und es werden keine Daten an den Entwickler gesendet.

## Was übertragen wird

| Funktion | Was gesendet wird |
|---|---|
| Mit Claude übersetzen | nur die Texte der Chatzeilen, die du ausgewählt hast, und die Zielsprache |
| Questhilfe | Questtitel, Questbeschreibung, Questziele und Fortschritt, Questgebiet, Queststufe, deine Charakterstufe und Klasse, deine Frage (falls eingegeben) |
| Talentberater | Klasse, Spezialisierung, Rolle, Stufe, gewählte und verfügbare Talente, freie Punkte, dein Ziel, deine Wünsche (falls eingegeben) |

Dazu kommt eine feste Anleitung für Claude („antworte auf Deutsch, kurz, ohne Markdown …“).

## Was nie übertragen wird

- Charaktername (in Questtexten wird er vor dem Senden durch „[Spielername]“ ersetzt)
- Realm, Kontoname, BattleTag, Gilde, Freundesliste
- Namen der Absender von Chatnachrichten (Chat DE speichert sie gar nicht erst)
- deine Position im Spiel
- Inhalte anderer Addons, Dateien oder Daten von deinem PC

## Wohin die Daten gehen

Der Companion sendet die Anfrage verschlüsselt (HTTPS) direkt an **api.anthropic.com**. Dort verarbeitet Anthropic sie nach seinen eigenen Bedingungen und seiner Datenschutzerklärung: https://www.anthropic.com/legal/privacy

Abgerechnet wird über **dein eigenes** Anthropic-API-Konto. Die Kosten richten sich nach den Tokens. Wie viele Tokens jede Anfrage verbraucht hat, steht im Spiel (Einstellungen > Claude) und im Companion (Protokoll).

## Was auf deinem PC gespeichert wird

| Ort | Inhalt |
|---|---|
| `%APPDATA%\ChatDE-Companion\config.json` | API-Schlüssel (mit Windows-DPAPI verschlüsselt, nur von deinem Windows-Benutzer lesbar), WoW-Ordner, Modellwahl |
| `%APPDATA%\ChatDE-Companion\state.json` | Antworten, die das Addon noch nicht abgeholt hat, und das Protokoll (Zeit, Art, Kurzbeschreibung, Tokens; keine Chattexte) |
| `%APPDATA%\ChatDE-Companion\companion.log` | technische Fehlermeldungen |
| `WTF\...\SavedVariables\WoWChatDE.lua` | Einstellungen des Addons, offene Anfragen, Verlauf der letzten 30 Antworten (schreibt WoW selbst) |
| `Interface\AddOns\WoWChatDE\Inbox.lua` | Antworten für das Addon (schreibt der Companion) |

Der API-Schlüssel kommt **nie** in den Spieleordner, in die gespeicherten Daten von WoW oder auf GitHub.

## Wie man alles löscht

1. Im Companion: Einstellungen > „Schlüssel löschen“, dann „Beenden“.
2. Den Ordner `%APPDATA%\ChatDE-Companion` löschen.
3. Im Spiel: Claude-Hilfe > Antworten > „Verlauf leeren“, oder das Addon entfernen.
4. Den API-Schlüssel kannst du außerdem jederzeit unter console.anthropic.com widerrufen.

## Ohne Companion

Ohne den Companion funktioniert Chat DE ganz normal mit der Offline-Übersetzung. Die Claude-Knöpfe legen dann nur Anfragen ab, die nie gesendet werden.
