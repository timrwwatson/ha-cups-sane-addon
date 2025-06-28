# Network Print & Scan Server for Home Assistant

Leverage your always-on Home Assistant host server to network-enable USB printers and scanners. This comprehensive addon provides CUPS printing, SANE scanning, and a modern web-based scanning interface, turning your locally-connected USB devices into network-accessible resources.

## 🖨️ **What This Addon Provides**

- **🔌 USB-to-Network Bridge** - Turn USB printers/scanners into network-accessible devices using your HA server
- **🖨️ CUPS Print Server** - Share printers across your network with extensive driver support
- **🔍 SANE Scanner Support** - Network-enable USB scanners for remote access  
- **🌐 Web Scanning Interface** - Modern browser-based scanning from any device
- **📱 AirPrint Compatibility** - iOS/macOS devices automatically discover shared printers
- **⚡ Always-On Service** - Leverage your HA host's 24/7 uptime for print/scan services
- **🏗️ Multi-Architecture** - Works on all HA host types (AMD64, ARM64, ARMv7, etc.)

## ✨ **Key Features**

### Print Server Capabilities
- **HP & Brother Printer Focus** - Extensive driver packages for popular brands
- **PDF Printing** - Built-in PDF printer for document generation
- **Network Sharing** - Share USB printers across your entire network
- **Web Administration** - Full CUPS web interface on port 631
- **AirPrint Broadcasting** - iOS/macOS devices can discover and print automatically

### Scanning Capabilities  
- **Multi-Format Output** - TIFF, JPEG, PNG, PDF, and OCR text extraction
- **Advanced Features** - Auto-cropping, resolution control, color modes
- **Batch Scanning** - ADF support and manual multi-page workflows
- **Image Processing** - Auto-levels, threshold, blur filters
- **OCR Support** - Text extraction with Tesseract in multiple languages
- **Modern Web UI** - Responsive design accessible from any device

### Technical Features
- **Containerized** - Runs securely in Docker with proper isolation
- **Persistent Storage** - Scan outputs and configurations survive addon restarts
- **Health Monitoring** - Automatic service restart and health checks
- **Debug Logging** - Comprehensive logging for troubleshooting

## 🚀 **Installation**

