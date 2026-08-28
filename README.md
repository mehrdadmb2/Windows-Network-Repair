# Windows Network Repair

<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell">
  <img src="https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows&logoColor=white" alt="Windows">
  <img src="https://img.shields.io/github/license/mehrdadmb2/Windows-Network-Repair?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/github/stars/mehrdadmb2/Windows-Network-Repair?style=for-the-badge" alt="Stars">
  <img src="https://img.shields.io/github/last-commit/mehrdadmb2/Windows-Network-Repair?style=for-the-badge" alt="Last Commit">
</p>

<p align="center">
  <strong>A professional PowerShell-based utility for diagnosing, repairing, and managing common Windows networking, SMB, and file-sharing issues.</strong>
</p>

<p align="center">
  Backup • Restore • Diagnostics • SMB Management • Firewall • Network Discovery • Logging
</p>

---

## 📖 Overview

**Windows Network Repair** is a modular Windows troubleshooting and repair utility designed to simplify the diagnosis and repair of common networking, file-sharing, SMB, and network-discovery problems.

Instead of manually navigating through Windows settings, Group Policy, Registry Editor, Services, and Windows Firewall, this project provides a centralized interactive console for checking system configuration and performing targeted repairs.

The tool is especially useful for:

* Home networks
* Windows-to-Windows file sharing
* Legacy NAS devices
* Older network storage systems
* Printers and devices using SMB
* Network discovery problems
* SMB compatibility troubleshooting
* Lab and testing environments
* IT troubleshooting and system administration

> ⚠️ **Important:** Some SMB compatibility options can reduce Windows security. Only enable security-sensitive options when they are actually required and when you understand the associated risks.

---

## ✨ Features

### 🔍 Diagnostics

The utility can inspect important Windows networking components, including:

* Network Discovery firewall rules
* File and Printer Sharing firewall rules
* Windows network services
* SMB configuration
* SMB signing configuration
* Guest authentication configuration
* Network adapter bindings
* Registry configuration
* Windows optional SMB features

The diagnostic mode helps identify which components are currently enabled, disabled, missing, or potentially misconfigured.

---

### 🛠️ Network Repair

The project provides targeted repair actions for common networking problems.

Supported operations include:

* Enable Network Discovery
* Enable File and Printer Sharing
* Enable SMB 1.0 / CIFS support
* Configure SMB signing
* Configure SMB guest authentication
* Manage Client for Microsoft Networks
* Restart or inspect required Windows services
* Repair firewall configuration

Each operation is designed to be performed explicitly rather than silently modifying the system.

---

### 💾 Backup & Restore

Before modifying important registry-based SMB settings, the tool can create backups.

Backups are stored inside:

```text
Backup/
```

Example:

```text
Backup/
└── RegistryBackup_20260828_181530.reg
```

This makes it possible to restore previously saved configuration when necessary.

---

### ♻️ Undo / Rollback

The project includes rollback functionality for changes performed by the repair utility.

This allows you to return important networking settings to a safer/default configuration instead of manually reversing every modification.

---

### 📝 Logging

Every important operation can be written to a timestamped log file.

Logs are stored in:

```text
Logs/
```

Example:

```text
Logs/
└── NetworkRepair_20260828_181530.log
```

This makes troubleshooting easier and provides a history of what the utility performed.

---

### 📊 System Reports

The utility can generate a readable diagnostic report containing information such as:

* Windows network services
* SMB configuration
* Registry values
* Network sharing configuration
* Firewall state

Generated reports are stored inside:

```text
Logs/
```

---

## 🖥️ Interactive Menu

When the application starts, it provides an interactive console menu:

```text
==========================================================
        Windows Network / SMB Repair Utility
==========================================================

[1] Check Current Configuration
[2] Apply Recommended Fixes
[3] Enable SMB 1.0 / CIFS
[4] Configure SMB Signing
[5] Configure Guest Authentication
[6] Configure Client for Microsoft Networks
[7] Backup Current Settings
[8] Restore Previous Settings
[9] Undo Changes
[10] Generate Report
[0] Exit

==========================================================
```

