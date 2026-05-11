#!/bin/bash
# finish_install.sh - part of the DebianInstaller project
# Copyright (C) 2026, Scott Wyman, development@scottwyman.me
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.


INSTALLATION_VARIABLES_FILE=/activate_installation_variables.sh

INSTALL_CONSTANTS_FILE=/install_constants

PRETTY_OUTPUT_LIBRARY=/pretty_output_library.sh

COMPLETION_FILE="/finish_install_completion.txt"

export DEBIAN_FRONTEND=noninteractive

add_initramfs_module()
{
    if ! [[ -d /etc/initramfs-tools ]]
    then
        mkdir -p /etc/initramfs-tools
    fi

    if ! grep "$1" /etc/initramfs-tools/modules &>/dev/null
    then
        echo "$1" >> /etc/initramfs-tools/modules
    fi
}

if [[ "$(whoami)" != "root" ]]
then
    printf "\n\e[31m%s\e[0m\n" "[!] Must run script as root"
    exit 1
fi

if ! source $INSTALL_CONSTANTS_FILE &>/dev/null
then
    printf "\n\n\e[31m%s %s\e[0m\n\n" \
        "[!] Couldn't source the install_constants file. Make sure" \
        "to run bash ./DebianInstaller/start_install.sh."
    exit 1
fi

if ! source $PRETTY_OUTPUT_LIBRARY &>/dev/null
then
    printf "\n\n\e[31m%s %s\e[0m\n\n" \
        "[!] Couldn't source the pretty output library. Make sure" \
        "to run bash ./DebianInstaller/start_install.sh."
    exit 1
fi

declare -r STDERR_LOG_PATH="/debianinstallererrors.log"

if ! source $INSTALLATION_VARIABLES_FILE &>/dev/null
then
    printf "\n\n\e[31m%s %s\e[0m\n\n" \
        "[!] Couldn't source the installation variable. Make sure" \
        "to run \`bash ./DebianInstaller/start_install.sh\` first"
    exit 1
fi

if [[ -z "$admin_password" ]]
then
    printf "\n\n\e[31m%s\e[0m\n\n" \
        "[!] No admin password set. Make sure to run start_install.sh first"
    exit 1
fi

if [[ -z "$username" ]]
then
    printf "\n\n\e[31m%s\e[0m\n\n" \
        "[!] No username set. Make sure to run start_install.sh first"
    exit 1
fi

if [[ "$OVERWRITE_HOME_PARTITION" == 'n' && ! -d "/home/$username" ]]
then
    printf "\n\e[31m%s %s %s %s %s\e[0m\n" \
        "[!] /home/$username doesn't exist. When you're not overwriting the" \
        "/home partition you must use the username that already exists on" \
        "that partition. Use ls /mnt/home to see the existing users home," \
        "then Change the username in /tmp/activate_installation_variables.sh" \
        "to match it. After those steps re-run start_install.sh"
    exit 1
fi

if [[ -n "$APT_CACHE_SERVER" && -n "$APT_CACHE_FILE" ]]
then
    if ! grep "Acquire::http::Proxy \"$APT_CACHE_SERVER\";" \
        $APT_CACHE_FILE &>/dev/null
    then
        echo "Acquire::http::Proxy \"$APT_CACHE_SERVER\";" > $APT_CACHE_FILE &
        task_output $! "$STDERR_LOG_PATH" \
            "Use apt proxy server '$APT_CACHE_SERVER'"
        [[ $? -ne 0 ]] && exit 1
    fi

    if ! apt-config dump | grep "Proxy" &>/dev/null
    then
        printf "\n\n\e[31m%s %s\e[0m\n\n" \
            "[!] The apt proxy isn't set up correctly. This shouldn't" \
            "happen...stopping"
        exit 1
    fi

    curl --max-time 5 "$APT_CACHE_SERVER" 1>/dev/null 2>$STDERR_LOG_PATH &
    task_output $! "$STDERR_LOG_PATH" \
        "Check connection to apt cache server at '$APT_CACHE_SERVER'"
    if [[ $? -ne 0 ]]
    then
        printf "\n\e[36m%s %s %s %s\e[0m\n\n" \
            "[TIP] Change the APT_CACHE_SERVER line in" \
            "'./DebianInstaller/install_constants' to your new apt cache" \
            "server url, or remove the line entirely if you aren't using" \
            "an apt cache server"
        exit 1
    fi
