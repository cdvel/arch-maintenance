#!/bin/bash

# Weekly Arch Linux Maintenance Script
# Based on: https://fernandocejas.com/blog/engineering/2022-03-30-arch-linux-system-maintance/
# Description: Performs routine maintenance tasks for Arch Linux systems
# Usage: Run with sudo privileges - sudo ./arch_maintenance.sh

# Color definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Default settings - Can be changed with command line options
PERFORM_SYSTEM_UPDATE=true
PERFORM_CACHE_CLEAN=true
REMOVE_ORPHANS=true
CLEAN_JOURNALS=true
AUTO_CONFIRM=false
DRY_RUN=false
BACKUP_PACMAN=true
YOLO_MODE=false
UPDATE_FLATPAK=true
REINSTALL_FLATPAK=true

# Show help function
function show_help() {
  echo -e "${BLUE}${BOLD}Arch Linux Maintenance Script - Options:${NC}"
  echo "  -h, --help             Show this help message"
  echo "  -n, --no-update        Skip system updates"
  echo "  -c, --no-cache-clean   Skip cache cleaning"
  echo "  -o, --no-orphans       Skip orphaned package removal"
  echo "  -j, --no-journal-clean Skip journal cleaning"
  echo "  -y, --yes              Auto-confirm all actions"
  echo "  --yolo                 Skip all confirmations and use aggressive defaults"
  echo "  -d, --dry-run          Show what would be done without actually doing it"
  echo "  -b, --no-backup        Skip pacman database backup"
  echo "  -f, --no-flatpak       Skip Flatpak updates and maintenance"
  echo "  --no-flatpak-reinstall Skip reinstalling Flatpak packages after maintenance"
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
  -h | --help)
    show_help
    ;;
  -n | --no-update)
    PERFORM_SYSTEM_UPDATE=false
    shift
    ;;
  -c | --no-cache-clean)
    PERFORM_CACHE_CLEAN=false
    shift
    ;;
  -o | --no-orphans)
    REMOVE_ORPHANS=false
    shift
    ;;
  -j | --no-journal-clean)
    CLEAN_JOURNALS=false
    shift
    ;;
  -y | --yes)
    AUTO_CONFIRM=true
    shift
    ;;
  --yolo)
    YOLO_MODE=true
    AUTO_CONFIRM=true
    shift
    ;;
  -d | --dry-run)
    DRY_RUN=true
    shift
    ;;
  -b | --no-backup)
    BACKUP_PACMAN=false
    shift
    ;;
  -f | --no-flatpak)
    UPDATE_FLATPAK=false
    REINSTALL_FLATPAK=false
    shift
    ;;
  --no-flatpak-reinstall)
    REINSTALL_FLATPAK=false
    shift
    ;;
  *)
    echo -e "${RED}Unknown option: $1${NC}"
    show_help
    ;;
  esac
done

# Check if script is run with sudo
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}⚠️  This script must be run with sudo privileges.${NC}"
  exit 1
fi

# Display header
echo -e "${BLUE}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}        ARCH LINUX MAINTENANCE SCRIPT       ${NC}"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${CYAN}🚀 Starting maintenance tasks at $(date)${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}${BOLD}DRY RUN MODE: No actual changes will be made${NC}"
  echo ""
fi

# Function to display task sections
function task_header() {
  echo ""
  echo -e "${PURPLE}🔷 ${BOLD}$1${NC}"
  echo -e "${PURPLE}────────────────────────────────────────────${NC}"
}

# Function to prompt for confirmation
function confirm_action() {
  if [ "$AUTO_CONFIRM" = true ] || [ "$YOLO_MODE" = true ]; then
    return 0
  fi

  echo -e "${YELLOW}$1 [y/N]${NC}"
  read -r response
  if [[ "${response,,}" =~ ^(yes|y)$ ]]; then
    return 0
  else
    return 1
  fi
}

# Function to run commands with error checking
function run_command() {
  echo -e "${YELLOW}$ $1${NC}"

  if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}(dry run) Command would be executed${NC}"
    return 0
  else
    eval $1
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✅ Success${NC}"
      return 0
    else
      echo -e "${RED}❌ Error occurred${NC}"
      return 1
    fi
  fi
}

