#!/usr/bin/env python3
"""
Hashcat GUI launcher (Tkinter).
- Paste hashes or load from file
- Select wordlist
- Pick hash mode from dropdown (or type custom mode)
- Optional attack mode/devices
- Runs hashcat and streams output
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import threading
import tkinter as tk
import webbrowser
from tkinter import filedialog, messagebox, scrolledtext, ttk

HASH_MODE_OPTIONS = [
    "5600 (NetNTLMv2)",
    "1000 (NTLM)",
    "0 (MD5)",
    "100 (SHA1)",
    "1400 (SHA2-256)",
    "1700 (SHA2-512)",
    "22000 (WPA-PBKDF2-PMKID+EAPOL)",
    "12500 (RAR3-hp)",
    "13000 (RAR5)",
]


def default_hashcat_cmd() -> str:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    if sys.platform == "win32":
        candidates = [
            os.path.join(script_dir, "hashcat-6.2.5", "hashcat.exe"),
            os.path.join(script_dir, "hashcat.exe"),
        ]
        for c in candidates:
            if os.path.isfile(c):
                return c
        return "hashcat.exe"
    candidates = [
        os.path.join(script_dir, "hashcat-6.2.5", "hashcat"),
        os.path.join(script_dir, "hashcat"),
    ]
    for c in candidates:
        if os.path.isfile(c):
            return c
    return "hashcat"


def apply_tk_window_icon(root: tk.Misc) -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidates = [
        os.path.join(script_dir, "hashcat_gui_cat_icon.png"),
        os.path.join(script_dir, "icons", "hashcat_gui_cat_icon.png"),
    ]
    path = ""
    for candidate in candidates:
        if os.path.isfile(candidate):
            path = candidate
            break
    if not path:
        return
    try:
        from PIL import Image, ImageTk

        pil_img = Image.open(path).convert("RGBA")
        w, h = pil_img.size
        side = max(w, h, 1)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.paste(pil_img, ((side - w) // 2, (side - h) // 2), pil_img)
        sq.thumbnail((64, 64), Image.Resampling.LANCZOS)
        img = ImageTk.PhotoImage(sq, master=root)
        root.iconphoto(True, img)
        setattr(root, "_app_icon_photo", img)
        return
    except Exception:
        pass
    try:
        img = tk.PhotoImage(file=path)
        root.iconphoto(True, img)
        setattr(root, "_app_icon_photo", img)
    except tk.TclError:
        return


class HashcatGuiApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Hashcat launcher")
        self.minsize(680, 560)
        self.geometry("780x640")
        apply_tk_window_icon(self)

        self._proc: subprocess.Popen[str] | None = None
        self._reader_thread: threading.Thread | None = None
        self._hash_path_is_temp = False
        self._hash_path = ""

        main = ttk.Frame(self, padding=12)
        main.pack(fill=tk.BOTH, expand=True)

        src_lf = ttk.LabelFrame(main, text="Hash input source", padding=8)
        src_lf.grid(row=0, column=0, columnspan=3, sticky=tk.EW, pady=(0, 8))

        self.hash_source = tk.StringVar(value="paste")
        rb_fr = ttk.Frame(src_lf)
        rb_fr.pack(fill=tk.X)
        ttk.Radiobutton(
            rb_fr,
            text="Paste hash(es) in the box below",
            variable=self.hash_source,
            value="paste",
            command=self._sync_hash_input_widgets,
        ).pack(side=tk.LEFT)
        ttk.Radiobutton(
            rb_fr,
            text="Load hash(es) from file",
            variable=self.hash_source,
            value="file",
            command=self._sync_hash_input_widgets,
        ).pack(side=tk.LEFT, padx=(20, 0))

        file_row = ttk.Frame(src_lf)
        file_row.pack(fill=tk.X, pady=(8, 0))
        ttk.Label(file_row, text="Hash file:").pack(side=tk.LEFT)
        self.hash_file_var = tk.StringVar()
        self.hash_file_entry = ttk.Entry(file_row, textvariable=self.hash_file_var, width=55)
        self.hash_file_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(8, 8))
        self.hash_file_browse = ttk.Button(file_row, text="Browse...", command=self._browse_hash_file)
        self.hash_file_browse.pack(side=tk.LEFT)

        ttk.Label(main, text='Hash(es) - one per line (when "Paste" is selected):').grid(
            row=1, column=0, sticky=tk.W
        )
        self.hash_text = scrolledtext.ScrolledText(main, height=5, wrap=tk.WORD)
        self.hash_text.grid(row=2, column=0, columnspan=3, sticky=tk.NSEW, pady=(4, 8))

        ttk.Label(main, text="Wordlist file:").grid(row=3, column=0, sticky=tk.W)
        self.wordlist_var = tk.StringVar()
        ttk.Entry(main, textvariable=self.wordlist_var, width=50).grid(
            row=4, column=0, columnspan=2, sticky=tk.EW, pady=(0, 8)
        )
        ttk.Button(main, text="Browse...", command=self._browse_wordlist).grid(
            row=4, column=2, sticky=tk.E, padx=(8, 0), pady=(0, 8)
        )

        opts = ttk.Frame(main)
        opts.grid(row=5, column=0, columnspan=3, sticky=tk.EW, pady=(0, 8))

        mode_link = tk.Label(opts, text="Hash mode (-m):", fg="#0066cc", cursor="hand2")
        mode_link.bind("<Button-1>", self._open_hash_mode_help)
        mode_link.pack(side=tk.LEFT)

        self.mode_var = tk.StringVar(value=HASH_MODE_OPTIONS[0])
        self.mode_combo = ttk.Combobox(
            opts, textvariable=self.mode_var, values=HASH_MODE_OPTIONS, width=34
        )
        self.mode_combo.pack(side=tk.LEFT, padx=(6, 16))

        attack_link = tk.Label(opts, text="Attack (-a), 0 = wordlist:", fg="#0066cc", cursor="hand2")
        attack_link.bind("<Button-1>", self._open_attack_help)
        attack_link.pack(side=tk.LEFT)
        self.attack_var = tk.StringVar(value="0")
        ttk.Entry(opts, textvariable=self.attack_var, width=6).pack(side=tk.LEFT, padx=(6, 0))
        self.optimize_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(opts, text="Optimize kernels", variable=self.optimize_var).pack(
            side=tk.LEFT, padx=(12, 0)
        )

        dev_row = ttk.Frame(main)
        dev_row.grid(row=6, column=0, columnspan=3, sticky=tk.EW, pady=(0, 8))
        ttk.Label(
            dev_row,
            text="Device(s) (-d), optional - 1 = CPU only, 2 = GPU only, blank uses both:",
        ).pack(side=tk.LEFT)
        self.devices_var = tk.StringVar()
        ttk.Entry(dev_row, textvariable=self.devices_var, width=14).pack(side=tk.LEFT, padx=(8, 0))

        ttk.Label(main, text="Hashcat executable (optional if on PATH):").grid(
            row=7, column=0, columnspan=3, sticky=tk.W
        )
        self.exe_var = tk.StringVar(value=default_hashcat_cmd())
        ttk.Entry(main, textvariable=self.exe_var, width=50).grid(
            row=8, column=0, columnspan=2, sticky=tk.EW, pady=(4, 8)
        )
        ttk.Button(main, text="Browse...", command=self._browse_exe).grid(
            row=8, column=2, sticky=tk.E, padx=(8, 0), pady=(4, 8)
        )

        btn_row = ttk.Frame(main)
        btn_row.grid(row=9, column=0, columnspan=3, sticky=tk.W, pady=(0, 8))
        self.run_btn = ttk.Button(btn_row, text="Run hashcat", command=self._run)
        self.run_btn.pack(side=tk.LEFT, padx=(0, 8))
        self.stop_btn = ttk.Button(btn_row, text="Stop", command=self._stop, state=tk.DISABLED)
        self.stop_btn.pack(side=tk.LEFT)

        ttk.Label(main, text="Output:").grid(row=10, column=0, sticky=tk.W)
        self.out_text = scrolledtext.ScrolledText(main, height=12, wrap=tk.WORD, state=tk.DISABLED)
        self.out_text.grid(row=11, column=0, columnspan=3, sticky=tk.NSEW)

        main.rowconfigure(2, weight=0)
        main.rowconfigure(11, weight=1)
        main.columnconfigure(0, weight=1)

        self._sync_hash_input_widgets()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _sync_hash_input_widgets(self) -> None:
        use_file = self.hash_source.get() == "file"
        self.hash_text.configure(state=tk.DISABLED if use_file else tk.NORMAL)
        self.hash_file_entry.configure(state=tk.NORMAL if use_file else tk.DISABLED)
        self.hash_file_browse.configure(state=tk.NORMAL if use_file else tk.DISABLED)

    def _browse_hash_file(self) -> None:
        path = filedialog.askopenfilename(
            title="Select hash file",
            filetypes=[("Text / hashes", "*.txt;*.hash;*.*"), ("All files", "*.*")],
        )
        if path:
            self.hash_file_var.set(path)

    def _browse_wordlist(self) -> None:
        path = filedialog.askopenfilename(
            title="Select wordlist",
            filetypes=[("Text / all", "*.txt;*.*"), ("All files", "*.*")],
        )
        if path:
            self.wordlist_var.set(path)

    def _browse_exe(self) -> None:
        path = filedialog.askopenfilename(
            title="Select hashcat executable",
            filetypes=[("Executable", "*.exe"), ("All files", "*.*")],
        )
        if path:
            self.exe_var.set(path)

    def _append_output(self, text: str) -> None:
        def _do() -> None:
            self.out_text.configure(state=tk.NORMAL)
            self.out_text.insert(tk.END, text)
            self.out_text.see(tk.END)
            self.out_text.configure(state=tk.DISABLED)

        self.after(0, _do)

    def _set_running(self, running: bool) -> None:
        def _do() -> None:
            self.run_btn.configure(state=tk.DISABLED if running else tk.NORMAL)
            self.stop_btn.configure(state=tk.NORMAL if running else tk.DISABLED)

        self.after(0, _do)

    def _open_hash_mode_help(self, _event: tk.Event[tk.Misc]) -> None:
        webbrowser.open("https://hashcat.net/wiki/doku.php?id=example_hashes", new=2)

    def _open_attack_help(self, _event: tk.Event[tk.Misc]) -> None:
        webbrowser.open("https://hashcat.net/wiki/", new=2)

    @staticmethod
    def _parse_mode_value(mode_text: str) -> str:
        mode_text = mode_text.strip()
        if not mode_text:
            return ""
        return mode_text.split(" ", 1)[0]

    def _show_recovered(self, exe_abs: str, mode: str, hash_path: str, hc_cwd: str) -> None:
        show_cmd = [exe_abs, "-m", mode, "--show", hash_path]
        creation = 0
        if sys.platform == "win32":
            creation = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        try:
            result = subprocess.run(
                show_cmd,
                cwd=hc_cwd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                creationflags=creation,
                check=False,
            )
        except OSError as e:
            self._append_output(f"\n[show error] Could not run --show: {e}\n")
            return

        lines = [ln for ln in result.stdout.splitlines() if ln.strip()]
        if lines:
            self._append_output("\nRecovered password(s):\n")
            for ln in lines:
                self._append_output(ln + "\n")
            self._append_output("\n")

    def _run(self) -> None:
        if self._proc is not None and self._proc.poll() is None:
            messagebox.showinfo("Busy", "Hashcat is already running.")
            return

        use_file = self.hash_source.get() == "file"
        hash_path: str
        self._hash_path_is_temp = False

        if use_file:
            hf = self.hash_file_var.get().strip()
            if not hf or not os.path.isfile(hf):
                messagebox.showerror("Hash file", 'Choose a valid hash file, or switch to "Paste" mode.')
                return
            hash_path = os.path.normpath(os.path.abspath(hf))
        else:
            raw = self.hash_text.get("1.0", tk.END).strip()
            if not raw:
                messagebox.showerror("Missing hash", "Enter at least one hash, or use a hash file.")
                return
            fd, hash_path = tempfile.mkstemp(prefix="hc_gui_", suffix=".txt", text=True)
            self._hash_path_is_temp = True
            try:
                with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
                    for line in raw.splitlines():
                        line = line.strip()
                        if line:
                            f.write(line + "\n")
            except OSError as e:
                messagebox.showerror("Error", f"Could not write hash file: {e}")
                try:
                    os.unlink(hash_path)
                except OSError:
                    pass
                return

        wordlist = self.wordlist_var.get().strip()
        if not wordlist or not os.path.isfile(wordlist):
            messagebox.showerror("Wordlist", "Choose a valid wordlist file.")
            if self._hash_path_is_temp:
                try:
                    os.unlink(hash_path)
                except OSError:
                    pass
            return

        mode = self._parse_mode_value(self.mode_var.get())
        if not mode.isdigit():
            messagebox.showerror("Mode", "Hash mode (-m) must be a number (see hashcat --help).")
            if self._hash_path_is_temp:
                try:
                    os.unlink(hash_path)
                except OSError:
                    pass
            return

        attack = self.attack_var.get().strip()
        if not attack.isdigit():
            messagebox.showerror("Attack", "Attack mode (-a) must be a number.")
            if self._hash_path_is_temp:
                try:
                    os.unlink(hash_path)
                except OSError:
                    pass
            return

        devices_raw = self.devices_var.get().strip()
        devices_arg = ""
        if devices_raw:
            parts = [p.strip() for p in devices_raw.split(",") if p.strip()]
            if not parts or not all(p.isdigit() for p in parts):
                messagebox.showerror(
                    "Devices",
                    "Device list must be comma-separated numbers (e.g. 1 or 1,3).",
                )
                if self._hash_path_is_temp:
                    try:
                        os.unlink(hash_path)
                    except OSError:
                        pass
                return
            devices_arg = ",".join(parts)

        exe = self.exe_var.get().strip()
        if not exe:
            messagebox.showerror("Executable", "Set the path to hashcat or leave the default if it is on PATH.")
            if self._hash_path_is_temp:
                try:
                    os.unlink(hash_path)
                except OSError:
                    pass
            return

        if not shutil.which(exe) and not os.path.isfile(exe):
            messagebox.showerror("Executable", f"Cannot find hashcat: {exe}")
            if self._hash_path_is_temp:
                try:
                    os.unlink(hash_path)
                except OSError:
                    pass
            return

        if os.path.isfile(exe):
            exe_abs = os.path.normpath(os.path.abspath(exe))
        else:
            which = shutil.which(exe)
            exe_abs = os.path.normpath(os.path.abspath(which)) if which else exe
        hc_cwd = os.path.dirname(exe_abs)

        self.out_text.configure(state=tk.NORMAL)
        self.out_text.delete("1.0", tk.END)
        self.out_text.configure(state=tk.DISABLED)

        cmd = [exe_abs, "-a", attack, "-m", mode]
        if self.optimize_var.get():
            cmd.append("-O")
        if devices_arg:
            cmd.extend(["-D", devices_arg])
        cmd.extend([hash_path, wordlist])
        self._append_output("Command: " + subprocess.list2cmdline(cmd) + "\n")
        self._append_output(f"Working directory: {hc_cwd}\n\n")

        creation = 0
        if sys.platform == "win32":
            creation = getattr(subprocess, "CREATE_NO_WINDOW", 0)

        try:
            self._proc = subprocess.Popen(
                cmd,
                cwd=hc_cwd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                bufsize=1,
                creationflags=creation,
            )
        except OSError as e:
            self._append_output(f"Failed to start hashcat: {e}\n")
            if self._hash_path_is_temp:
                try:
                    os.unlink(hash_path)
                except OSError:
                    pass
            self._proc = None
            return

        self._hash_path = hash_path
        self._set_running(True)

        def reader() -> None:
            assert self._proc is not None and self._proc.stdout is not None
            is_temp = self._hash_path_is_temp
            hp = self._hash_path
            try:
                for line in self._proc.stdout:
                    self._append_output(line)
            except Exception as ex:
                self._append_output(f"\n[read error] {ex}\n")
            code = self._proc.wait()
            if code == 0:
                self._show_recovered(exe_abs, mode, hp, hc_cwd)
            self._append_output(f"\n--- Exit code: {code} ---\n")
            if is_temp:
                try:
                    os.unlink(hp)
                except OSError:
                    pass
            self._hash_path = ""
            self._hash_path_is_temp = False
            self._proc = None
            self._set_running(False)

        self._reader_thread = threading.Thread(target=reader, daemon=True)
        self._reader_thread.start()

    def _stop(self) -> None:
        if self._proc is None or self._proc.poll() is not None:
            return
        try:
            self._proc.terminate()
        except OSError:
            pass

    def _on_close(self) -> None:
        self._stop()
        self.destroy()


def main() -> None:
    app = HashcatGuiApp()
    app.mainloop()


if __name__ == "__main__":
    main()