The menu-based architecture makes the tool easy to use without requiring the user to manually edit the Windows Registry or navigate through multiple administrative interfaces.

---

## 📁 Project Structure

```text
Windows-Network-Repair/
│
├── NetworkRepair.cmd
├── NetworkRepair.ps1
├── Restore.ps1
│
├── Modules/
│   ├── Logger.psm1
│   ├── Registry.psm1
│   ├── Services.psm1
│   ├── SMB.psm1
│   └── Firewall.psm1
│
├── Backup/
│
├── Logs/
│
└── README.md
```

### Core Files

| File                | Purpose                                           |
| ------------------- | ------------------------------------------------- |
| `NetworkRepair.cmd` | Launches the application with elevated privileges |
| `NetworkRepair.ps1` | Main application and interactive menu             |
| `Restore.ps1`       | Quick restoration utility                         |
| `Logger.psm1`       | Logging functionality                             |
| `Registry.psm1`     | Registry and SMB configuration                    |
| `Services.psm1`     | Windows service and optional feature management   |
| `SMB.psm1`          | SMB/network adapter configuration                 |
| `Firewall.psm1`     | Windows Firewall configuration                    |
| `Backup/`           | Registry and configuration backups                |
| `Logs/`             | Logs and generated reports                        |

---

## 🚀 Installation

### Method 1 — Clone with Git

```bash
git clone https://github.com/mehrdadmb2/Windows-Network-Repair.git
cd Windows-Network-Repair
```

### Method 2 — Download ZIP

Download the repository from GitHub and extract it anywhere on your Windows computer.

Repository:

