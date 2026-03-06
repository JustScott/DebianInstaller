#!/bin/bash
#
# start_install.sh - part of the DebianInstaller project
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

# TODO: Add logic for selecting disk
# TODO: Check that disk and partitions exist before running

# TODO: Add section for checking that all needed files are accessible

INSTALLATION_VARIABLES_FILE=/tmp/activate_installation_variables.sh

PRETTY_OUTPUT_LIBRARY=./DebianInstaller/pretty_output_library.sh

COMPLETION_FILE=./start_install_completion.txt

INSTALL_CONSTANTS_FILE=./DebianInstaller/install_constants

export DEBIAN_FRONTEND=noninteractive

if ! source $INSTALL_CONSTANTS_FILE &>/dev/null
then
    printf "\n\n\e[31m%s %s\e[0m\n\n" \
        "[!] Couldn't source the install_constants file. Make sure" \
        "to run \`bash ./DebianInstaller/start_install.sh\`"
    exit 1
fi

if ! source $PRETTY_OUTPUT_LIBRARY &>/dev/null
then
    printf "\n\n\e[31m%s %s\e[0m\n\n" \
        "[!] Couldn't source the pretty output library. Make sure" \
        "to run \`bash ./DebianInstaller/start_install.sh\`"
    exit 1
fi

{
    get_name() {
        declare -g name=""
        local name_verify

        while : 
        do
            read -p 'Enter Name: ' name
            read -p 'Verify Name: ' name_verify

            if [[ -z "$name" ]]
            then
                clear
                echo -e " - Name Can't Be Empty - \n"
                continue
            fi

            if [[ $name == $name_verify ]]
            then
                clear
                echo -e " - Set as '$name' - \n"
                sleep .5
                break
            else 
                clear
                echo -e " - Names Don't Match - \n"
            fi
        done
    }

    get_user_password() {
        declare -g user_password=""
        local user_password_verify

        echo -e "\n - Set Password for '$1' - "
        while :
        do
            read -s -p 'Set Password: ' user_password
            read -s -p $'\nverify Password: ' user_password_verify

            if [[ $user_password == $user_password_verify ]]
            then
                clear
                echo -e " - Set password for $1! - \n"
                sleep 1
                break
            else
                clear
                echo -e " - Passwords Don't Match - \n"
            fi
        done
    }
}

if [[ "$(whoami)" != "root" ]]
then
    printf "\n\e[31m%s\e[0m\n" "[!] Must run script as root"
    exit 1
fi

