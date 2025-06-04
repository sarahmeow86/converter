#!/usr/bin/env bash

# Dialog helper functions
show_msg() {
    dialog --title "Message" --msgbox "$1" 8 60
}

show_progress() {
    echo "$1" | dialog --title "Progress" --progressbox 8 60
}

show_error() {
    dialog --title "Error" --msgbox "Error: $1" 8 60
}

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "dialog is not installed. Installing!"
    pacman -S --noconfirm dialog
    if [ $? -ne 0 ]; then
        echo "Failed to install dialog. Please install it manually."
        exit 1
    fi
fi

# Function to select init system
select_init_system() {
    local init_system

    init_system=$(dialog --clear --title "Init System Selection" \
        --menu "Choose the init system to convert to:" 15 50 4 \
        "openrc" "OpenRC init system" \
        "dinit" "Dinit init system" \
        "s6" "S6 init system" \
        "runit" "Runit init system" \
        2>&1 >/dev/tty)

    # Check if user pressed Cancel or ESC
    if [ $? -ne 0 ]; then
        clear
        echo "No init system selected. Exiting..."
        return 1
    fi

    clear
    echo "Selected init system: $init_system"
    
    # Install packages for selected init
    install_base_packages "$init_system"
    
    echo "$init_system"
}

# Add logging helper
log_cmd() {
    local logfile="/tmp/artix-convert.log"
    "$@" &>> "$logfile"
    return $?
}

pacstuff()  {
    local logfile="/tmp/artix-convert.log"
    : > "$logfile"  # Clear log file

    (
        echo "10"; show_progress "Backing up original pacman.conf..."
        mv -vf /etc/pacman.conf /etc/pacman.conf.arch &>/dev/null
        
        echo "20"; show_progress "Downloading new pacman.conf..."
        curl -s https://gitea.artixlinux.org/packages/pacman/raw/branch/master/pacman.conf -o /etc/pacman.conf &>/dev/null || {
            show_error "Failed to download pacman.conf"
            return 1
        }
        
        echo "25"; show_progress "Modifying pacman configuration..."
        # Enable parallel downloads
        sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/' /etc/pacman.conf
        
        # Check if multilib was enabled in original config
        if grep -q '^\[multilib\]' /etc/pacman.conf.arch; then
            # Enable lib32 repository if multilib was enabled
            sed -i 's/#\[lib32\]/[lib32]/' /etc/pacman.conf
            sed -i 's/#Include = \/etc\/pacman.d\/mirrorlist/Include = \/etc\/pacman.d\/mirrorlist/' /etc/pacman.conf
        fi
        
        echo "30"; show_progress "Modifying package signing requirements..."
        sed -i 's/SigLevel    = Required DatabaseOptional/SigLevel    = Never/' /etc/pacman.conf

        echo "40"; show_progress "Creating backup of downloaded config..."
        cp -vf /etc/pacman.conf /etc/pacman.conf.artix.backup &>/dev/null
        
        echo "50"; show_progress "Setting up mirrorlists..."
        mv -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist-arch &>/dev/null
        curl -s https://gitea.artixlinux.org/packages/artix-mirrorlist/raw/branch/master/mirrorlist -o /etc/pacman.d/mirrorlist &>/dev/null
        cp -vf /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.artix &>/dev/null
        
        echo "70"; show_progress "Cleaning package cache..."
        log_cmd pacman -Scc --noconfirm
        
        echo "80"; show_progress "Synchronizing package databases..."
        log_cmd pacman -Syy
        
        echo "90"; show_progress "Installing Artix keyring..."
        log_cmd pacman -S --noconfirm artix-keyring
        
        echo "95"; show_progress "Configuring Artix keys..."
        log_cmd pacman-key --populate artix
        log_cmd pacman-key --lsign-key 95AEC5D0C1E294FC9F82B253573A673A53C01BC2

        echo "98"; show_progress "Restoring package signature requirements..."
        sed -i 's/SigLevel    = Never/SigLevel    = Required DatabaseOptional/' /etc/pacman.conf
        
        echo "100"; show_progress "Configuration complete!"
    ) | dialog --title "Converting to Artix" --gauge "Starting conversion process..." 8 60 0

    show_msg "Pacman configuration completed successfully!\nCheck /tmp/artix-convert.log for details."
}

