"""Chat DE Companion - Begleitprogramm fuer das WoW-Addon Chat DE.

Laeuft unsichtbar im Hintergrund (Symbol im Infobereich der Taskleiste),
ohne Konsolenfenster. Es wartet auf Claude-Anfragen des Addons, schickt sie
an die Anthropic-API und legt die Antworten fuer das Addon ab.

Starten:  pythonw chatde_companion.pyw   (pythonw = Python ohne Konsole)
Datenschutz: siehe DATENSCHUTZ.md im selben Ordner.

Lizenz: GNU General Public License v2 oder spaeter.
"""

from __future__ import annotations

import base64
import ctypes
import ctypes.wintypes as wt
import json
import os
import queue
import sys
import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

COMPANION_VERSION = "1.0.0-beta"
APP_NAME = "Chat DE Companion"
SCRIPT_DIR = Path(__file__).resolve().parent
CONFIG_DIR = Path(os.environ.get("APPDATA", str(Path.home()))) / "ChatDE-Companion"
CONFIG_FILE = CONFIG_DIR / "config.json"
STATE_FILE = CONFIG_DIR / "state.json"
LOG_FILE = CONFIG_DIR / "companion.log"
POLL_SECONDS = 2.0
LOG_MAX = 60


# ---------------------------------------------------------------------------
# Kleine Helfer
# ---------------------------------------------------------------------------

