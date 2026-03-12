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
    [[ $? -ne 0 ]] && exit 1
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

if ! grep "^apt_install_system_packages$" $COMPLETION_FILE &>/dev/null
then
    apt-get install --no-install-recommends --yes gnome-core \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Install gnome"
    [[ $? -ne 0 ]] && exit 1

    apt-get install --yes locales neovim curl wget \
        git efibootmgr efivar linux-image-amd64 \
        grub-efi-amd64-bin network-manager sudo \
        plymouth plymouth-themes \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Install system packages"
    [[ $? -ne 0 ]] && exit 1

    echo "apt_install_system_packages" >> $COMPLETION_FILE
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

if ! grep "^configure_grub$" $COMPLETION_FILE &>/dev/null
then
    if [[ -f "/usr/share/grub/default/grub" ]]
    then
        cp /usr/share/grub/default/grub /etc/default/grub \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Configure Grub"
        [[ $? -ne 0 ]] && exit 1
    fi

    if ! grep "^GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub &>/dev/null
    then
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> /etc/default/grub
    else
        sed -i \
            '/^GRUB_CMDLINE_LINUX_DEFAULT/c\GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' /etc/default/grub
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
        --bootloader-id=Debian $DISK \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Install grub"
    [[ $? -ne 0 ]] && exit 1

    echo "grub_install" >> $COMPLETION_FILE
fi

if ! grep "^grub_mkconfig$" $COMPLETION_FILE &>/dev/null
then
    grub-mkconfig -o /boot/grub/grub.cfg \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Apply Grub configuration"
    [[ $? -ne 0 ]] && exit 1

    echo "grub_mkconfig" >> $COMPLETION_FILE
fi

if ! grep "^update_initramfs$" $COMPLETION_FILE &>/dev/null
then
    update-initramfs -u >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Update the initramfs"
    [[ $? -ne 0 ]] && exit 1

    echo "update_initramfs" >> $COMPLETION_FILE
fi

if ! grep "^set_splash_theme$" $COMPLETION_FILE &>/dev/null
then
    plymouth-set-default-theme -R moonlight \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Set the splash theme with plymouth-themes"

    echo "set_splash_theme" >> $COMPLETION_FILE
fi

if ! id administrator &>/dev/null
then
    useradd -Um -s /bin/bash administrator \
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
    useradd -Um -s /bin/bash $username  \
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
    cd /home/administrator
    git clone https://www.github.com/JustScott/DebianPreset &>/dev/null
    task_output $! "$STDERR_LOG_PATH" \
        "Clone DebianPreset to administrator's \$HOME"
    if [[ -d /home/administrator/DebianPreset ]]
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
    cd /home/$username
    git clone https://www.github.com/JustScott/DebianPreset &>/dev/null
    task_output $! "$STDERR_LOG_PATH" \
        "Clone DebianPreset to $username's \$HOME"
    if [[ -d /home/$username/DebianPreset ]]
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

# No need for completion tracking
passwd -d $username >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
task_output $! "$STDERR_LOG_PATH" "Make user account passwordless"
[[ $? -ne 0 ]] && exit 1

# No need for completion tracking
echo -e "[User]\nSystemAccount=true" \
    > /var/lib/AccountsService/users/administrator &
task_output $! "$STDERR_LOG_PATH" "Remove administrator from gdm login screen"
[[ $? -ne 0 ]] && exit 1

# No need for completion tracking
systemctl enable NetworkManager >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
task_output $! "$STDERR_LOG_PATH" "Enable NetworkManager service"
[[ $? -ne 0 ]] && exit 1
