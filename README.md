# logi-switch

Switch a Logitech **MX Keys** keyboard and **MX Master** mouse to the same
Easy-Switch channel (1, 2 or 3) with one command, so you never have to flip
the mouse over to press its channel button.

- `logi-switch.ps1`: Windows, PowerShell only. Nothing to install.
- `logi_switch.py`: macOS (also works on Linux and Windows) with Python and `hidapi`.

Both scripts do the same thing. They send the device the HID++ "change host"
command (feature `0x1814`), which is what the Easy-Switch buttons trigger.

> A device only accepts the command from the computer it is currently
> connected to, so each computer needs the script to send the devices
> *away* from itself.

Supported devices (Bluetooth): MX Keys, MX Master 3, MX Master 3S.
To add another model, put its Bluetooth product ID in the device list near
the top of the script.

---

## Windows setup (step by step)

1. **Check that PowerShell allows this.** Open PowerShell (Start menu, type
   `PowerShell`) and run:
   ```powershell
   $ExecutionContext.SessionState.LanguageMode
   ```
   It must print `FullLanguage`. If it says `ConstrainedLanguage`, the script
   can't run on this machine.

2. **Download the script.** In the same PowerShell window:
   ```powershell
   Invoke-WebRequest -Uri https://raw.githubusercontent.com/btaner/logi-switch/main/logi-switch.ps1 -OutFile $HOME\logi-switch.ps1
   ```
   (Or open `logi-switch.ps1` on GitHub, click **Download raw file**, and
   save it in your user folder, `C:\Users\<you>\`.)

3. **Unblock it.** Windows marks downloaded files as untrusted:
   ```powershell
   Unblock-File $HOME\logi-switch.ps1
   ```

4. **Test it without switching anything.** With the keyboard and mouse
   connected to this PC, run:
   ```powershell
   & $HOME\logi-switch.ps1 -Status
   ```
   You should see both devices and their current channel, for example:
   ```
   MX Keys: on channel 1 of 3
   MX Master 3S: on channel 1 of 3
   ```
   If PowerShell says *running scripts is disabled on this system*, your
   execution policy blocks scripts. On a work computer, ask IT rather than
   bypassing it.

5. **Switch.** Send both devices to channel 2:
   ```powershell
   & $HOME\logi-switch.ps1 2
   ```

6. **Optional: a keyboard shortcut.**
   1. Right-click the desktop, then choose **New > Shortcut**.
   2. Enter this as the location (change the channel number at the end if needed):
      ```
      powershell.exe -NoProfile -WindowStyle Hidden -File "%USERPROFILE%\logi-switch.ps1" 2
      ```
   3. Name it something like `Switch to Mac` and click **Finish**.
   4. Right-click the new shortcut and choose **Properties**. Click in
      **Shortcut key** and press a combination, e.g. `Ctrl+Alt+M`. Click **OK**.

   Pressing that combination now switches both devices. A PowerShell window
   flashes briefly when you use it.

---

## macOS setup (step by step)

Needs Python 3 (for example from [Homebrew](https://brew.sh): `brew install python`).

1. **Download the script** into a folder of its own:
   ```bash
   mkdir -p ~/logi-switch
   curl -L -o ~/logi-switch/logi_switch.py https://raw.githubusercontent.com/btaner/logi-switch/main/logi_switch.py
   ```

2. **Create a Python environment and install `hidapi`:**
   ```bash
   python3 -m venv ~/logi-switch/.venv
   ~/logi-switch/.venv/bin/pip install hidapi
   ```

3. **Test it without switching anything:**
   ```bash
   ~/logi-switch/.venv/bin/python ~/logi-switch/logi_switch.py --status
   ```
   If the devices can't be opened, give your terminal app Input Monitoring
   access in **System Settings > Privacy & Security > Input Monitoring**.

4. **Switch.** Send both devices to channel 1:
   ```bash
   ~/logi-switch/.venv/bin/python ~/logi-switch/logi_switch.py 1
   ```

5. **Optional: a short alias.** Add it to your shell config:
   ```bash
   echo "alias kvm='~/logi-switch/.venv/bin/python ~/logi-switch/logi_switch.py'" >> ~/.zshrc
   source ~/.zshrc
   ```
   Now `kvm 1`, `kvm 2`, `kvm 3` and `kvm --status` work.

---

## Typical two-computer setup

| Channel | Computer |
|---------|----------|
| 1       | Windows  |
| 2       | Mac      |

- On the Mac, `kvm 1` sends both devices to Windows.
- On Windows, the `Ctrl+Alt+M` shortcut (or `logi-switch.ps1 2`) sends both back to the Mac.
- The keyboard's Easy-Switch keys keep working as usual.

## Troubleshooting

- **"No MX Keys / MX Master connected"**: the devices must be connected
  to *this* computer over Bluetooth. A Logi Bolt / Unifying USB receiver is
  not supported.
- **One device switches and the other doesn't**: run the status check to see
  which device reports an error, then check it is paired on the target
  channel.
- **Logi Options+**: running it at the same time is fine.