def log_to_file(msg: str) -> None:
    try:
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(LOG_FILE, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
    except OSError:
        pass


def fatal(msg: str) -> None:
    """Fehlermeldung als Fenster (es gibt ja keine Konsole)."""
    log_to_file("FEHLER: " + msg)
    try:
        r = tk.Tk()
        r.withdraw()
        messagebox.showerror(APP_NAME, msg)
        r.destroy()
    except Exception:
        pass
    sys.exit(1)


try:
    import anthropic  # noqa: E402
    import pystray  # noqa: E402
    from PIL import Image, ImageDraw  # noqa: E402
except ImportError as _e:
    fatal(
        "Es fehlen Python-Pakete für den Chat DE Companion.\n\n"
        "Bitte einmal installieren (Eingabeaufforderung):\n"
        "    py -m pip install -r requirements.txt\n\n"
        f"Ordner: {SCRIPT_DIR}\n\nFehlend: {_e.name}"
    )

sys.path.insert(0, str(SCRIPT_DIR))
from claude_client import (  # noqa: E402
    DEFAULT_MAX_TOKENS, DEFAULT_MODELS, MODEL_CHOICES, ask_claude, build_prompt,
)
from savedvars import read_savedvariables, write_inbox  # noqa: E402


# ---------------------------------------------------------------------------
# API-Schluessel mit Windows-DPAPI verschluesseln (nur dieser Windows-Benutzer)
# ---------------------------------------------------------------------------

class _Blob(ctypes.Structure):
    _fields_ = [("cbData", wt.DWORD), ("pbData", ctypes.POINTER(ctypes.c_char))]


def _dpapi(data: bytes, protect: bool) -> bytes:
    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    buf = ctypes.create_string_buffer(data, len(data))
    src = _Blob(len(data), ctypes.cast(buf, ctypes.POINTER(ctypes.c_char)))
    dst = _Blob()
    fn = crypt32.CryptProtectData if protect else crypt32.CryptUnprotectData
    ok = fn(ctypes.byref(src), None, None, None, None, 0, ctypes.byref(dst))
    if not ok:
        raise OSError("DPAPI fehlgeschlagen")
    try:
        return ctypes.string_at(dst.pbData, dst.cbData)
    finally:
        kernel32.LocalFree(dst.pbData)


def protect_key(key: str) -> str:
    return base64.b64encode(_dpapi(key.encode("utf-8"), True)).decode("ascii")


def unprotect_key(blob: str) -> str:
    return _dpapi(base64.b64decode(blob), False).decode("utf-8")


# ---------------------------------------------------------------------------
# Einstellungen und Zustand
# ---------------------------------------------------------------------------

def default_flavor_dir() -> str:
    # Companion liegt in <WoW>\_forever_\Interface\AddOns\WoWChatDE\Companion
    flavor = SCRIPT_DIR.parent.parent.parent.parent
    return str(flavor) if (flavor / "WTF").is_dir() else ""


def load_json(path: Path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save_json(path: Path, data) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


class Config:
    def __init__(self):
        d = load_json(CONFIG_FILE, {})
        self.api_key_blob: str = d.get("api_key_protected", "")
        self.flavor_dir: str = d.get("wow_flavor_dir") or default_flavor_dir()
        self.models: dict = {**DEFAULT_MODELS, **d.get("models", {})}
        self.max_tokens: dict = {**DEFAULT_MAX_TOKENS, **d.get("max_tokens", {})}
        self.notify: bool = d.get("notify", True)
        self.privacy_ack: str = d.get("privacy_ack_version", "")

    def save(self):
        save_json(CONFIG_FILE, {
            "api_key_protected": self.api_key_blob,
            "wow_flavor_dir": self.flavor_dir,
            "models": self.models,
            "max_tokens": self.max_tokens,
            "notify": self.notify,
            "privacy_ack_version": self.privacy_ack,
        })

    def api_key(self) -> str:
        if not self.api_key_blob:
            return ""
        try:
            return unprotect_key(self.api_key_blob)
        except (OSError, ValueError):
            return ""

    @property
    def ready(self) -> bool:
        return bool(self.api_key_blob) and self.privacy_ack == COMPANION_VERSION and bool(self.flavor_dir)

    def inbox_path(self) -> Path:
        return Path(self.flavor_dir) / "Interface" / "AddOns" / "WoWChatDE" / "Inbox.lua"

    def savedvar_files(self) -> list[Path]:
        acc = Path(self.flavor_dir) / "WTF" / "Account"
        if not acc.is_dir():
            return []
        return sorted(acc.glob("*/SavedVariables/WoWChatDE.lua"))


# ---------------------------------------------------------------------------
# Autostart (nur auf Wunsch, ueber das Kaestchen in den Einstellungen)
# ---------------------------------------------------------------------------

RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
RUN_NAME = "ChatDECompanion"


def pythonw_exe() -> str:
    exe = Path(sys.executable)
    cand = exe.with_name("pythonw.exe")
    return str(cand if cand.exists() else exe)


def autostart_enabled() -> bool:
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            winreg.QueryValueEx(k, RUN_NAME)
            return True
    except OSError:
        return False


def set_autostart(on: bool) -> None:
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as k:
        if on:
            cmd = f'"{pythonw_exe()}" "{Path(__file__).resolve()}"'
            winreg.SetValueEx(k, RUN_NAME, 0, winreg.REG_SZ, cmd)
        else:
            try:
                winreg.DeleteValue(k, RUN_NAME)
            except OSError:
                pass


# ---------------------------------------------------------------------------
# Arbeiter: wartet auf Anfragen, fragt Claude, schreibt Inbox.lua
# ---------------------------------------------------------------------------

def request_key(req: dict) -> str:
    """Fingerabdruck einer Anfrage ohne ID und Zeitstempel (zum Erkennen von Doppelten)."""
    core = {k: v for k, v in req.items() if k not in ("id", "created", "addonVersion")}
    return json.dumps(core, sort_keys=True, ensure_ascii=False, default=str)


class Worker(threading.Thread):
    def __init__(self, app: "App"):
        super().__init__(daemon=True)
        self.app = app
        self.cfg = app.cfg
        st = load_json(STATE_FILE, {})
        self.answers: dict = st.get("answers", {})      # id -> Antwort
        self.log: list = st.get("log", [])               # was gesendet wurde
        self.mtimes: dict = {}
        self.stop_event = threading.Event()
        self.wake_event = threading.Event()
        self.status = "Startet ..."

    def save_state(self):
        save_json(STATE_FILE, {"answers": self.answers, "log": self.log[-LOG_MAX:]})

    def add_log(self, kind: str, summary: str, ans=None, error: str | None = None):
        self.log.append({
            "time": int(time.time()), "kind": kind, "summary": summary,
            "tokens_in": getattr(ans, "tokens_in", 0), "tokens_out": getattr(ans, "tokens_out", 0),
            "model": getattr(ans, "model", ""), "error": error,
        })
        self.log = self.log[-LOG_MAX:]
        self.app.ui(self.app.refresh_log)

    def run(self):
        while not self.stop_event.is_set():
            try:
                self.tick()
            except Exception as e:  # nie abstuerzen - nur protokollieren
                log_to_file(f"tick: {e!r}")
                self.status = f"Fehler: {e}"
            self.wake_event.wait(POLL_SECONDS)
            self.wake_event.clear()

    def read_requests(self) -> dict:
        requests = {}
        for f in self.cfg.savedvar_files():
            try:
                data = read_savedvariables(str(f))
            except Exception as e:
                log_to_file(f"Lesen fehlgeschlagen ({f.name}): {e!r}")
                continue
            box = data.get("WoWChatDE_Outbox") or {}
            reqs = box.get("requests") if isinstance(box, dict) else None
            if isinstance(reqs, dict):
                for rid, req in reqs.items():
                    if isinstance(req, dict) and isinstance(rid, str):
                        requests[rid] = req
        return requests

    def tick(self):
        if not self.cfg.ready:
            self.status = "Nicht eingerichtet - bitte Einstellungen öffnen."
            return
        files = self.cfg.savedvar_files()
        changed = False
        for f in files:
            try:
                m = f.stat().st_mtime
            except OSError:
                continue
            if self.mtimes.get(str(f)) != m:
                self.mtimes[str(f)] = m
                changed = True
        if not changed and self.status.startswith("Bereit"):
            return
        requests = self.read_requests()
        pending = [rid for rid in requests if rid not in self.answers]
        if pending:
            key = self.cfg.api_key()
            if not key:
                self.status = "API-Schlüssel fehlt oder ist nicht lesbar."
                return
            client = anthropic.Anthropic(api_key=key, timeout=120.0, max_retries=2)
            for rid in pending:
                req = requests[rid]
                kind = str(req.get("kind", "?"))
                # Identische Anfrage schon beantwortet? Dann Antwort wiederverwenden (keine Kosten).
                rkey = request_key(req)
                reuse = next((a for a in self.answers.values() if a.get("key") == rkey and not a.get("error")), None)
                if reuse:
                    self.answers[rid] = {**reuse, "time": int(time.time()), "tokensIn": 0, "tokensOut": 0}
                    continue
                try:
                    _, _, summary = build_prompt(req)
                except ValueError:
                    summary = kind
                self.status = f"Frage Claude: {summary}"
                self.app.ui(self.app.refresh_status)
                ans = ask_claude(client, req, self.cfg.models, self.cfg.max_tokens)
                self.answers[rid] = {
                    "text": ans.text, "error": ans.error, "time": int(time.time()),
                    "tokensIn": ans.tokens_in, "tokensOut": ans.tokens_out, "model": ans.model,
                    "key": rkey,
                }
                self.add_log(kind, ans.sent_summary or summary, ans, ans.error)
                self.write_inbox(requests)
                self.save_state()
                if self.cfg.notify:
                    msg = ("Fehler: " + ans.error) if ans.error else "Antwort bereit - im Spiel auf 'Antwort laden' klicken."
                    self.app.notify(msg)
        # Antworten, die das Addon schon uebernommen hat, wegraeumen
        for rid in list(self.answers):
            if rid not in requests:
                del self.answers[rid]
        self.write_inbox(requests)
        self.save_state()
        n = len(requests)
        self.status = f"Bereit - {n} offene Anfrage(n), letzte Prüfung {time.strftime('%H:%M:%S')}"
        self.app.ui(self.app.refresh_status)

    def write_inbox(self, requests: dict):
        answers = {rid: {k: v for k, v in a.items() if k != "key"}
                   for rid, a in self.answers.items() if rid in requests}
        inbox = {"schema": 1, "written": int(time.time()), "companion": COMPANION_VERSION, "answers": answers}
        path = self.cfg.inbox_path()
        if path.parent.is_dir():
            write_inbox(str(path), inbox)


# ---------------------------------------------------------------------------
# Oberflaeche: Symbol in der Taskleiste + Fenster nur bei Bedarf
# ---------------------------------------------------------------------------

def make_icon_image() -> "Image.Image":
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((2, 2, 62, 62), fill=(38, 160, 120, 255), outline=(255, 210, 77, 255), width=4)
    d.text((17, 20), "DE", fill=(255, 255, 255, 255))
    return img


def read_privacy_text() -> str:
    try:
        return (SCRIPT_DIR / "DATENSCHUTZ.md").read_text(encoding="utf-8")
    except OSError:
        return "DATENSCHUTZ.md wurde nicht gefunden."


class App:
    def __init__(self):
        self.cfg = Config()
        self.root = tk.Tk()
        self.root.withdraw()
        self.root.title(APP_NAME)
        self.uiq: queue.Queue = queue.Queue()
        self.window: tk.Toplevel | None = None
        self.worker = Worker(self)
        self.icon = pystray.Icon(
            "chatde", make_icon_image(), APP_NAME,
            menu=pystray.Menu(
                pystray.MenuItem("Öffnen", lambda: self.ui(self.show_window), default=True),
                pystray.MenuItem("Jetzt prüfen", lambda: self.worker.wake_event.set()),
                pystray.MenuItem("Datenschutz", lambda: self.ui(lambda: self.show_window(tab=2))),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Beenden", lambda: self.ui(self.quit)),
            ),
        )

    # Aufrufe aus anderen Threads sicher in den Tk-Thread bringen
    def ui(self, fn):
        self.uiq.put(fn)

    def _pump(self):
        try:
            while True:
                self.uiq.get_nowait()()
        except queue.Empty:
            pass
        self.root.after(150, self._pump)

    def notify(self, msg: str):
        try:
            self.icon.notify(msg, "Chat DE")
        except Exception:
            pass

    def run(self):
        self.icon.run_detached()
        self.worker.start()
        self.root.after(150, self._pump)
        if not self.cfg.ready:
            self.root.after(300, lambda: self.show_window(tab=1 if self.cfg.privacy_ack == COMPANION_VERSION else 2))
        self.root.mainloop()

    def quit(self):
        self.worker.stop_event.set()
        self.worker.wake_event.set()
        try:
            self.icon.stop()
        except Exception:
            pass
        self.root.quit()

    # ------------------------------------------------------------------
    def show_window(self, tab: int = 0):
        if self.window and self.window.winfo_exists():
            self.window.deiconify()
            self.window.lift()
            self.nb.select(tab)
            return
        w = tk.Toplevel(self.root)
        self.window = w
        w.title(f"{APP_NAME} {COMPANION_VERSION}")
        w.geometry("720x520")
        w.minsize(620, 440)
        w.protocol("WM_DELETE_WINDOW", w.withdraw)
        self.nb = ttk.Notebook(w)
        self.nb.pack(fill="both", expand=True, padx=8, pady=8)
        self.nb.add(self._tab_status(self.nb), text="Status & Protokoll")
        self.nb.add(self._tab_settings(self.nb), text="Einstellungen")
        self.nb.add(self._tab_privacy(self.nb), text="Datenschutz")
        self.nb.select(tab)
        self.refresh_status()
        self.refresh_log()

    def _tab_status(self, parent):
        f = ttk.Frame(parent, padding=10)
        self.status_var = tk.StringVar()
        ttk.Label(f, textvariable=self.status_var, font=("Segoe UI", 10, "bold")).pack(anchor="w")
        ttk.Label(f, text="Protokoll: was wann an Claude gesendet wurde (ohne Inhalte).").pack(anchor="w", pady=(10, 2))
        cols = ("zeit", "art", "inhalt", "tokens", "ergebnis")
        self.tree = ttk.Treeview(f, columns=cols, show="headings", height=14)
        for c, t, wdt in zip(cols, ("Zeit", "Art", "Gesendet", "Tokens ein/aus", "Ergebnis"), (110, 70, 270, 100, 120)):
            self.tree.heading(c, text=t)
            self.tree.column(c, width=wdt, anchor="w")
        self.tree.pack(fill="both", expand=True)
        b = ttk.Frame(f)
        b.pack(fill="x", pady=(8, 0))
        ttk.Button(b, text="Jetzt prüfen", command=self.worker.wake_event.set).pack(side="left")
        ttk.Button(b, text="Fenster schließen (läuft weiter)", command=lambda: self.window.withdraw()).pack(side="right")
        return f

    def _tab_settings(self, parent):
        f = ttk.Frame(parent, padding=10)
        ttk.Label(f, text="API-Schlüssel von Anthropic (console.anthropic.com). Achtung: Jede Anfrage kostet Geld über dein Konto.").grid(row=0, column=0, columnspan=3, sticky="w")
        self.key_var = tk.StringVar()
        ttk.Entry(f, textvariable=self.key_var, show="•", width=52).grid(row=1, column=0, columnspan=2, sticky="we")
        self.key_info = ttk.Label(f, text="")
        self.key_info.grid(row=2, column=0, columnspan=3, sticky="w")

        ttk.Label(f, text="WoW-Forever-Ordner (enthält WTF und Interface):").grid(row=3, column=0, sticky="w", pady=(12, 0))
        self.dir_var = tk.StringVar(value=self.cfg.flavor_dir)
        ttk.Entry(f, textvariable=self.dir_var, width=52).grid(row=4, column=0, columnspan=2, sticky="we")
        ttk.Button(f, text="Wählen ...", command=self._choose_dir).grid(row=4, column=2, padx=4)

        ttk.Label(f, text="Modelle:").grid(row=5, column=0, sticky="w", pady=(12, 0))
        self.model_vars = {}
        for i, (kind, label) in enumerate((("translate", "Übersetzen"), ("quest", "Questhilfe"), ("talents", "Talente"))):
            ttk.Label(f, text=label).grid(row=6 + i, column=0, sticky="w")
            v = tk.StringVar(value=self.cfg.models.get(kind))
            ttk.Combobox(f, textvariable=v, values=MODEL_CHOICES, state="readonly", width=22).grid(row=6 + i, column=1, sticky="w")
            self.model_vars[kind] = v
        ttk.Label(f, text="Haiku ist am günstigsten, Opus am stärksten. Preise: anthropic.com/pricing").grid(row=9, column=0, columnspan=3, sticky="w")

        self.notify_var = tk.BooleanVar(value=self.cfg.notify)
        ttk.Checkbutton(f, text="Benachrichtigung, wenn eine Antwort bereit ist", variable=self.notify_var).grid(row=10, column=0, columnspan=3, sticky="w", pady=(12, 0))
        self.auto_var = tk.BooleanVar(value=autostart_enabled())
        ttk.Checkbutton(f, text="Mit Windows starten (unsichtbar, nur Symbol in der Taskleiste)", variable=self.auto_var).grid(row=11, column=0, columnspan=3, sticky="w")

        ttk.Button(f, text="Speichern", command=self._save_settings).grid(row=12, column=0, sticky="w", pady=(16, 0))
        ttk.Button(f, text="Schlüssel löschen", command=self._delete_key).grid(row=12, column=1, sticky="w", pady=(16, 0))
        f.columnconfigure(1, weight=1)
        self._update_key_info()
        return f

    def _tab_privacy(self, parent):
        f = ttk.Frame(parent, padding=10)
        txt = tk.Text(f, wrap="word", height=20, font=("Segoe UI", 9))
        txt.insert("1.0", read_privacy_text())
        txt.configure(state="disabled")
        txt.pack(fill="both", expand=True)
        self.ack_var = tk.BooleanVar(value=self.cfg.privacy_ack == COMPANION_VERSION)
        ttk.Checkbutton(f, text=f"Ich habe die Datenschutz-Erklärung gelesen (Version {COMPANION_VERSION})",
                        variable=self.ack_var, command=self._ack_changed).pack(anchor="w", pady=(8, 0))
        return f

    # ------------------------------------------------------------------
    def _update_key_info(self):
        if self.cfg.api_key_blob:
            self.key_info.configure(text="Ein Schlüssel ist gespeichert (verschlüsselt, nur für deinen Windows-Benutzer lesbar). Feld leer lassen = behalten.")
        else:
            self.key_info.configure(text="Noch kein Schlüssel gespeichert.")

    def _choose_dir(self):
        d = filedialog.askdirectory(title="WoW-Forever-Ordner wählen (z. B. ...\\World of Warcraft\\_forever_)")
        if d:
            self.dir_var.set(d)

    def _ack_changed(self):
        self.cfg.privacy_ack = COMPANION_VERSION if self.ack_var.get() else ""
        self.cfg.save()
        self.worker.wake_event.set()
        self.refresh_status()

    def _save_settings(self):
        d = self.dir_var.get().strip()
        if d and not (Path(d) / "WTF").is_dir():
            messagebox.showwarning(APP_NAME, "In diesem Ordner gibt es keinen Unterordner WTF. Bitte den Ordner _forever_ wählen.")
            return
        key = self.key_var.get().strip()
        if key:
            try:
                self.cfg.api_key_blob = protect_key(key)
            except OSError:
                messagebox.showerror(APP_NAME, "Der Schlüssel konnte nicht verschlüsselt werden.")
                return
            self.key_var.set("")
        self.cfg.flavor_dir = d
        for kind, v in self.model_vars.items():
            self.cfg.models[kind] = v.get()
        self.cfg.notify = bool(self.notify_var.get())
        self.cfg.save()
        try:
            set_autostart(bool(self.auto_var.get()))
        except OSError:
            messagebox.showwarning(APP_NAME, "Autostart konnte nicht geändert werden.")
        self._update_key_info()
        if self.cfg.privacy_ack != COMPANION_VERSION:
            messagebox.showinfo(APP_NAME, "Gespeichert. Bitte noch im Reiter 'Datenschutz' die Erklärung bestätigen.")
            self.nb.select(2)
        else:
            messagebox.showinfo(APP_NAME, "Gespeichert.")
        self.worker.wake_event.set()
        self.refresh_status()

    def _delete_key(self):
        if messagebox.askyesno(APP_NAME, "Gespeicherten API-Schlüssel wirklich löschen?"):
            self.cfg.api_key_blob = ""
            self.cfg.save()
            self._update_key_info()
            self.refresh_status()

    def refresh_status(self):
        if not (self.window and self.window.winfo_exists()):
            return
        if not self.cfg.privacy_ack == COMPANION_VERSION:
            s = "Bitte zuerst die Datenschutz-Erklärung lesen und bestätigen (Reiter Datenschutz)."
        elif not self.cfg.api_key_blob:
            s = "Bitte unter Einstellungen den API-Schlüssel eintragen."
        else:
            s = self.worker.status
        self.status_var.set(s)

    def refresh_log(self):
        if not (self.window and self.window.winfo_exists()):
            return
        self.tree.delete(*self.tree.get_children())
        names = {"translate": "Übersetzen", "quest": "Quest", "talents": "Talente"}
        for e in reversed(self.worker.log):
            self.tree.insert("", "end", values=(
                time.strftime("%d.%m. %H:%M", time.localtime(e.get("time", 0))),
                names.get(e.get("kind"), e.get("kind")),
                e.get("summary", ""),
                f"{e.get('tokens_in', 0)} / {e.get('tokens_out', 0)}",
                ("Fehler: " + e["error"]) if e.get("error") else "OK",
            ))


def single_instance() -> bool:
    handle = ctypes.windll.kernel32.CreateMutexW(None, False, "Local\\ChatDECompanionMutex")
    globals()["_mutex_handle"] = handle
    return ctypes.windll.kernel32.GetLastError() != 183  # ERROR_ALREADY_EXISTS


def main():
    if not single_instance():
        r = tk.Tk()
        r.withdraw()
        messagebox.showinfo(APP_NAME, "Der Chat DE Companion läuft bereits (Symbol neben der Uhr).")
        r.destroy()
        return
    try:
        App().run()
    except Exception as e:
        fatal(f"Unerwarteter Fehler: {e!r}")


if __name__ == "__main__":
    main()