fi

if ! grep "^apt_update$" $COMPLETION_FILE &>/dev/null
then
    apt-get update >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Update apt"
    [[ $? -ne 0 ]] && exit 1

    echo "apt_update" >> $COMPLETION_FILE
fi

debconf-set-selections > /dev/null 2>&1 <<EOF
keyboard-configuration keyboard-configuration/layoutcode string us
keyboard-configuration keyboard-configuration/modelcode string pc105
keyboard-configuration keyboard-configuration/variantcode string
console-setup console-setup/charmap47 select UTF-8
EOF

if ! grep "^install_firmware$" $COMPLETION_FILE &>/dev/null
then
    apt-get install --yes isenkram-cli \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Install isenkram-cli"
    [[ $? -ne 0 ]] && exit 1

    # Can't just use task_output because for some reason isenkram returns 1
    # if there's no firmware to install, which isn't an error.
    printf "\r\e[36m[%s]\e[0m %s" "..." "Auto-install firmware with isenkram"
    isenkram-autoinstall-firmware >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH"
    exit_code=$?
    if [[ $exit_code -lt 2 ]]
    then
        printf "\r\e[32m[Success]\e[0m %s\n" "Auto-install firmware with isenkram"
    elif [[ $exit_code -gt 1 ]]
    then
        printf "\r\e[31m[Error]\e[0m %s (Exit code: %d)\n" "$task_message" "$exit_code"
        printf "\e[31m[!] Check error log: %s\e[0m\n" "$stderr_path"
        exit 1
    fi
    unset exit_code

    apt-get purge --yes isenkram-cli \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Remove isenkram-cli"
    [[ $? -ne 0 ]] && exit 1
    echo "install_firmware" >> $COMPLETION_FILE
fi

if [[ -n "$DESKTOP_ENVIRONMENT" ]]
then
    if ! grep "^install_desktop_environment$" $COMPLETION_FILE &>/dev/null
    then
        case "$DESKTOP_ENVIRONMENT" in
            "gnome")
                apt-get install --no-install-recommends --yes \
                    gdm3 gnome-backgrounds gnome-bluetooth-sendto \
                    gnome-control-center gnome-keyring gnome-menus \
                    gnome-session gnome-settings-daemon gnome-shell \
                    orca gnome-sushi adwaita-icon-theme glib-networking \
                    gsettings-desktop-schemas evince gnome-calculator \
                    gnome-calendar gnome-terminal gnome-software \
                    gnome-text-editor gnome-snapshot tecla loupe nautilus \
                    totem simple-scan zenity evolution-data-server \
                    fonts-cantarell gstreamer1.0-packagekit \
                    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
                    gvfs-backends gvfs-fuse libatk-adaptor libcanberra-pulse \
                    libglib2.0-bin libpam-gnome-keyring gir1.2-gnomedesktop-3.0 \
                    >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
                task_output $! "$STDERR_LOG_PATH" "Install gnome"
                [[ $? -ne 0 ]] && exit 1
                ;;
            *)
                printf "\n\n\e[31m%s\e\n\n" \
                    "[!] Unsupported desktop environment: '$DESKTOP_ENVIRONMENT'"
                exit 1
                ;;
        esac

        apt-get install --yes \
            fonts-recommended fonts-noto* \
            plymouth plymouth-themes \
            mesa-vulkan-drivers \
            system-config-printer-common system-config-printer-udev cups \
            power-profiles-daemon pipewire-audio \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Install desktop environment helper packages (fonts, pipewire, etc)"
        [[ $? -ne 0 ]] && exit 1
        echo "install_desktop_environment" >> $COMPLETION_FILE
    fi
fi

if ! grep "^install_general_system_packages$" $COMPLETION_FILE &>/dev/null
then
    apt-get install --yes \
        locales neovim curl wget git unattended-upgrades sudo \
        linux-image-amd64 grub-efi-amd64-bin \
        cryptsetup cryptsetup-initramfs \
        efibootmgr efivar \
        network-manager wpasupplicant \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Install general system packages"
    [[ $? -ne 0 ]] && exit 1
    echo "install_general_system_packages" >> $COMPLETION_FILE
