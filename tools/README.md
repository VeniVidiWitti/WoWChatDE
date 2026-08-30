# Werkzeuge

`Words.lua` ist erzeugt, nicht getippt. Diese beiden Skripte bauen die Datei aus
dem Ding-Wörterbuch der TU Chemnitz neu auf. Sie sind der „Quelltext" der
Datendatei im Sinne der GPL.

```bash
sudo apt-get install trans-de-en     # Ding-Wörterbuch (GPL v2)
pip install wordfreq                 # Worthäufigkeiten

python3 tools/build_words.py > WoWChatDE/Words.lua
python3 tools/clean_words.py WoWChatDE/Words.lua
```

`build_words.py` wählt unter mehreren Bedeutungen die im Deutschen
gebräuchlichste und lässt die häufigsten englischen Wörter aus.
`clean_words.py` entfernt Vulgärsprache und Beleidigungen — Blizzards
Add-On-Policy verlangt Inhalte gemäß ESRB-Freigabe „T".
