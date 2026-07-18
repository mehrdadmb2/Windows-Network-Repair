# Windows Network Repair

<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg" alt="PowerShell 5.1+">
  <img src="https://img.shields.io/badge/Windows-10%2F11-green.svg" alt="Windows 10/11">
  <img src="https://img.shields.io/badge/license-MIT-brightgreen.svg" alt="License MIT">
  <img src="https://img.shields.io/github/last-commit/mehrdadmb2/Windows-Network-Repair" alt="Last Commit">
</p>

<p align="center">
  A professional PowerShell utility to diagnose and repair common Windows network sharing, SMB, and discovery issues.<br>
  Built with safety in mind — automatic backup, interactive menu, and step‑by‑step fixes.
</p>

---

## ✨ Features

- ✅ **Interactive menu** – simple numbered choices for every task
- 🔍 **Full diagnostic scan** – checks firewall rules, services, SMB signing, guest authentication, network adapters
- 🛠️ **Targeted repairs**
  - Enable Network Discovery and File Sharing firewall rules
  - Disable SMB signing (RequiredSecuritySignature)
  - Enable insecure guest logons (AllowInsecureGuestAuth)
  - Disable "Client for Microsoft Networks" on all NICs
  - Enable SMB 1.0 / CIFS support
- 💾 **Registry backup & restore** – every critical change is backed up to `.reg` files before modification
- ♻️ **Undo all changes** – one-click rollback of all settings applied by the tool
- 📝 **Detailed logging** – all actions are logged with timestamps in the `Logs\` folder
- 📊 **Report generation** – exports current service status and registry settings to a text file
- 🧰 **Modular design** – separate PowerShell modules for services, registry, SMB, firewall, and logging
- 🔐 **Administrator detection** – refuses to run without elevated privileges

---

## 📂 Repository Structure

```
Windows-Network-Repair/
│
├── NetworkRepair.cmd        # Batch launcher (requests admin if needed)
├── NetworkRepair.ps1         # Main menu & orchestration script
├── Restore.ps1               # Quick restore from latest backup
│
├── Modules/
│   ├── Logger.psm1           # Log file management
│   ├── Registry.psm1         # Registry tweaks (SMB signing, guest auth)
│   ├── Services.psm1         # Windows optional features (SMB1)
│   ├── SMB.psm1              # Network adapter bindings
│   └── Firewall.psm1         # Firewall rule toggles
│
├── Backup/                   # Registry backups (.reg) – created automatically
├── Logs/                     # Session logs and generated reports
└── README.md
```

---

## 🚀 Quick Start

1. **Download** the repository as a ZIP or clone it:
   ```bash
   git clone https://github.com/mehrdadmb2/Windows-Network-Repair.git
   ```
2. **Right-click** on `NetworkRepair.cmd` and select **Run as administrator**.
3. Use the interactive menu to check your configuration or apply fixes.

> **No installation required** – just unzip and run.

---

## 🖥️ Usage

When you launch the tool, you’ll see the main menu:

```
==========================================================
        Windows Network / SMB Repair Utility v2.0
==========================================================

[1] Check Current Configuration
[2] Apply Recommended Fixes (Step by Step)
[3] Enable SMB 1.0 / CIFS File Sharing Support
[4] Disable SMB Signing
[5] Enable Insecure Guest Logons
[6] Disable Client for Microsoft Networks (on all NICs)
[7] Backup Current Settings
[8] Restore Previous Settings
[9] Undo All Changes
[10] Generate Report
[0] Exit
```

### Example workflow

1. Start with **Option 1** – see what’s broken.
2. Run **Option 7** – create a safety backup.
3. Choose the fixes you need (2, 3, 4, 5, 6).
4. If something goes wrong, use **Option 9** (Undo) or **Option 8** (Restore).
5. Generate a report with **Option 10** to share with support.

---

## 🛡️ Safety & Security

This tool modifies system settings that can **weaken security** (disabling SMB signing, enabling guest access).  
To keep you in control:

- Every registry change is **backed up** automatically before modification.
- All actions are **confirmed interactively** – nothing is changed silently.
- A **full undo** option restores settings to their previous state.
- The tool is intended for **home networks, legacy device access, or isolated labs** – not for production environments where security hardening is required.

---

## 📋 Requirements

- **Windows 10 / Windows 11** (all editions, though Group Policy features are not included by default for Home)
- **PowerShell 5.1** (pre-installed on Windows 10/11)
- **Administrator privileges**

---

## 🤝 Contributing

Contributions are welcome!  
Feel free to open an issue or submit a pull request if you have ideas for improvements or additional repair modules.

1. Fork the repository.
2. Create your feature branch (`git checkout -b feature/amazing-feature`).
3. Commit your changes.
4. Push to the branch.
5. Open a pull request.

---

## 📄 License

This project is licensed under the MIT License – see the [LICENSE](LICENSE) file for details.

---

## 📧 Contact

Created by [Mehrdad](https://github.com/mehrdadmb2)  
Repository: [https://github.com/mehrdadmb2/Windows-Network-Repair](https://github.com/mehrdadmb2/Windows-Network-Repair)

---

⭐ If this tool helped you, please consider starring the repository!
```

**Notes for you:**  
- If you don’t have a `LICENSE` file yet, add one (e.g., MIT) to the root – GitHub can generate it for you.  
- You can replace the placeholder contact name “Mehrdad” with your own info.  
- The badges at the top will automatically reflect the last commit date once the repo is active.  
- Keep the `Backup/` and `Logs/` folders in the repo but leave them empty (add a `.gitkeep` file inside each if you want them tracked).
