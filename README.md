# Arch Linux Maintenance

An automated maintenance script for Arch Linux systems with scheduled execution and safety features.

## Overview

This repository contains scripts to automate routine maintenance tasks for Arch Linux. It handles system updates, cache cleaning, orphaned package removal, and various other maintenance tasks safely and efficiently.

## Features

- 🔄 Full system updates (pacman and AUR via yay)
- 🧹 Package cache cleaning
- 🗑️ Orphaned package removal
- 💾 Pacman database backups
- 📋 System logs check
- 💿 SSD TRIM support
- 📊 Disk usage reporting
- 📱 Flatpak support and dependency protection
- ⏱️ Automated biweekly execution via systemd
- 📝 Comprehensive logging
- 🛡️ Safety features (dry-run mode, confirmations)

## Requirements

The following packages are required for full functionality:

- `pacman` (built-in on Arch)
- `reflector` - For optimizing mirror lists: `sudo pacman -S reflector`
- `yay` - For AUR support: [Installation instructions](https://github.com/Jguer/yay#installation)
- `flatpak` - For Flatpak application support: `sudo pacman -S flatpak`

Without these packages, some features may be disabled or limited in functionality.

## Files

- `arch_maintenance.sh` - The main maintenance script
- `setup_maintenance.sh` - Installation script to set up automation
- `arch-maintenance.service` - Systemd service definition
- `arch-maintenance.timer` - Systemd timer for biweekly execution

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/cdvel/arch-maintenance.git
   cd arch-maintenance
   ```

2. Make the scripts executable:
   ```bash
   chmod +x arch_maintenance.sh setup_maintenance.sh
   ```

3. Run the setup script:
   ```bash
   sudo ./setup_maintenance.sh
   ```

This will:
- Create a maintenance directory at `~/arch-maintenance`
- Install the systemd service and timer
- Set up log rotation
- Enable automatic execution every two weeks

## Usage

### Automatic Execution

After installation, the script will run automatically every two weeks and log its output to `~/arch-maintenance/logs/`.

Check the timer status:
```bash
systemctl status arch-maintenance.timer
```

See when the next run is scheduled:
```bash
systemctl list-timers arch-maintenance.timer
```

### Manual Execution

Run the script manually with:
```bash
sudo ~/arch-maintenance/arch_maintenance.sh
```

### Command Line Options

The script supports several command-line options for safety:

- `-h, --help` - Show help message
- `-n, --no-update` - Skip system updates
- `-c, --no-cache-clean` - Skip cache cleaning
- `-o, --no-orphans` - Skip orphaned package removal
- `-j, --no-journal-clean` - Skip journal cleaning
- `-y, --yes` - Auto-confirm all actions
- `--yolo` - Skip all confirmations and use aggressive defaults
- `-d, --dry-run` - Show what would be done without making changes
- `-b, --no-backup` - Skip pacman database backup
- `-f, --no-flatpak` - Skip Flatpak updates and maintenance
- `--no-flatpak-reinstall` - Skip reinstalling Flatpak packages after maintenance

Example of a dry run:
```bash
sudo ~/arch-maintenance/arch_maintenance.sh --dry-run
```

### Flatpak Support

The script includes special handling for Flatpak applications:

- Updating Flatpak applications
- Cleaning unused Flatpak runtimes
- Reinstalling Flatpak packages after orphan removal to restore dependencies

**Note:** Orphan package removal may break Flatpak dependencies, which is why the script automatically reinstalls Flatpak packages at the end of the maintenance process.

If you're experiencing issues with Flatpak applications after running the script, you can manually repair them with:
```bash
flatpak repair
```

## Logs

Logs are stored in `~/arch-maintenance/logs/` with timestamps and are automatically rotated to prevent excessive disk usage.

## Customization

Edit the `arch_maintenance.sh` script to customize which maintenance tasks are performed.

The systemd timer can be modified by editing `/etc/systemd/system/arch-maintenance.timer` and running:
```bash
sudo systemctl daemon-reload
```

## License

[MIT License](LICENSE)

## Credits

Based on [Fernando Cejas's Arch Linux system maintenance guide](https://fernandocejas.com/blog/engineering/2022-03-30-arch-linux-system-maintance/).
