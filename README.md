<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:A8E55C,100:2DC94E&height=200&section=header&text=G2rayXCodeLeafy&fontSize=52&fontColor=ffffff&fontAlignY=38&desc=Xray%20Management%20Tool%20%E2%80%A2%20Codespace%20Optimized&descSize=18&descAlignY=60&descColor=efffef" alt="G2ray Panel" width="100%"/>

<br/>

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=22&pause=1200&color=2DC94E&center=true&vCenter=true&width=500&lines=%E2%9A%A1+G2ray+Panel+v1.0;Deploy+VLESS+in+Codespaces;Manage+Configs+on+the+Fly;Auto-Keepalive+Included;Native+XHTTP+Support" alt="Typing animation" />

<img src="./assets/preview.png" alt="G2ray Panel Preview" width="800" style="border-radius: 10px; box-shadow: 0 4px 8px rgba(0,0,0,0.2);" />

<br/>
<br/>

[![Shell](https://img.shields.io/badge/Shell-Bash-2DC94E?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://bash.org)
[![Platform](https://img.shields.io/badge/Platform-GitHub%20Codespaces-A8E55C?style=for-the-badge&logo=github&logoColor=white&labelColor=1a1a1a)](https://github.com/features/codespaces)
[![License](https://img.shields.io/badge/License-MIT-2DC94E?style=for-the-badge&labelColor=1a1a1a)](LICENSE)
[![Telegram](https://img.shields.io/badge/Channel-%40codeleafy-2DC94E?style=for-the-badge&logo=telegram&logoColor=white&labelColor=1a1a1a)](https://t.me/codeleafy)
[![GitHub](https://img.shields.io/badge/GitHub-Code--Leafy-A8E55C?style=for-the-badge&logo=github&logoColor=white&labelColor=1a1a1a)](https://github.com/Code-Leafy)

<br/>

> **A powerful, interactive Bash panel to deploy and manage VLESS XHTTP configurations.**  
> Built specifically for GitHub Codespaces. Fully automated, lightweight, and efficient.

<br/>

### 📢 Community Donated Configs (SUB)
https://raw.githubusercontent.com/Code-Leafy/G2rayXCodeLeafy/main/configs.txt

> **Thank you to everyone who has contributed!** Your donations help the community bypass restrictions with ease.  
> 💡 **Want to help?** You can donate your config directly from the G2ray Panel CLI (Option 1) after generating it. Your privacy is fully protected!

<br/>

---

## 📖 Tutorial & Disclaimer
👉[**Click here for the Step-by-Step Tutorial**](https://t.me/CodeLeafy/15)

> [!IMPORTANT]
> **Disclaimer:** This project is provided for educational and research purposes only. The developer does not encourage or condone the use of this software for bypassing network restrictions in violation of local laws. Users are solely responsible for their actions and compliance with all applicable regulations in their region. The developer is not responsible for any misuse of this tool.

<br/>

</div>

---

## ✨ Features

- ⚡ **One-Click Deployment** — Generate and start Xray engines in seconds.
- 🎛️ **Interactive CLI Panel** — A beautiful, menu-driven interface to manage your node.
- 🔄 **Auto-Keepalive** — Smart keepalive loops to prevent your Codespace from hibernating.
- 📡 **Live Stats** — Monitor traffic usage (RX/TX) and resource consumption in real-time.
- 🌍 **Dynamic Routing** — Switch between Auto-detect, Custom IPs, and CDN routes instantly.
- 🩺 **Self-Healing** — Auto-restart engine, public port management, and log monitoring.
- 📋 **QR Generation** — Generate shareable QR codes directly in your terminal.

---

## 📋 Requirements

| Requirement | Notes |
|-------------|-------|
| **GitHub Account** | To use Codespaces |
| **curl / jq** | Used for API interaction and JSON parsing |
| **Xray-Core** | The core engine (automatically detected/run) |

---

## 🚀 Installation & Usage

### Method 1: Standard (Terminal)
```bash
# Clone the repository
git clone https://github.com/Code-Leafy/G2ray-Panel.git
cd G2ray-Panel

# Run the panel
bash g2ray.sh
```

### Method 2: Mobile / Web (No Terminal Required)
If you don't have Git installed or are using a phone, follow these steps:
1. **Fork the Repo:** Click the **Fork** button at the top right of this page to copy it to your account.
2. **Create Codespace:** Open your forked repository, click the green **Code** button, select the **Codespaces** tab, and then click **Create codespace on main**.
3. **Wait for Load:** Wait a few minutes for the environment to build.
4. **Launch Panel:** Once the terminal loads, the G2ray CLI panel will appear automatically!

> **First Run:** The script will automatically detect that no configuration exists and prompt you to generate one.

---

## 🎮 Panel Controls

The G2ray Panel provides a full suite of tools:

- **Core Controls:** Generate configs, start/stop/restart the engine, and view QR codes.
- **Configuration:** Modify routing, change IPs, and tune the Keepalive frequency.
- **Analytics:** View real-time data usage, CPU/RAM usage of the engine, and check your Codespace quota/uptime.
- **Logs:** View the last 15 lines of the engine log to troubleshoot connectivity.

---

## 🛠️ How It Works

```
1. Panel initialized via Bash
   └─ Checks for existing config
      ├─ If missing: Runs setup/keygen
      └─ If present: Loads existing environment
2. Xray Engine execution
   └─ Configured with XHTTP protocol
   └─ API enabled for stats tracking
3. Keepalive mechanism
   └─ Background task prevents Codespace inactivity
   └─ Customizable interval (Normal/Aggressive/Economy)
```

---

## 📁 Repository Structure

```
G2ray-Panel/
├── g2ray.sh          # Main management panel
├── configs.txt       # Community donated configs
├── data/             # Configs, UUIDs, and PIDs
├── logs/             # Engine log files
└── README.md         # This file
```

---

## 📣 Channel & Support

<div align="center">

[![Telegram](https://img.shields.io/badge/Join%20Channel-%40codeleafy-2CA5E0?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/codeleafy)

Get the latest updates, configuration tips, and support on our Telegram channel.

</div>

---

## ⚖️ License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

Made with ❤️ by [Code-Leafy](https://github.com/Code-Leafy)

[![GitHub stars](https://img.shields.io/github/stars/Code-Leafy/G2ray-Panel?style=social)](https://github.com/Code-Leafy/G2ray-Panel/stargazers)

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:A8E55C,100:2DC94E&height=100&section=footer" width="100%"/>

</div>
