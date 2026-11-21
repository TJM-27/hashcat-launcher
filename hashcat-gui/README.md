# Hashcat launcher

A small Windows window for [hashcat](https://hashcat.net/) 6.2.5. Paste hashes or pick a hash file, choose an attack, and run it. Hashcat is included in this folder. Nothing else has to be installed.

## Open it

Double-click **Hashcat Launcher.exe**.

`Hashcat Launcher.cmd` starts that same exe. If the exe is missing, the cmd file runs `hashcat_gui.ps1` with the Windows PowerShell that is already on Windows 10 and 11.

## Take it to another PC

Copy this whole folder. The exe looks next to itself for:

- `hashcat_gui.ps1` — the window logic
- `hashcat-6.2.5\` — hashcat and its kernels, rules, and OpenCL files
- `icons\` — the window icon

The exe on its own will not find hashcat. The folder is about 250 MB because hashcat is in it.

Windows 10 or 11 is enough. The exe uses the .NET Framework and Windows PowerShell that come with Windows. Python is not required.

## What you fill in

| Field | What it does |
|---|---|
| Paste hashes / Load from file | One hash per line, or a text file of hashes. Pasted hashes are written to a temp file for that run and deleted when the run ends. |
| Wordlist file | The dictionary for straight, combination, hybrid, and association attacks. Hidden for brute-force. Combination asks for a left and a right wordlist. |
| Hash mode (`-m`) | Hash type. The list starts at NetNTLMv2. You can type any other hashcat mode number. The **Hash mode** link opens the hashcat example-hash list. |
| Attack (`-a`) | Which attack to run. Extra boxes appear for the mode you pick. |
| Mask | Brute-force and both hybrids. A mask such as `?a?a?a?a?a?a`, or a `.hcmask` file. |
| `?1` to `?4` | Custom charsets, only needed when the mask uses those tokens. Example: `?1` = `?l?d` and mask `?1?1?1?1`. |
| Increment (`-i`) | Brute-force and hybrids. Tries the mask from the minimum length up to the maximum. |
| Rules file (`-r`) | Optional. Shown for association. Browse opens `hashcat-6.2.5\rules`. |
| Device(s) (`-d`) | Optional. Blank uses every device hashcat detects. Numbers come from `hashcat -I`. |
| Hashcat executable | Defaults to `hashcat-6.2.5\hashcat.exe` in this folder. |

**Run hashcat** starts the job and streams its output into the window. **Stop** ends that hashcat process.

When hashcat exits with code 0, the launcher runs `hashcat -m <mode> --show` on the same hash file and appends any recovered lines. Hashcat also records cracks in `hashcat-6.2.5\hashcat.potfile`.

## Command it runs

The working directory is the folder that contains `hashcat.exe`, so hashcat can see its kernels. The attack you pick changes the end of the command:

| Attack | Command shape |
|---|---|
| 0 Straight | `hashcat.exe -a 0 -m <mode> <hash file> <wordlist>` |
| 1 Combination | `hashcat.exe -a 1 -m <mode> <hash file> <left wordlist> <right wordlist>` |
| 3 Brute-force | `hashcat.exe -a 3 -m <mode> [-1 <charset>] [-i] <hash file> <mask>` |
| 6 Hybrid wordlist + mask | `hashcat.exe -a 6 -m <mode> <hash file> <wordlist> <mask>` |
| 7 Hybrid mask + wordlist | `hashcat.exe -a 7 -m <mode> <hash file> <mask> <wordlist>` |
| 9 Association | `hashcat.exe -a 9 -m <mode> [-r <rules>] <hash file> <wordlist>` |

Built-in mask tokens are `?l` lowercase, `?u` uppercase, `?d` digits, `?h` lower hex, `?H` upper hex, `?s` symbols, `?a` all printable, and `?b` every byte. `?1` through `?4` use the custom charset boxes.

## Device field

The box is passed as `-d`, which selects backend devices by the numbers from `hashcat -I` (often `1` is the first GPU). It is not “1 = CPU, 2 = GPU.” Those numbers belong to hashcat’s `-D` option, and this window does not send `-D`.

## Options still not on the form

Workload profile (`-w`), optimized kernels (`-O`), single rules (`-j`, `-k`), `--username`, outfile (`-o`), potfile path, session restore, and `--runtime`. A rules file (`-r`) is available for association attacks. The rule files that ship with hashcat are in `hashcat-6.2.5\rules\`.

Preset hash modes in the dropdown:

| Mode | Name |
|---|---|
| 5600 | NetNTLMv2 |
| 1000 | NTLM |
| 0 | MD5 |
| 100 | SHA1 |
| 1400 | SHA2-256 |
| 1700 | SHA2-512 |
| 22000 | WPA-PBKDF2-PMKID+EAPOL |
| 12500 | RAR3-hp |
| 13000 | RAR5 |

## Files

| File | Role |
|---|---|
| `Hashcat Launcher.exe` | The program to open. |
| `Hashcat Launcher.cmd` | Starts the exe, or the script if the exe is gone. |
| `hashcat_gui.ps1` | Source for the window. |
| `HashcatLauncher.cs` | Small exe wrapper that starts `hashcat_gui.ps1`. |
| `Build-HashcatLauncher.ps1` | Rebuilds the exe wrapper. Only needed if you change `HashcatLauncher.cs`. |
| `hashcat-6.2.5\` | Bundled hashcat. |
| `icons\` | Window and header icon. |
| `hashcat_gui.py` | Older Python version of a similar window. The exe is the one to use. |

## Rebuild the exe

From this folder, in PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-HashcatLauncher.ps1
```

That writes `Hashcat Launcher.exe` here. The exe is only a small wrapper; it loads `hashcat_gui.ps1` from the same folder when you open it.
