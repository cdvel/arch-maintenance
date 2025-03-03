#!/bin/bash

# Setup script for Arch Linux Maintenance
# This script sets up the maintenance directory, systemd service and timer

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Check if script is run with sudo
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}⚠️  This script must be run with sudo privileges.${NC}"
  exit 1
fi

echo -e "${BLUE}${BOLD}=====================================${NC}"
echo -e "${BLUE}${BOLD} Arch Maintenance Setup${NC}"
echo -e "${BLUE}${BOLD}=====================================${NC}"

# Create maintenance directory
MAINT_DIR="/home/arch-maintenance
echo -e "${YELLOW}Creating maintenance directory at $MAINT_DIR...${NC}"
mkdir -p $MAINT_DIR
mkdir -p $MAINT_DIR/logs

# Copy maintenance script to the directory
echo -e "${YELLOW}Copying maintenance script...${NC}"
cp arch_maintenance.sh $MAINT_DIR/
chmod +x $MAINT_DIR/arch_maintenance.sh

# Create systemd service and timer files
echo -e "${YELLOW}Creating systemd service and timer...${NC}"
cat >/etc/systemd/system/arch-maintenance.service <<'EOL'
[Unit]
Description=Arch Linux System Maintenance
After=network.target

[Service]
Type=oneshot
ExecStart=/home/Maintenance/arch_maintenance.sh --yes
User=root
StandardOutput=append:/home/Maintenance/logs/maintenance_%Y-%m-%d_%H-%M.log
StandardError=append:/home/Maintenance/logs/maintenance_%Y-%m-%d_%H-%M.log

[Install]
WantedBy=multi-user.target
EOL

cat >/etc/systemd/system/arch-maintenance.timer <<'EOL'
[Unit]
Description=Run Arch Linux Maintenance every two weeks
Requires=arch-maintenance.service

[Timer]
Unit=arch-maintenance.service
OnCalendar=biweekly
Persistent=true
RandomizedDelaySec=1hour

[Install]
WantedBy=timers.target
EOL

# Set proper permissions
echo -e "${YELLOW}Setting permissions...${NC}"
chown -R root:root /etc/systemd/system/arch-maintenance.*
chmod 644 /etc/systemd/system/arch-maintenance.*

# Reload systemd, enable and start the timer
echo -e "${YELLOW}Enabling and starting systemd timer...${NC}"
systemctl daemon-reload
systemctl enable arch-maintenance.timer
systemctl start arch-maintenance.timer

# Create log rotation configuration
echo -e "${YELLOW}Setting up log rotation...${NC}"
cat >/etc/logrotate.d/arch-maintenance <<'EOL'
/home/Maintenance/logs/maintenance_*.log {
    monthly
    rotate 6
    compress
    missingok
    notifempty
}
EOL

echo -e "${GREEN}${BOLD}Setup completed successfully!${NC}"
echo -e "${YELLOW}The maintenance script will run every two weeks automatically.${NC}"
echo -e "${YELLOW}Logs will be stored in $MAINT_DIR/logs/${NC}"
echo -e "${YELLOW}You can run it manually with: sudo $MAINT_DIR/arch_maintenance.sh${NC}"
echo -e "${YELLOW}To check timer status: systemctl status arch-maintenance.timer${NC}"
echo -e "${YELLOW}To check next run time: systemctl list-timers arch-maintenance.timer${NC}"

exit 0