[Windows-Network-Repair](https://github.com/mehrdadmb2/Windows-Network-Repair)

---

## ▶️ Usage

1. Open the project directory.
2. Right-click `NetworkRepair.cmd`.
3. Select **Run as administrator**.
4. Review the current configuration using:

```text
[1] Check Current Configuration
```

5. Create a backup before making important changes:

```text
[7] Backup Current Settings
```

6. Apply only the repairs required for your environment.
7. Generate a report after troubleshooting if needed.

For example:

```text
Check Configuration
        ↓
Create Backup
        ↓
Apply Required Repair
        ↓
Verify Configuration
        ↓
Generate Report
        ↓
Restart Windows if required
```

---

## 🔐 Security Considerations

This project can manage low-level Windows networking configuration.

Some compatibility settings may reduce the security level of SMB communication, especially:

```text
SMB 1.0 / CIFS
Insecure Guest Authentication
Reduced SMB Signing Requirements
```

These options should **not** be enabled simply because they are available.

They are primarily useful when dealing with:

* Legacy devices
* Old NAS systems
* Older printers
* Legacy SMB implementations
* Controlled laboratory environments
* Isolated local networks

For modern environments, prefer:

* SMB 2/3
* Authenticated users
* Strong passwords
* SMB signing where appropriate
* Current Windows security defaults
* Proper firewall configuration

Never expose insecure SMB configurations directly to the public Internet.

---

## 🧰 Requirements

### Supported Operating Systems

* Windows 10
* Windows 11

### Software

* Windows PowerShell 5.1 or newer
* Administrator privileges

PowerShell 5.1 is already included with supported versions of Windows.

---

## 🧪 Recommended Workflow

For troubleshooting a Windows file-sharing problem, the recommended workflow is:

```text
1. Run Diagnostics
       ↓
2. Check Network Services
       ↓
3. Check Firewall Rules
       ↓
4. Check SMB Configuration
       ↓
5. Create Backup
       ↓
6. Apply Only Required Fix
       ↓
7. Re-check Configuration
       ↓
8. Restart Windows if necessary
       ↓
9. Test File Sharing
```

This minimizes unnecessary system modifications.

---

## 📋 Example Problems

This project can help investigate problems such as:

### Windows cannot discover another computer

Check:

```text
Network Discovery
Function Discovery services
Firewall rules
Network profile
SMB configuration
```

### Shared folder cannot be accessed

Check:

```text
File and Printer Sharing
LanmanWorkstation
LanmanServer
SMB configuration
Firewall
Authentication
```

### Legacy NAS cannot connect

Check:

```text
SMB compatibility
SMB 1.0
Guest authentication
SMB signing
```

> Legacy compatibility features should only be enabled when the target device genuinely requires them.

---

## 🏗️ Architecture

The project follows a modular PowerShell architecture.

```text
                  ┌──────────────────────┐
                  │   NetworkRepair.cmd  │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │  NetworkRepair.ps1   │
                  │     Main Engine      │
                  └──────────┬───────────┘
                             │
          ┌──────────────────┼──────────────────┐
          │                  │                  │
          ▼                  ▼                  ▼
   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
   │  Registry   │    │   Services  │    │     SMB     │
   │    Module   │    │    Module   │    │    Module   │
   └─────────────┘    └─────────────┘    └─────────────┘
          │                  │                  │
          └──────────────────┼──────────────────┘
                             │
               ┌─────────────┴─────────────┐
               │                           │
               ▼                           ▼
       ┌─────────────┐             ┌─────────────┐
       │   Firewall  │             │    Logger   │
       │    Module   │             │    Module   │
       └─────────────┘             └─────────────┘
```

This architecture makes the project easier to maintain, debug, and extend.

---

## 🔮 Roadmap

Planned improvements may include:

* [ ] Automatic Windows edition detection
* [ ] Windows 10/11 build detection
* [ ] Improved Group Policy detection
* [ ] Network profile management
* [ ] Network adapter diagnostics
* [ ] DNS diagnostics
* [ ] Winsock diagnostics
* [ ] TCP/IP stack repair
* [ ] NetBIOS diagnostics
* [ ] Automatic service dependency analysis
* [ ] Advanced SMB diagnostics
* [ ] Improved backup/restore engine
* [ ] JSON configuration export
* [ ] HTML diagnostic reports
* [ ] Automatic repair verification
* [ ] Dry-run mode
* [ ] More granular confirmation prompts
* [ ] Internationalization
* [ ] GUI version

---

## 🤝 Contributing

Contributions, bug reports, suggestions, and improvements are welcome.

To contribute:

```bash
git fork https://github.com/mehrdadmb2/Windows-Network-Repair.git
```

Create a new branch:

```bash
git checkout -b feature/my-improvement
```

Make your changes and commit them:

```bash
git add .
git commit -m "Add my improvement"
```

Push your branch:

```bash
git push origin feature/my-improvement
```

Then open a Pull Request on GitHub.

---

## 🐛 Bug Reports

When reporting a problem, please include:

* Windows version
* Windows edition
* PowerShell version
* Error message
* Relevant log file
* Steps to reproduce the problem

You can check your PowerShell version with:

```powershell
$PSVersionTable
```

---

## ⚠️ Disclaimer

This software modifies Windows networking configuration and may require administrative privileges.

The author is not responsible for:

* Data loss
* Network outages
* Security issues
* Incorrect system configuration
* Problems caused by enabling legacy protocols
* Problems caused by modifications made outside the software

Always create a backup before changing important system configuration.

Use security-sensitive SMB options only when required.

---

## 📄 License

This project is licensed under the **MIT License**.

See the `LICENSE` file for the complete license text.

---

## 👨‍💻 Author

Developed by **Mehrdad**

GitHub:

https://github.com/mehrdadmb2

Project:

https://github.com/mehrdadmb2/Windows-Network-Repair

---

## ⭐ Support the Project

If this project helped you troubleshoot a Windows networking or SMB problem, consider giving the repository a ⭐ on GitHub.

It helps the project gain visibility and encourages further development.

---

<p align="center">
  <strong>Windows Network Repair</strong><br>
  Diagnose • Repair • Backup • Restore • Verify
</p>