check_required_install_constants()
{
    if [[ -z "$DISK" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$DISK constant not set, this is fatal...stopping"
        exit 1
    fi
    if [[ -z "$EFI_PARTITION" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$DISK constant not set, this is fatal...stopping"
        exit 1
    fi
    if [[ -z "$ROOT_PARTITION" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$DISK constant not set, this is fatal...stopping"
        exit 1
    fi
}

check_required_install_constants

# We should remove the admin_password from the install variables file
# if set_admin_password isn't in the completion file, because it could
# mean the user wants to enter a new password
if ! grep "^set_admin_password$" $COMPLETION_FILE &>/dev/null
then
    sed -i '/^admin_password=/d' $INSTALLATION_VARIABLES_FILE
fi
if ! grep "^admin_password=" $INSTALLATION_VARIABLES_FILE &>/dev/null
then
    clear 
    echo -e "* Prompt [1/2] *\n"
    get_user_password "administrator"
    if [[ -z "$user_password" ]]
    then
        printf "\n\n\e[31m%s\e[0m\n\n" "[!] Must set admin password... stopping"
        exit 1
    fi

    echo -e "\nadmin_password=\"$user_password\"" >> $INSTALLATION_VARIABLES_FILE

    echo "set_admin_password" >> $COMPLETION_FILE
fi

if ! grep "^set_username$" $COMPLETION_FILE &>/dev/null
then
    sed -i '/^username=/d' $INSTALLATION_VARIABLES_FILE
fi
if ! grep "^username=" $INSTALLATION_VARIABLES_FILE &>/dev/null
then
    clear
    echo -e "* Prompt [2/2] *\n"
    echo ' - Set User Name - '
    get_name
    if [[ -z "$name" ]]
    then
        printf "\n\n\e[31m%s\e[0m\n\n" "[!] Must set username... stopping"
        exit 1
    fi
    echo -e "\nusername=\"$name\"" >> $INSTALLATION_VARIABLES_FILE

    echo "set_username" >> $COMPLETION_FILE
fi

clear

if ! cmp -s ./DebianInstaller/configuration_files/sources.list \
    /etc/apt/sources.list &>/dev/null
then
    cp ./DebianInstaller/configuration_files/sources.list /etc/apt/sources.list \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Copy sources.list to the current live system"
    [[ $? -ne 0 ]] && exit 1
fi

if ! cmp -s /usr/share/zoneinfo/America/Chicago /etc/localtime &>/dev/null
then
    ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Set live system timezone: 'America/Chicago'"
    [[ $? -ne 0 ]] && exit 1
fi

if [[ -n "$APT_CACHE_SERVER" && -n "$APT_CACHE_FILE" ]]
then
    if ! grep "Acquire::http::Proxy \"$APT_CACHE_SERVER\";"\
        $APT_CACHE_FILE &>/dev/null
    then
        echo "Acquire::http::Proxy \"$APT_CACHE_SERVER\";" \
            > $APT_CACHE_FILE &
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
fi

if ! grep "^apt_update$" $COMPLETION_FILE &>/dev/null
then
    apt-get update >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Update apt"
    [[ $? -ne 0 ]] && exit 1

    echo "apt_update" >> $COMPLETION_FILE
fi

if ! grep "^apt_upgrade$" $COMPLETION_FILE &>/dev/null
then
    apt-get upgrade --yes >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "upgrade live system with apt"
    [[ $? -ne 0 ]] && exit 1

    echo "apt_upgrade" >> $COMPLETION_FILE
fi

if ! grep "^apt_install_debootstrap$" $COMPLETION_FILE &>/dev/null
then
    apt-get install --yes arch-install-scripts debootstrap \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "Install arch-install-scripts and debootstrap"
    [[ $? -ne 0 ]] && exit 1

    echo "apt_install_debootstrap" >> $COMPLETION_FILE
fi

if ! grep "^mkfs_boot$" $COMPLETION_FILE &>/dev/null
then
    echo 'y' | mkfs.fat -F 32 $EFI_PARTITION \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Format boot partition with FAT32"
    [[ $? -ne 0 ]] && exit 1

    echo "mkfs_boot" >> $COMPLETION_FILE
fi

if ! grep "^mkfs_root$" $COMPLETION_FILE &>/dev/null
then
    echo 'y' | mkfs.ext4 $ROOT_PARTITION \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Configure System For EXT4"
    [[ $? -ne 0 ]] && exit 1

    echo "mkfs_root" >> $COMPLETION_FILE
fi

if ! grep "^mount_root$" $COMPLETION_FILE &>/dev/null
then
    mount $ROOT_PARTITION /mnt >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Mount the root partition"
    [[ $? -ne 0 ]] && exit 1

    echo "mount_root" >> $COMPLETION_FILE
fi

if ! grep "^mount_boot$" $COMPLETION_FILE &>/dev/null
then
    mount --mkdir $EFI_PARTITION /mnt/boot/efi \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Mount the boot partition"
    [[ $? -ne 0 ]] && exit 1

    echo "mount_boot" >> $COMPLETION_FILE
fi

if ! grep "^mkswap$" $COMPLETION_FILE &>/dev/null
then
    mkswap -U clear --size 4G --file /mnt/swapfile \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Create 4GB swapfile"
    [[ $? -ne 0 ]] && exit 1

    echo "mkswap" >> $COMPLETION_FILE
fi

if ! grep "^swapon$" $COMPLETION_FILE &>/dev/null
then
    swapon /mnt/swapfile >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Enable the swapfile"
    [[ $? -ne 0 ]] && exit 1

    echo "swapon" >> $COMPLETION_FILE
fi

if ! grep "^run_debootstrap$" $COMPLETION_FILE &>/dev/null
then
    if [[ -n "$APT_CACHE_SERVER" ]]
    then
        debootstrap --arch amd64 stable /mnt \
            $APT_CACHE_SERVER/deb.debian.org/debian \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Run debootstrap (this could take a while on slow internet)"
        [[ $? -ne 0 ]] && exit 1
    else
        debootstrap --arch amd64 stable /mnt https://deb.debian.org/debian \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Run debootstrap (this could take a while on slow internet)"
        [[ $? -ne 0 ]] && exit 1
    fi

    echo "run_debootstrap" >> $COMPLETION_FILE
fi

if ! grep "^genfstab$" $COMPLETION_FILE &>/dev/null
then
    genfstab -U /mnt > /mnt/etc/fstab 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Generate the fstab file"
    if [[ $? -ne 0 ]]
    then
        printf "\n\n\e[31m%s\n%s\n%s\e[0m\n\n" \
            "[!] It's likely debootstrap failed, and not genfstab" \
            "     - try removing 'debootstrap' from the completion" \
            "       file and running again"
        exit 1
    fi

    echo "genfstab" >> $COMPLETION_FILE
fi

if ! cmp -s /etc/hosts /mnt/etc/hosts &>/dev/null
then
    cp /etc/hosts /mnt/etc/hosts >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Copy the hosts file to the new system"
    [[ $? -ne 0 ]] && exit 1
fi

if ! cmp -s ./DebianInstaller/configuration_files/sources.list \
    /mnt/etc/apt/sources.list &>/dev/null
then
    cp ./DebianInstaller/configuration_files/sources.list \
        /mnt/etc/apt/sources.list \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Copy sources.list to the new system"
    [[ $? -ne 0 ]] && exit 1
fi

if ! grep "^set_hostname$" $COMPLETION_FILE &>/dev/null
then
    echo "debian" > /mnt/etc/hostname >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Set the new systems hostname to 'debian'"
    [[ $? -ne 0 ]] && exit 1

    echo "set_hostname" >> $COMPLETION_FILE
fi

if ! cmp -s $PRETTY_OUTPUT_LIBRARY \
    /mnt/$(basename $PRETTY_OUTPUT_LIBRARY) &>/dev/null
then
    cp $PRETTY_OUTPUT_LIBRARY /mnt/ \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "Copy '$PRETTY_OUTPUT_LIBRARY' to the new system"
    [[ $? -ne 0 ]] && exit 1
fi

if ! cmp -s ./DebianInstaller/finish_install.sh /mnt/finish_install.sh &>/dev/null
then
    cp ./DebianInstaller/finish_install.sh /mnt \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "Copy 'finish_install.sh' to the new system"
    [[ $? -ne 0 ]] && exit 1
fi

if ! cmp -s $INSTALLATION_VARIABLES_FILE \
    /mnt/$(basename $INSTALLATION_VARIABLES_FILE) &>/dev/null
then
    cp $INSTALLATION_VARIABLES_FILE /mnt/ \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "Copy '$INSTALLATION_VARIABLES_FILE' to the new system"
    [[ $? -ne 0 ]] && exit 1
fi


if ! cmp -s $INSTALL_CONSTANTS_FILE \
    /mnt/$(basename $INSTALL_CONSTANTS_FILE) &>/dev/null
then
    cp $INSTALL_CONSTANTS_FILE /mnt/ \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "Copy '$INSTALL_CONSTANTS_FILE' to the new system"
    [[ $? -ne 0 ]] && exit 1
fi

arch-chroot /mnt /bin/bash finish_install.sh