# Check if yay is installed
if ! command -v yay &>/dev/null; then
  echo -e "${YELLOW}⚠️  Warning: yay is not installed. Some features will use pacman instead.${NC}"
  HAS_YAY=false
else
  echo -e "${GREEN}✓ yay detected${NC}"
  HAS_YAY=true
fi

# Check if flatpak is installed
if ! command -v flatpak &>/dev/null; then
  echo -e "${YELLOW}⚠️  Warning: flatpak is not installed. Flatpak operations will be skipped.${NC}"
  HAS_FLATPAK=false
else
  echo -e "${GREEN}✓ flatpak detected${NC}"
  HAS_FLATPAK=true
fi

# Backup pacman database
if [ "$BACKUP_PACMAN" = true ]; then
  task_header "Backing up pacman database 💾"
  BACKUP_DATE=$(date +%Y%m%d)
  BACKUP_DIR="/var/lib/pacman/backup"

  if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${CYAN}Creating backup directory...${NC}"
    if [ "$DRY_RUN" = false ]; then
      mkdir -p $BACKUP_DIR
    fi
  fi

  BACKUP_FILE="$BACKUP_DIR/pacman_database_$BACKUP_DATE.tar.gz"

  echo -e "${CYAN}ℹ️ Creating backup of pacman database to $BACKUP_FILE${NC}"
  if [ "$DRY_RUN" = false ]; then
    tar -czf "$BACKUP_FILE" -C /var/lib/pacman/ local
    if [ $? -eq 0 ]; then
      echo -e "${GREEN}✅ Pacman database backup created successfully${NC}"
      echo -e "${CYAN}ℹ️ To restore: sudo tar -xzf $BACKUP_FILE -C /var/lib/pacman/${NC}"
    else
      echo -e "${RED}❌ Failed to create pacman database backup${NC}"
    fi
  else
    echo -e "${CYAN}(dry run) Would backup pacman database${NC}"
  fi
fi

# Update pacman mirrors to get fastest mirrors
task_header "Updating pacman mirrors 🌐"
echo -e "${CYAN}ℹ️ This updates mirror list for faster downloads${NC}"

# Check if reflector is installed
if ! command -v reflector &>/dev/null; then
  echo -e "${RED}⚠️ reflector is not installed. Skipping mirror update.${NC}"
  echo -e "${YELLOW}Install reflector with: sudo pacman -S reflector${NC}"
