# Network Print & Scan Server for Home Assistant

Turn your HA host into a network print and scan server. Share USB printers and scanners across your network with CUPS printing, SANE scanning, and a modern web-based scanning interface.

## 🖨️ **Features**

- **🔌 USB-to-Network Bridge** - Network-enable USB printers and scanners
- **🖨️ CUPS Print Server** - Share printers with extensive driver support
- **🔍 SANE Scanner Support** - Network scanning with web interface
- **📱 AirPrint Compatible** - iOS/macOS auto-discovery
- **🌐 Web Scanning Interface** - Modern browser-based scanning with OCR
- **⚡ Always-On Service** - Leverage your HA host's 24/7 uptime
- **🏗️ Multi-Architecture** - Works on all HA host types

### Print & Scan Capabilities
- **HP & Brother printer focus** with extensive driver packages
- **Multiple scan formats** - TIFF, JPEG, PNG, PDF with OCR text extraction
- **Advanced scanning** - Auto-cropping, batch scanning, image processing
- **Built-in OCR** - Tesseract with multiple languages, searchable PDFs

## 🚀 **Installation**

### Quick Install
[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=[https%3A//github.com/vtechs-ja/ha-cups-sane-addon](https://github.com/timrwwatson/ha-cups-sane-addon))

### Manual Installation
1. **Add Repository**: Settings → Add-ons → ⋮ → Repositories  
   Add: `https://github.com/vtechs-ja/ha-cups-sane-addon`
2. **Install**: Find "Network Print & Scan Hub" and click Install
3. **Configure**: Enable USB access and Host Network in addon settings
4. **Start**: Click Start and monitor logs

## 🔧 **Configuration**

### Hardware Setup
- Connect USB devices to HA host before starting addon
- Ensure network scanners are accessible from HA network

### Access Points
- **Print Server**: `http://your-ha-ip:631` (CUPS web interface)
- **Scan Interface**: `http://your-ha-ip:8080` (scanservjs web UI)

### Default Credentials
- **Username**: `print` | **Password**: `print`
- *(Configurable in addon settings)*

## 📋 **Usage**

### Printing
1. Access CUPS at `http://your-ha-ip:631`
2. Go to Administration → Add Printer
3. Select and configure your printer
4. Your printer is now network-accessible and AirPrint compatible

### Scanning
1. Access scan interface at `http://your-ha-ip:8080`
2. Select scanner and configure settings
3. Preview, scan, and download files
4. OCR and multiple format support included

## 🔍 **Troubleshooting**

### Common Issues
- **Addon Won't Start**: Enable USB access and Host Network in addon configuration
- **Scanner Not Detected**: Ensure scanner is connected and powered before starting addon
- **Print Jobs Fail**: Check printer connection, paper/ink, and CUPS logs at port 631
- **Web Interface 401 Errors**: Clear browser cache or access directly via IP:port

### Log Locations
- **Addon Logs**: HA Settings → Add-ons → Network Print & Scan Hub → Logs
- **CUPS Logs**: Available at `http://your-ha-ip:631`

## 🏗️ **Architecture Support**

Supports all HA architectures: amd64, aarch64, armv7, armhf, i386

## 📁 **File Storage**

Persistent data stored in addon's data directory:
- `/data/cups/` - CUPS configuration
- `/data/scans/` - Scanned documents
- `/data/sane.d/` - SANE scanner configuration

## 🤝 **Acknowledgements**

Built upon excellent open-source projects:
- [niallr/ha-cups-addon](https://github.com/niallr/ha-cups-addon) - Original CUPS implementation
- [sbs20/scanservjs](https://github.com/sbs20/scanservjs) - Modern scanning interface
- [SANE Project](http://www.sane-project.org/) - Scanner framework

## ☕ **Support the Project**

If this addon has been helpful and you'd like to support future development:

[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/vtechjm)

## 📄 **License**

Released under the same license terms as the original components. See individual component repositories for specific licensing details.

## 🐛 **Community Support**

This is a community project maintained as-needed. For issues:
1. Check troubleshooting section and addon logs
2. Search existing GitHub issues
3. Community contributions and pull requests welcome

---

**Turn your USB printers and scanners into always-available network resources! 🖨️📄✨**