init_stuff() {
    systemctl --no-pager --type=service --state=running | grep -v '^systemd\.' | awk '{print $1}' | grep service > daemon.list
    pacman -Rdd --noconfirm systemd systemd-libs systemd-sysvcompat pacman-mirrorlist dbus
    rm -fv /etc/resolv.conf
    cp -f /etc/pacman.d/mirrorlist.artix /etc/pacman.d/mirrorlist
}

install_base_packages() {
    local init_system="$1"
    local base_pkgs="base base-devel grub linux linux-headers mkinitcpio rsync lsb-release esysusers etmpfiles artix-branding-base"
    local init_pkgs=""

    case "$init_system" in
        "openrc")
            init_pkgs="openrc elogind-openrc openrc-system"
            ;;
        "dinit")
            init_pkgs="dinit elogind-dinit dinit-system"
            ;;
        "s6")
            init_pkgs="s6-base elogind-s6 s6-system"
            ;;
        "runit")
            init_pkgs="runit elogind-runit runit-system"
            ;;
    esac

    (
        echo "0"; show_progress "Installing base packages..."
        log_cmd pacman -S --noconfirm $base_pkgs
        
        echo "50"; show_progress "Installing $init_system specific packages..."
        log_cmd pacman -S --noconfirm $init_pkgs
        
        echo "100"; show_progress "Package installation complete!"
    ) | dialog --title "Installing Base System" --gauge "Installing packages..." 8 60 0
}

reinstall_packages() {
    local init_system="$1"
    
    (
        echo "20"; show_progress "Reinstalling system packages..."
        log_cmd bash -c 'pacman -Sl system | grep installed | cut -d" " -f2 | pacman -S --noconfirm -'
        
        echo "40"; show_progress "Reinstalling world packages..."
        log_cmd bash -c 'pacman -Sl world | grep installed | cut -d" " -f2 | pacman -S --noconfirm -'
        
        echo "60"; show_progress "Reinstalling galaxy packages..."
        log_cmd bash -c 'pacman -Sl galaxy | grep installed | cut -d" " -f2 | pacman -S --noconfirm -'
        
        echo "80"; show_progress "Reinstalling lib32 packages..."
        log_cmd bash -c 'pacman -Sl lib32 | grep installed | cut -d" " -f2 | pacman -S --noconfirm -'

        echo "90"; show_progress "Converting system services to $init_system..."
        while read -r daemon; do
            # Remove both .service and .target suffixes
            daemon_name=$(echo "$daemon" | sed -E 's/\.(service|target)$//')
            pkg_name="${daemon_name}-${init_system}"
            
            # Check if package exists in repos
            if pacman -Ss "^${pkg_name}$" &>/dev/null; then
                log_cmd pacman -S --noconfirm "${pkg_name}"
            else
                echo "Package ${pkg_name} not found in repositories, skipping..." >> /tmp/artix-convert.log
            fi
        done < daemon.list
        
        echo "100"; show_progress "Package reinstallation complete!"
    ) | dialog --title "Reinstalling Packages" --gauge "Reinstalling all packages from Artix repositories..." 8 60 0

    # Show summary of skipped packages
    if grep -q "not found in repositories" /tmp/artix-convert.log; then
        show_msg "Some service packages were not available. Check /tmp/artix-convert.log for details."
    fi
}