### **Quick Install** (Easiest Method)
[![Add repository to Home Assistant](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A//github.com/vtechs-ja/ha-cups-sane-addon)

Click the button above to automatically add this repository to your Home Assistant instance.

### **Manual Installation**
1. **Add Repository Manually**:
   ```
   Settings → Add-ons → Add-on Store → ⋮ → Repositories
   Add: https://github.com/vtechs-ja/ha-cups-sane-addon
   ```

2. **Install Addon**:
   - Find "Network Print & Scan Hub" in the add-on store
   - Click **Install**
   - Enable **USB** access in Configuration tab
   - Enable **Host Network** in Network tab

3. **Start Addon**:
   - Click **Start**
   - Monitor logs for successful startup

## 🔧 **Configuration**

### Hardware Setup
- **USB Devices**: Connect printers/scanners to HA host before starting addon
- **Network Scanners**: Ensure network scanners are accessible from HA network
- **Permissions**: Addon automatically configures required user permissions

### Access Points
- **Print Server**: `http://your-ha-ip:631` (CUPS web interface)
- **Scan Interface**: `http://your-ha-ip:8080` (scanservjs web UI)  
- **HA Integration**: Use "Open Web UI" button (port 8080 interface)

### Default Credentials
- **Username**: `print`
- **Password**: `print`
- *(Can be modified in addon configuration)*

## 📋 **Usage**

### Setting Up Printing
1. Access CUPS interface at `http://your-ha-ip:631`
2. Go to **Administration** → **Add Printer**
3. Select your USB or network printer
4. Configure driver and settings
5. Test print functionality

### Setting Up Scanning  
1. Access scan interface at `http://your-ha-ip:8080`
2. Select your scanner from detected devices
3. Configure scan settings (resolution, format, etc.)
4. Preview and scan documents
5. Download or process scanned files

### Network Access
Once your USB devices are connected to the HA host, they become network resources:
- **Desktop/Laptop**: Add `http://your-ha-ip:631` as a network printer
- **Mobile Devices**: Shared printers appear automatically in AirPrint
- **Web Scanning**: Access scanning interface from any device at `http://your-ha-ip:8080`
- **Always Available**: Devices remain accessible 24/7 thanks to your HA host's uptime

## 🔍 **Troubleshooting**

### Common Issues

**Addon Won't Start**
- Check that USB access is enabled in addon configuration
- Verify Host Network is enabled
- Review addon logs for specific error messages

**Scanner Not Detected**
- Ensure scanner is connected and powered on before starting addon
- Check USB cable connections
- For network scanners, verify IP connectivity

**Print Jobs Fail**
- Verify printer is connected and has paper/ink
- Check CUPS error logs in web interface
- Restart addon if printer was disconnected/reconnected

**Web Interface 401 Errors**
- Clear browser cache and cookies for HA domain
- Log out and back into Home Assistant
- Try accessing directly via IP:port instead of HA ingress

### Log Locations
- **Addon Logs**: Home Assistant → Settings → Add-ons → Network Print & Scan Hub → Logs
- **CUPS Logs**: Available in CUPS web interface at `http://your-ha-ip:631`
- **System Logs**: Check HA system logs for hardware/USB issues

## 🏗️ **Architecture Support**

This addon supports all major Home Assistant architectures:
- **amd64** - Intel/AMD 64-bit (most common)
- **aarch64** - ARM 64-bit (Raspberry Pi 4, etc.)
- **armv7** - ARM 32-bit (Raspberry Pi 3, etc.)  
- **armhf** - ARM hard-float
- **i386** - Intel 32-bit (legacy systems)

## 📁 **File Storage**

All persistent data is stored in the addon's data directory:
- **`/data/cups/`** - CUPS configuration and printer settings
- **`/data/scans/`** - Scanned documents and images
- **`/data/sane.d/`** - SANE scanner configuration
- **`/data/scanservjs.config.js`** - scanservjs settings

## 🛠️ **Advanced Configuration**

### Custom Scanner Settings
Edit `/data/sane.d/` configuration files for advanced scanner options.

### CUPS Configuration  
Modify settings via web interface or edit `/data/cups/cupsd.conf` directly.

### Network Scanner Setup
Add network scanner IPs to `/data/sane.d/net.conf`:
```
192.168.1.100  # Your network scanner IP
```

## 🤝 **Acknowledgements**

This addon builds upon excellent work from the open-source community:

- **Original CUPS Addon**: [niallr/ha-cups-addon](https://github.com/niallr/ha-cups-addon) - Foundational CUPS implementation
- **CUPS Configuration**: [lemariva/wifi-cups-server](https://github.com/lemariva/wifi-cups-server) - cupsd.conf and Dockerfile structure  
- **Avahi/D-Bus Integration**: [marthoc/docker-homeseer](https://github.com/marthoc/docker-homeseer) - Service management patterns
- **Scanning Interface**: [sbs20/scanservjs](https://github.com/sbs20/scanservjs) - Modern web-based scanning solution
- **SANE Project**: [sane-project.org](http://www.sane-project.org/) - Scanner Access Now Easy framework

## ☕ **Support the Project**

If this addon has been helpful and you'd like to support future development:

[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-PayPal-blue.svg?style=for-the-badge&logo=paypal)](https://paypal.me/vtechjm)

Your support helps keep this project maintained and updated! 🙏

## 📄 **License**

This project is released under the same license terms as the original components it builds upon. See individual component repositories for specific licensing details.

## 🐛 **Community Support**

This is a community project maintained as-needed for personal use. While the code is freely available for anyone to use and extend:

**For Issues:**
1. Check the troubleshooting section above
2. Review addon logs for error details  
3. Search existing GitHub issues
4. Community contributions and pull requests are welcome

**Support Expectations:**
- Updates will be made periodically for compatibility
- No guaranteed response time for issues
- Community members are encouraged to help each other
- Fork and extend as needed for your use case

## 🔋 **Power Management Notes**

**USB Printer Standby:** Most USB printers automatically enter standby mode when idle. However, they remain powered through the USB connection. Some possibilities:
- **Smart USB Hubs:** Use HA-controlled smart plugs with USB hubs to power cycle printers
- **Printer Settings:** Many printers have built-in sleep timers (check printer's web interface or buttons)
- **CUPS Power Management:** Some printers support power commands through CUPS drivers

## 📝 **OCR Features Already Included**

The scanservjs interface already includes OCR capabilities:
- **Tesseract OCR** is pre-installed
- **Text Output Format** - Scan directly to `.txt` files
- **Multiple Languages** - English, German, French, Spanish, Italian, Portuguese, Dutch
- **PDF with OCR** - Creates searchable PDFs
- Access via the scanning web interface at port 8080

---

**Turn your USB printers and scanners into always-available network resources! 🖨️📄✨**