fi

# TODO: Implement checks for locale and timezone to see if they've been set
{
    # Set the keyboard orientation
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/default/locale
    update-locale LANG=en_US.UTF-8
} >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
task_output $! "$STDERR_LOG_PATH" "Configure locale: 'en_US.UTF-8'"
[[ $? -ne 0 ]] && exit 1

if ! cmp -s /usr/share/zoneinfo/America/Chicago /etc/localtime &>/dev/null
then
    ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Set timezone: 'America/Chicago'"
    [[ $? -ne 0 ]] && exit 1
fi

if ! grep "^generate_locale$" $COMPLETION_FILE &>/dev/null
then
    locale-gen >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Generate locale"
    [[ $? -ne 0 ]] && exit 1

    echo "generate_locale" >> $COMPLETION_FILE
fi

{
    add_initramfs_module "usb_storage"
    add_initramfs_module "usbhid"
    add_initramfs_module "hid_generic"
    add_initramfs_module "nls_cp437"
    add_initramfs_module "nls_utf8"
    add_initramfs_module "nls_ascii"
} >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
task_output $! "$STDERR_LOG_PATH" "Add modules to initramfs for USB decryption"
[[ $? -ne 0 ]] && exit 1

if ! grep "^configure_grub$" $COMPLETION_FILE &>/dev/null
then
    if [[ -f "/usr/share/grub/default/grub" ]]
    then
        cp /usr/share/grub/default/grub /etc/default/grub \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Configure Grub"
        [[ $? -ne 0 ]] && exit 1
    fi

    LUKS_DEVICE_UUID="$(blkid -s UUID -o value $ROOT_PARTITION)"

    if [[ -z "$LUKS_DEVICE_UUID" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] Cannot get the UUID of '$ROOT_PARTITION'." \
            "This is fatal... stopping"
        exit 1
    fi

    if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub &>/dev/null
    then
        echo "GRUB_CMDLINE_LINUX_DEFAULT='quiet splash'" >> /etc/default/grub
    else
        sed -i \
            "/^GRUB_CMDLINE_LINUX_DEFAULT=/c\GRUB_CMDLINE_LINUX_DEFAULT='quiet splash'" /etc/default/grub
    fi

    if ! grep "^GRUB_GFXMODE" /etc/default/grub &>/dev/null
    then
        echo 'GRUB_GFXMODE=1920x1080' >> /etc/default/grub
    else
        sed -i \
            '/^GRUB_GFXMODE/c\GRUB_GFXMODE=1920x1080' /etc/default/grub
    fi

    if ! grep "^GRUB_TIMEOUT" /etc/default/grub &>/dev/null
    then
        echo 'GRUB_TIMEOUT=0' >> /etc/default/grub
    else
        sed -i \
            '/^GRUB_TIMEOUT/c\GRUB_TIMEOUT=0' /etc/default/grub
    fi

    if ! grep "^GRUB_TIMEOUT_STYLE" /etc/default/grub &>/dev/null
    then
        echo 'GRUB_TIMEOUT_STYLE=hidden' >> /etc/default/grub
    else
        sed -i \
            '/^GRUB_TIMEOUT_STYLE/c\GRUB_TIMEOUT_STYLE=hidden' /etc/default/grub
    fi

    echo "configure_grub" >> $COMPLETION_FILE
fi

if ! grep "^grub_install$" $COMPLETION_FILE &>/dev/null
then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi \
        --bootloader-id=debian --recheck $DISK \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Install grub"
    [[ $? -ne 0 ]] && exit 1

    echo "grub_install" >> $COMPLETION_FILE
fi

if ! grep "^grub_update$" $COMPLETION_FILE &>/dev/null
then
    update-grub >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Apply Grub configuration"
    [[ $? -ne 0 ]] && exit 1

    echo "grub_update" >> $COMPLETION_FILE
fi

if ! grep "^update_initramfs$" $COMPLETION_FILE &>/dev/null
then
    update-initramfs -u -k all >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Update the initramfs"
    [[ $? -ne 0 ]] && exit 1

    echo "update_initramfs" >> $COMPLETION_FILE
fi

if dpkg -s plymouth &>/dev/null
then
    if ! grep "^set_splash_theme$" $COMPLETION_FILE &>/dev/null
    then
        plymouth-set-default-theme -R moonlight \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Set the splash theme with plymouth-themes"

        echo "set_splash_theme" >> $COMPLETION_FILE
    fi
fi

if ! id administrator &>/dev/null
then
    home_flag='--create-home'
    if [[ -d '/home/administrator' ]]
    then
        home_flag='--no-create-home'
    fi

    useradd --user-group $home_flag --uid 1000 -s /bin/bash administrator \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Create administrator account"
    [[ $? -ne 0 ]] && exit 1
fi

# Double check the admin account is created
if ! id administrator &>/dev/null
then
    printf "\n\e[31m%s %s\e[0m\n" "[!] user 'administrator' doesn't exist..." \
        "this shouldn't happen... stopping"
    exit 1
fi

if ! groups administrator | grep "sudo" &>/dev/null
then
    usermod -aG sudo administrator >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Add administrator to the sudo group"
    [[ $? -ne 0 ]] && exit 1
fi

# No need for completion tracking, just set the password
echo administrator:"$admin_password" | chpasswd \
    >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
task_output $! "$STDERR_LOG_PATH" "Set administrator password"
[[ $? -ne 0 ]] && exit 1

if ! id $username &>/dev/null
then
    home_flag='--create-home'
    if [[ -d "/home/$username" ]]
    then
        home_flag='--no-create-home'
    fi

    useradd --user-group $home_flag --uid 1001 -s /bin/bash $username \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Create user account: '$username'"
    [[ $? -ne 0 ]] && exit 1
fi

# Double check the user account is created
if ! id $username &>/dev/null
then
    printf "\n\e[31m%s %s\e[0m\n" "[!] user '$username' doesn't exist..." \
        "this shouldn't happen... stopping"
    exit 1
fi

if [[ -d "/home/administrator" ]]
then
    if ! [[ -d /home/administrator/DebianPreset ]]
    then
        cd /home/administrator
        git clone https://www.github.com/JustScott/DebianPreset \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Clone DebianPreset to administrator's \$HOME"
    elif [[ -d /home/administrator/DebianPreset ]]
    then
        chown administrator:administrator -R /home/administrator/DebianPreset
    fi
else
    printf "\n\e[31m%s %s\e[0m\n" \
        "[!] administrator's \$HOME doesn't exist, this shouldn't" \
        "happen... stopping"
    exit 1
fi

if [[ -d "/home/$username" ]]
then
    if ! [[ -d /home/$username/DebianPreset ]]
    then
        cd /home/$username
        git clone https://www.github.com/JustScott/DebianPreset \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Clone DebianPreset to $username's \$HOME"
    elif [[ -d /home/$username/DebianPreset ]]
    then
        chown $username:$username -R /home/$username/DebianPreset
    fi
else
    printf "\n\e[31m%s %s\e[0m\n" \
        "[!] $username's \$HOME doesn't exist, this shouldn't" \
        "happen... stopping"
    exit 1
fi

cd /

if [[ -n "$user_password" ]]
then
    echo "$username":"$user_password" | chpasswd \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Set ${username}'s password"
    [[ $? -ne 0 ]] && exit 1
else
    # No need for completion tracking
    passwd -d "$username" >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Make ${username}'s account passwordless"
    [[ $? -ne 0 ]] && exit 1
fi

if dpkg -s gdm3 &>dev/null
then
    # No need for completion tracking
    echo -e "[User]\nSystemAccount=true" \
        > /var/lib/AccountsService/users/administrator &
    task_output $! "$STDERR_LOG_PATH" "Remove administrator from gdm login screen"
    [[ $? -ne 0 ]] && exit 1
fi

# No need for completion tracking
if ! systemctl is-enabled NetworkManager &>/dev/null
then
    systemctl enable NetworkManager >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Enable NetworkManager service"
    [[ $? -ne 0 ]] && exit 1
fi

# No need for completion tracking
if ! systemctl is-enabled unattended-upgrades &>/dev/null
then
    systemctl enable unattended-upgrades >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Enable unattended-upgrades service"
    [[ $? -ne 0 ]] && exit 1
fi