enable_services() {
    local init_system="$1"
    local enable_cmd=""
    
    # Set the appropriate enable command based on init system
    case "$init_system" in
        "openrc")
            enable_cmd="rc-update add"
            ;;
        "dinit")
            enable_cmd="dinitctl enable"
            ;;
        "s6")
            # Create contents.d directory if it doesn't exist
            mkdir -p /etc/s6/adminsv/default/contents.d/
            enable_cmd="touch /etc/s6/adminsv/default/contents.d"
            ;;
        "runit")
            enable_cmd="ln -s /etc/runit/sv"
            ;;
    esac

    (
        echo "0"; show_progress "Preparing to enable services..."
        
        # Count total services for progress calculation
        total_services=$(wc -l < daemon.list)
        current=0
        
        while read -r daemon; do
            ((current++))
            progress=$((current * 100 / total_services))
            
            daemon_name=$(echo "$daemon" | sed -E 's/\.(service|target)$//')
            echo "$progress"; show_progress "Enabling service: $daemon_name"
            
            case "$init_system" in
                "openrc")
                    if [ -f "/etc/init.d/${daemon_name}" ]; then
                        log_cmd $enable_cmd "$daemon_name" default
                    else
                        echo "OpenRC service ${daemon_name} not found, skipping..." >> /tmp/artix-convert.log
                    fi
                    ;;
                "dinit")
                    if [ -d "/etc/dinit.d/${daemon_name}" ]; then
                        log_cmd $enable_cmd "$daemon_name"
                    else
                        echo "Dinit service ${daemon_name} not found, skipping..." >> /tmp/artix-convert.log
                    fi
                    ;;
                "s6")
                    if [ -d "/etc/s6/sv/${daemon_name}" ]; then
                        log_cmd $enable_cmd/"${daemon_name}"
                        log_cmd s6-db-reload
                    else
                        echo "S6 service ${daemon_name} not found, skipping..." >> /tmp/artix-convert.log
                    fi
                    ;;
                "runit")
                    if [ -d "/etc/runit/sv/${daemon_name}" ]; then
                        log_cmd $enable_cmd/"$daemon_name" /run/runit/service/
                    else
                        echo "Runit service ${daemon_name} not found, skipping..." >> /tmp/artix-convert.log
                    fi
                    ;;
            esac
        done < daemon.list
        
        echo "100"; show_progress "Service activation complete!"
    ) | dialog --title "Enabling Services" --gauge "Activating system services..." 8 60 0
}

safe_reboot() {
    show_msg "System will now reboot to complete the conversion.\nPress OK to continue."
    
    (
        echo "25"; show_progress "Syncing filesystems..."
        sync
        
        echo "50"; show_progress "Unmounting all filesystems..."
        umount -a || true  # Continue even if some filesystems are busy
        
        echo "75"; show_progress "Remounting root filesystem read-only..."
        mount -f / -o remount,ro
        
        echo "100"; show_progress "Triggering system reboot..."
        echo s >| /proc/sysrq-trigger  # Sync
        echo u >| /proc/sysrq-trigger  # Unmount
        echo b >| /proc/sysrq-trigger  # Reboot
    ) | dialog --title "System Reboot" --gauge "Preparing for system reboot..." 8 60 0
}

convert_system() {
    # Select init system first
    local init_system
    init_system=$(select_init_system)
    
    if [ $? -ne 0 ]; then
        show_error "Init system selection failed"
        exit 1
    fi

    # Configure pacman and repositories
    pacstuff || {
        show_error "Pacman configuration failed"
        exit 1
    }

    # Remove systemd and prepare for conversion
    init_stuff || {
        show_error "System preparation failed"
        exit 1
    }

    # Reinstall packages with new init versions
    reinstall_packages "$init_system" || {
        show_error "Package reinstallation failed"
        exit 1
    }

    # Enable converted services
    enable_services "$init_system" || {
        show_error "Service enablement failed"
        exit 1
    }

    show_msg "System successfully converted to Artix Linux with ${init_system}!"
    
    # Reboot the system
    safe_reboot
}

# Call the main function if script is executed directly
convert_system || {
    show_error "Conversion process failed"
    exit 1
}