else
  if confirm_action "Do you want to update the pacman mirrors?"; then
    # Try to detect country automatically through IP geolocation
    COUNTRY=$(curl -s https://ipinfo.io/country 2>/dev/null)
    if [ -z "$COUNTRY" ]; then
      echo -e "${YELLOW}Could not detect country automatically, using default settings.${NC}"
      run_command "reflector --verbose --latest 5 --sort rate --save /etc/pacman.d/mirrorlist"
    else
      echo -e "${CYAN}Detected country: $COUNTRY${NC}"
      run_command "reflector --verbose --country '$COUNTRY' --latest 5 --sort rate --save /etc/pacman.d/mirrorlist"
    fi
    echo -e "${CYAN}📊 Mirror list updated for optimal speeds${NC}"
  else
    echo -e "${YELLOW}⏩ Skipping mirror update${NC}"
  fi
fi

# Full system update (including AUR packages when using yay)
if [ "$PERFORM_SYSTEM_UPDATE" = true ]; then
  task_header "Performing full system update 📦"
  echo -e "${CYAN}ℹ️ This will update all packages on your system${NC}"
  echo -e "${RED}⚠️  WARNING: System updates can occasionally cause issues with existing software${NC}"

  if confirm_action "Do you want to perform a full system update?"; then
    if [ "$HAS_YAY" = true ]; then
      run_command "yay -Syu --noconfirm"
      echo -e "${CYAN}🎮 Both repository and AUR packages updated${NC}"
    else
      run_command "pacman -Syu --noconfirm"
      echo -e "${YELLOW}⚠️ Note: AUR packages are not being updated as yay is not installed.${NC}"
    fi
  else
    echo -e "${YELLOW}⏩ Skipping system update${NC}"
  fi
else
  echo -e "${YELLOW}⏩ System update skipped (disabled by command line option)${NC}"
fi

# Update Flatpak packages
if [ "$UPDATE_FLATPAK" = true ] && [ "$HAS_FLATPAK" = true ]; then
  task_header "Updating Flatpak Applications 📱"
  echo -e "${CYAN}ℹ️ This will update all Flatpak applications${NC}"

  # List installed Flatpak apps
  echo -e "${CYAN}ℹ️ Currently installed Flatpak applications:${NC}"
  run_command "flatpak list --app"

  if confirm_action "Do you want to update Flatpak applications?"; then
    run_command "flatpak update -y"
    echo -e "${GREEN}✅ Flatpak applications updated${NC}"
  else
    echo -e "${YELLOW}⏩ Skipping Flatpak updates${NC}"
  fi

  # Clean unused Flatpak runtimes and extensions
  if confirm_action "Do you want to clean unused Flatpak runtimes and extensions?"; then
    run_command "flatpak uninstall --unused -y"
    echo -e "${GREEN}✅ Unused Flatpak components removed${NC}"
  else
    echo -e "${YELLOW}⏩ Skipping Flatpak cleanup${NC}"
  fi
else
  if [ "$UPDATE_FLATPAK" = false ]; then
    echo -e "${YELLOW}⏩ Flatpak operations skipped (disabled by command line option)${NC}"
  elif [ "$HAS_FLATPAK" = false ]; then
    echo -e "${YELLOW}⏩ Flatpak operations skipped (Flatpak not installed)${NC}"
  fi
fi

# Clean package cache
if [ "$PERFORM_CACHE_CLEAN" = true ]; then
  task_header "Cleaning package cache 🧹"
  echo -e "${CYAN}ℹ️ This removes old versions of packages from your cache${NC}"
  echo -e "${YELLOW}⚠️ Warning: This will make downgrading packages more difficult${NC}"

  if confirm_action "Do you want to clean the package cache?"; then
    echo -e "${CYAN}ℹ️ Removing all cached versions of installed and uninstalled packages, except for the most recent 3 versions${NC}"
    run_command "paccache -r"
    run_command "paccache -ruk0"
    echo -e "${GREEN}♻️ Package cache cleaned${NC}"
  else
    echo -e "${YELLOW}⏩ Skipping package cache cleaning${NC}"
  fi

  # Clean yay cache if available
  if [ "$HAS_YAY" = true ]; then
    task_header "Cleaning yay cache 🧹"
    echo -e "${CYAN}ℹ️ This removes build files from yay cache${NC}"

    if confirm_action "Do you want to clean the yay cache?"; then
      echo -e "${CYAN}ℹ️ Removing build files from yay cache${NC}"
      run_command "yay -Sc --noconfirm"
      echo -e "${GREEN}♻️ YAY cache cleaned${NC}"
    else
      echo -e "${YELLOW}⏩ Skipping yay cache cleaning${NC}"
    fi
  fi
else
  echo -e "${YELLOW}⏩ Cache cleaning skipped (disabled by command line option)${NC}"
fi

# Remove orphaned packages
if [ "$REMOVE_ORPHANS" = true ]; then
  task_header "Removing orphaned packages 🗑️"
  echo -e "${CYAN}ℹ️ This removes packages that are no longer required by any installed software${NC}"
  echo -e "${YELLOW}⚠️ Warning: Sometimes packages may be incorrectly identified as orphaned${NC}"

  # Explicitly warn about Flatpak dependencies
  if [ "$HAS_FLATPAK" = true ]; then
    echo -e "${RED}⚠️ Warning: This may remove dependencies needed by Flatpak applications${NC}"
    if [ "$REINSTALL_FLATPAK" = true ]; then
      echo -e "${GREEN}✓ Flatpak applications will be reinstalled after orphan removal to restore dependencies${NC}"
    else
      echo -e "${RED}⚠️ Flatpak reinstallation is disabled - your Flatpak apps may break!${NC}"
    fi
  fi

  ORPHANS=$(pacman -Qtdq)
  if [[ -z "$ORPHANS" ]]; then
    echo -e "${GREEN}🔍 No orphaned packages found.${NC}"
  else
    echo -e "${YELLOW}🔍 The following orphaned packages were found:${NC}"
    echo -e "${YELLOW}$ORPHANS${NC}"

    if confirm_action "Do you want to remove these orphaned packages?"; then
      if [ "$HAS_YAY" = true ]; then
        run_command "yay -Rns $ORPHANS --noconfirm"
      else
        run_command "pacman -Rns $ORPHANS --noconfirm"
      fi
      echo -e "${GREEN}♻️ System cleaned of orphaned packages${NC}"

      # Extra message about Flatpak reinstallation after orphan removal
      if [ "$HAS_FLATPAK" = true ] && [ "$REINSTALL_FLATPAK" = true ]; then
        echo -e "${CYAN}ℹ️ Flatpak applications will be reinstalled later to fix any dependency issues${NC}"
      fi
    else
      echo -e "${YELLOW}⏩ Skipping orphaned package removal${NC}"
    fi
  fi
else
  echo -e "${YELLOW}⏩ Orphaned package removal skipped (disabled by command line option)${NC}"
fi

# Check for failed systemd services
task_header "Checking for failed systemd services 🔄"
echo -e "${CYAN}ℹ️ Listing any failed system services${NC}"
run_command "systemctl --failed"
echo -e "${CYAN}🔎 System service status checked${NC}"

# Check system logs for errors
task_header "Checking system logs for errors 📋"
echo -e "${CYAN}ℹ️ Checking recent logs for critical errors${NC}"
run_command "journalctl -p 3 -xb"
echo -e "${CYAN}📒 System logs inspected${NC}"

# Trim SSD if applicable
task_header "Performing SSD TRIM 💿"
echo -e "${CYAN}ℹ️ This optimizes SSD performance (has no effect on HDDs)${NC}"
if confirm_action "Do you want to perform SSD TRIM?"; then
  run_command "fstrim -av"
  echo -e "${CYAN}💿 SSD optimization completed${NC}"
else
  echo -e "${YELLOW}⏩ Skipping SSD TRIM${NC}"
fi

# Clean journal logs
if [ "$CLEAN_JOURNALS" = true ]; then
  task_header "Cleaning systemd journal logs 📚"
  echo -e "${CYAN}ℹ️ This removes old system logs older than 2 weeks${NC}"
  echo -e "${YELLOW}⚠️ Warning: This will make investigating older issues more difficult${NC}"

  if confirm_action "Do you want to clean journal logs older than 2 weeks?"; then
    run_command "journalctl --vacuum-time=2weeks"
    echo -e "${GREEN}♻️ Old logs cleared${NC}"
  else
    echo -e "${YELLOW}⏩ Skipping journal cleanup${NC}"
  fi
else
  echo -e "${YELLOW}⏩ Journal cleaning skipped (disabled by command line option)${NC}"
fi

# Check disk usage
task_header "Checking disk usage 📊"
echo -e "${CYAN}ℹ️ Displaying disk usage report${NC}"
run_command "df -h"
echo -e "${CYAN}💽 Disk usage report generated${NC}"

# Reinstall Flatpak packages to fix any dependency issues
if [ "$REINSTALL_FLATPAK" = true ] && [ "$HAS_FLATPAK" = true ]; then
  task_header "Reinstalling Flatpak packages 🔄"
  echo -e "${CYAN}ℹ️ This reinstalls all Flatpak packages to fix dependencies that may have been removed${NC}"
  echo -e "${CYAN}ℹ️ This is necessary because orphan removal may have removed packages Flatpak depends on${NC}"

  if confirm_action "Do you want to reinstall Flatpak packages to fix potential dependency issues?"; then
    # Get list of installed Flatpak applications
    FLATPAK_APPS=$(flatpak list --app --columns=application)

    if [ -n "$FLATPAK_APPS" ]; then
      echo -e "${CYAN}ℹ️ Reinstalling Flatpak packages to restore system dependencies${NC}"
      for app in $FLATPAK_APPS; do
        run_command "flatpak install --reinstall -y $app"
      done
      echo -e "${GREEN}✅ Flatpak packages reinstalled successfully${NC}"
      echo -e "${GREEN}✅ This should fix any issues caused by orphan package removal${NC}"
    else
      echo -e "${YELLOW}ℹ️ No Flatpak applications found to reinstall${NC}"
    fi
  else
    echo -e "${YELLOW}⏩ Skipping Flatpak package reinstallation${NC}"
    if [ "$REMOVE_ORPHANS" = true ]; then
      echo -e "${RED}⚠️ Warning: Your Flatpak applications may not work correctly${NC}"
      echo -e "${RED}⚠️ If you experience issues, run: flatpak repair${NC}"
    fi
  fi
else
  if [ "$HAS_FLATPAK" = true ] && [ "$REINSTALL_FLATPAK" = false ] && [ "$REMOVE_ORPHANS" = true ]; then
    echo -e "${RED}⚠️ Warning: Orphaned packages were removed but Flatpak reinstallation was skipped${NC}"
    echo -e "${RED}⚠️ Your Flatpak applications may have broken dependencies${NC}"
    echo -e "${YELLOW}To fix issues: flatpak repair${NC}"
  fi
fi

# Summary
echo ""
echo -e "${BLUE}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BLUE}${BOLD}            MAINTENANCE COMPLETED           ${NC}"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════${NC}"
echo -e "${CYAN}🏁 Completed at $(date)${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}${BOLD}NOTE: This was a dry run. No actual changes were made.${NC}"
  echo -e "${YELLOW}To perform actual maintenance, run without the -d or --dry-run option.${NC}"
else
  echo -e "${GREEN}🎉 Weekly maintenance tasks completed! Your system should now be up-to-date and clean.${NC}"

  # Show what was skipped
  SKIPPED=""
  [ "$PERFORM_SYSTEM_UPDATE" = false ] && SKIPPED="${SKIPPED}system updates, "
  [ "$PERFORM_CACHE_CLEAN" = false ] && SKIPPED="${SKIPPED}cache cleaning, "
  [ "$REMOVE_ORPHANS" = false ] && SKIPPED="${SKIPPED}orphan removal, "
  [ "$CLEAN_JOURNALS" = false ] && SKIPPED="${SKIPPED}journal cleaning, "
  [ "$BACKUP_PACMAN" = false ] && SKIPPED="${SKIPPED}pacman backup, "
  [ "$UPDATE_FLATPAK" = false ] && SKIPPED="${SKIPPED}flatpak updates, "
  [ "$REINSTALL_FLATPAK" = false ] && SKIPPED="${SKIPPED}flatpak reinstallation, "

  if [ ! -z "$SKIPPED" ]; then
    SKIPPED=${SKIPPED%, }
    echo -e "${YELLOW}ℹ️ The following tasks were skipped: $SKIPPED${NC}"
  fi

  echo -e "${YELLOW}🔄 Consider rebooting your system to apply all updates.${NC}"
fi

# Additional tips
echo ""
echo -e "${CYAN}💡 TIPS:${NC}"

# yay-specific tip
if [ "$HAS_YAY" = true ]; then
  echo -e "${CYAN}  • To check for development package updates from the AUR, run:${NC}"
  echo -e "${YELLOW}     yay -Sua${NC}"
fi

# Flatpak-specific tip
if [ "$HAS_FLATPAK" = true ]; then
  echo -e "${CYAN}  • To list Flatpak applications that need updating:${NC}"
  echo -e "${YELLOW}     flatpak remote-ls --updates${NC}"

  echo -e "${CYAN}  • To get more information about a Flatpak application:${NC}"
  echo -e "${YELLOW}     flatpak info <application-id>${NC}"

  echo -e "${CYAN}  • If Flatpak applications have issues after maintenance:${NC}"
  echo -e "${YELLOW}     flatpak repair${NC}"
fi

echo ""
echo -e "${CYAN}💡 Run this script with -h or --help to see available options${NC}"

exit 0
