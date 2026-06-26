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
    if [[ -z "$EFI_PARTITION" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$EFI_PARTITION constant not set, this is fatal...stopping"
        return 1
    fi
    if [[ -z "$BOOT_PARTITION" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$BOOT_PARTITION constant not set, this is fatal...stopping"
        return 1
    fi
    if [[ -z "$ROOT_PARTITION" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$ROOT_PARTITION constant not set, this is fatal...stopping"
        return 1
    fi
    if [[ -z "$HOME_PARTITION" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$HOME_PARTITION constant not set, this is fatal...stopping"
        return 1
    fi
    if [[ "$OVERWRITE_HOME_PARTITION" != 'y' && "$OVERWRITE_HOME_PARTITION" != 'n' ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" \
            "[!] \$OVERWRITE_HOME_PARTITION constant must be 'y' or 'n'," \
            "this is fatal...stopping"
        return 1
    fi

    if [[ -z "$ADMIN_USERNAME" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$ADMIN_USERNAME constant not set, this is fatal...stopping"
        return 1
    fi

    if [[ -z "$ADMIN_PASSWORD" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$ADMIN_PASSWORD constant not set, this is fatal...stopping"
        return 1
    fi

    if [[ -z "$USER_USERNAME" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$USER_USERNAME constant not set, this is fatal...stopping"
        return 1
    fi

    if [[ -z "$TIMEZONE" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$TIMEZONE constant not set, this is fatal...stopping"
        return 1
    fi

    if ! [[ -f "/usr/share/zoneinfo/${TIMEZONE}" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" \
            "[!] \$TIMEZONE constant must be a valid timezone from" \
            "/usr/share/zoneinfo, this is fatal...stopping"
        return 1
    fi

    return 0
}

check_required_install_constants || exit 1

if [[ -n "$LUKS_PASSWORD" || -n "$LUKS_KEYFILE_PARTITION" ]]
then
    declare -r ENCRYPT_SYSTEM='y'
else
    declare -r ENCRYPT_SYSTEM='n'
fi

check_for_cache_server()
{
    if [[ -n "$APT_CACHE_SERVER" ]]
    then
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
            return 1
        fi
    fi

    return 0
}

check_for_cache_server || exit 1

populate_installation_variables_file()
{
    if ! grep "^ADMIN_USERNAME='$ADMIN_USERNAME'" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
    then
        if grep "^ADMIN_USERNAME=" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
        then
            sed -i '/^ADMIN_USERNAME/d' file &>/dev/null
        fi
        echo "ADMIN_USERNAME='$ADMIN_USERNAME'" >> "$INSTALLATION_VARIABLES_FILE"
    fi

    if ! grep "^ADMIN_PASSWORD='$ADMIN_PASSWORD'" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
    then
        if grep "^ADMIN_PASSWORD=" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
        then
            sed -i '/^ADMIN_PASSWORD/d' file &>/dev/null
        fi
        echo "ADMIN_PASSWORD='$ADMIN_PASSWORD'" >> "$INSTALLATION_VARIABLES_FILE"
    fi

    if ! grep "^USER_USERNAME='$USER_USERNAME'" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
    then
        if grep "^USER_USERNAME=" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
        then
            sed -i '/^USER_USERNAME/d' file &>/dev/null
        fi
        echo "USER_USERNAME='$USER_USERNAME'" >> "$INSTALLATION_VARIABLES_FILE"
    fi

    if ! grep "^USER_PASSWORD='$USER_PASSWORD'" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
    then
        if grep "^USER_PASSWORD=" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
        then
            sed -i '/^USER_PASSWORD/d' file &>/dev/null
        fi
        echo "USER_PASSWORD='$USER_PASSWORD'" >> "$INSTALLATION_VARIABLES_FILE"
    fi

    if ! grep "^TIMEZONE='$TIMEZONE'" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
    then
        if grep "^TIMEZONE=" "$INSTALLATION_VARIABLES_FILE" &>/dev/null
        then
            sed -i '/^TIMEZONE/d' file &>/dev/null
        fi
        echo "TIMEZONE='$TIMEZONE'" >> "$INSTALLATION_VARIABLES_FILE"
    fi
}

populate_installation_variables_file

unset ADMIN_USERNAME
unset ADMIN_PASSWORD
unset USER_NAME
unset USER_PASSWORD
unset TIMEZONE

create_luks_keyfile_on_usb()
{
    if ! [[ -b /dev/disk/by-label/keyfile_usb ]]
    then
        echo 'y' | mkfs.fat -F 32 -n "keyfile_usb" $LUKS_KEYFILE_PARTITION \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Format keyfile_usb partition with FAT32"
        [[ $? -ne 0 ]] && exit 1
    fi

    if ! [[ -d /media/keyfile_usb ]]
    then
        mount --mkdir /dev/disk/by-label/keyfile_usb /media/keyfile_usb \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount keyfile_usb partition"
        [[ $? -ne 0 ]] && exit 1
    fi

    if ! [[ -f /media/keyfile_usb/luks_keyfile ]]
    then
        dd if=/dev/urandom of=/media/keyfile_usb/luks_keyfile bs=1024 count=2 \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Create luks_keyfile on keyfile_usb"
        [[ $? -ne 0 ]] && exit 1

        chmod 400 /media/keyfile_usb/luks_keyfile \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Set permissions on luks_keyfile (400)"
        [[ $? -ne 0 ]] && exit 1
    fi
}

luks_format_root_with_keyfile()
{
    if ! grep "^luksFormatRootWithKeyfile$" $COMPLETION_FILE &>/dev/null
    then
        cryptsetup luksFormat --key-file /media/keyfile_usb/luks_keyfile \
            --batch-mode $ROOT_PARTITION \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "luksFormat root ($ROOT_PARTITION) with USB keyfile"
        [[ $? -ne 0 ]] && exit 1

        echo "luksFormatRootWithKeyfile" >> $COMPLETION_FILE
    fi

    return 0
}

luks_format_home_with_keyfile()
{
    if ! grep "^luksFormatHomeWithKeyfile$" $COMPLETION_FILE &>/dev/null
    then
        cryptsetup luksFormat --key-file /media/keyfile_usb/luks_keyfile \
            --batch-mode $HOME_PARTITION \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "luksFormat home ($HOME_PARTITION) with USB keyfile"
        [[ $? -ne 0 ]] && exit 1

        echo "luksFormatHomeWithKeyfile" >> $COMPLETION_FILE
    fi

    return 0
}

luks_format_root_with_passphrase() {
    if [[ -z "$LUKS_PASSWORD" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "Luks password not set in 'install_constants' file"
        exit 1
    fi

    if ! grep "^luksFormatRootWithPassphrase$" $COMPLETION_FILE &>/dev/null
    then
        echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat -s 512 -h sha512 \
            --key-file=- $ROOT_PARTITION >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "luksFormat root ($ROOT_PARTITION) with passphrase"
        [[ $? -ne 0 ]] && exit 1

        echo "luksFormatRootWithPassphrase" >> $COMPLETION_FILE
    fi

    return 0
}

luks_format_home_with_passphrase() {
    if [[ -z "$LUKS_PASSWORD" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "Luks password not set in 'install_constants' file"
        exit 1
    fi

    if ! grep "^luksFormatHomeWithPassphrase$" $COMPLETION_FILE &>/dev/null
    then
        echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat -s 512 -h sha512 \
            --key-file=- $HOME_PARTITION >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "luksFormat home ($HOME_PARTITION) with passphrase"
        [[ $? -ne 0 ]] && exit 1

        echo "luksFormatHomeWithPassphrase" >> $COMPLETION_FILE
    fi

    return 0
}

luks_open_root()
{
    if ! grep "^luksOpenRoot$" $COMPLETION_FILE &>/dev/null
    then
        if [[ -n "$LUKS_PASSWORD" ]]
        then
            echo -n "$LUKS_PASSWORD" | cryptsetup open --key-file=- $ROOT_PARTITION \
                crypt_root >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted root partition with passphrase"
            [[ $? -ne 0 ]] && exit 1
        else
            cryptsetup open --key-file /media/keyfile_usb/luks_keyfile \
                $ROOT_PARTITION crypt_root >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted root partition with USB keyfile"
            [[ $? -ne 0 ]] && exit 1
        fi

        echo "luksOpenRoot" >> $COMPLETION_FILE
    fi
}

luks_open_home()
{
    if ! grep "^luksOpenHome$" $COMPLETION_FILE &>/dev/null
    then
        if [[ -n "$LUKS_PASSWORD" ]]
        then
            echo -n "$LUKS_PASSWORD" | cryptsetup open --key-file=- $HOME_PARTITION \
                crypt_home >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted home partition with passphrase"
            [[ $? -ne 0 ]] && exit 1
        else
            cryptsetup open --key-file /media/keyfile_usb/luks_keyfile \
                $HOME_PARTITION crypt_home >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted home partition with USB keyfile"
            [[ $? -ne 0 ]] && exit 1
        fi

        echo "luksOpenHome" >> $COMPLETION_FILE
    fi
}

format_partitions()
{
    local home_partition="$1"
    local root_partition="$2"

    if ! grep "^mkfs_efi$" $COMPLETION_FILE &>/dev/null
    then
        echo 'y' | mkfs.fat -F 32 $EFI_PARTITION \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Format EFI partition ($EFI_PARTITION) with FAT32"
        [[ $? -ne 0 ]] && exit 1

        echo "mkfs_efi" >> $COMPLETION_FILE
    fi

    if ! grep "^mkfs_boot$" $COMPLETION_FILE &>/dev/null
    then
        echo 'y' | mkfs.ext4 $BOOT_PARTITION \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Format boot partition ($BOOT_PARTITION) with EXT4"
        [[ $? -ne 0 ]] && exit 1

        echo "mkfs_boot" >> $COMPLETION_FILE
    fi

    if [[ $OVERWRITE_HOME_PARTITION == 'y' ]]
    then
        if ! grep "^mkfs_home$" $COMPLETION_FILE &>/dev/null
        then
            echo 'y' | mkfs.ext4 "$home_partition" \
                >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Format home partition ($HOME_PARTITION) with EXT4"
            [[ $? -ne 0 ]] && exit 1

            echo "mkfs_home" >> $COMPLETION_FILE
        fi
    fi

    if ! grep "^mkfs_root$" $COMPLETION_FILE &>/dev/null
    then
        echo 'y' | mkfs.ext4 "$root_partition" \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Format root partition ($ROOT_PARTITION) with EXT4"
        [[ $? -ne 0 ]] && exit 1

        echo "mkfs_root" >> $COMPLETION_FILE
    fi
}

mount_partitions()
{
    local home_partition="$1"
    local root_partition="$2"

    if ! grep "^mount_root$" $COMPLETION_FILE &>/dev/null
    then
        mount "$root_partition" /mnt >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount the root partition ($ROOT_PARTITION)"
        [[ $? -ne 0 ]] && exit 1

        echo "mount_root" >> $COMPLETION_FILE
    fi

    if ! grep "^mount_home$" $COMPLETION_FILE &>/dev/null
    then
        mount --mkdir "$home_partition" /mnt/home \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount the home partition ($HOME_PARTITION)"
        [[ $? -ne 0 ]] && exit 1

        echo "mount_home" >> $COMPLETION_FILE
    fi

    if ! grep "^mount_boot$" $COMPLETION_FILE &>/dev/null
    then
        mount --mkdir $BOOT_PARTITION /mnt/boot \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount the boot partition ($BOOT_PARTITION)"
        [[ $? -ne 0 ]] && exit 1

        echo "mount_boot" >> $COMPLETION_FILE
    fi

    if ! grep "^mount_efi$" $COMPLETION_FILE &>/dev/null
    then
        mount --mkdir $EFI_PARTITION /mnt/boot/efi \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount the efi partition ($EFI_PARTITION)"
        [[ $? -ne 0 ]] && exit 1

        echo "mount_efi" >> $COMPLETION_FILE
    fi
}

populate_crypttab()
{
    ENCRYPTED_ROOT_PARTITION_UUID="$(blkid -s UUID -o value $ROOT_PARTITION)"
    ENCRYPTED_HOME_PARTITION_UUID="$(blkid -s UUID -o value $HOME_PARTITION)"

    if [[ -z "$ENCRYPTED_ROOT_PARTITION_UUID" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] Couldn't find encrypted root partition in blkid output"
        exit 1
    fi

    if [[ -z "$ENCRYPTED_HOME_PARTITION_UUID" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] Couldn't find encrypted home partition in blkid output"
        exit 1
    fi

    if ! [[ -d /mnt/etc/ ]]
    then
        mkdir -p /mnt/etc 1>/dev/null 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Create /mnt/etc for crypttab"
        [[ $? -ne 0 ]] && exit 1
    fi

    if ! grep "$ENCRYPTED_ROOT_PARTITION_UUID" /mnt/etc/crypttab &>/dev/null
    then
        if [[ -n "$LUKS_PASSWORD" ]]
        then
            echo "crypt_root UUID=$ENCRYPTED_ROOT_PARTITION_UUID none luks,discard,keyscript=decrypt_keyctl,initramfs" \
            >> /mnt/etc/crypttab 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Add encrypted root to /mnt/etc/crypttab"
            [[ $? -ne 0 ]] && exit 1
        else
            echo "crypt_root UUID=$ENCRYPTED_ROOT_PARTITION_UUID /dev/disk/by-label/keyfile_usb:/luks_keyfile:60 luks,discard,keyscript=passdev,tries=2,initramfs" \
            >> /mnt/etc/crypttab 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Add encrypted root to /mnt/etc/crypttab"
            [[ $? -ne 0 ]] && exit 1
        fi
    fi

    if ! grep "$ENCRYPTED_HOME_PARTITION_UUID" /mnt/etc/crypttab &>/dev/null
    then
        if [[ -n "$LUKS_PASSWORD" ]]
        then
            echo "crypt_home UUID=$ENCRYPTED_HOME_PARTITION_UUID none luks,discard,keyscript=decrypt_keyctl,initramfs" \
            >> /mnt/etc/crypttab 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Add encrypted home to /mnt/etc/crypttab"
            [[ $? -ne 0 ]] && exit 1
        else
            echo "crypt_home UUID=$ENCRYPTED_HOME_PARTITION_UUID /dev/disk/by-label/keyfile_usb:/luks_keyfile:60 luks,discard,keyscript=passdev,tries=2,initramfs" \
            >> /mnt/etc/crypttab 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Add encrypted home to /mnt/etc/crypttab"
            [[ $? -ne 0 ]] && exit 1
        fi
    fi
}

configure_swap()
{
    if [[ -n "$SWAP_SIZE_IN_GB" ]]
    then
        if ! [[ "$SWAP_SIZE_IN_GB" =~ ^[1-9][0-9]*$ ]]
        then
            printf "\n\e[31m%s\e[0m\n" "[!] Invalid swap size: '$SWAP_SIZE_IN_GB'"
            exit 1
        fi

        if [[ "$SWAP_SIZE_IN_GB" -gt 32 ]]
        then
            printf "\n\e[31m%s\e[0m\n" "[!] Max swap size is 32GB"
            exit 1
        fi

        if ! grep "^mkswap$" $COMPLETION_FILE &>/dev/null
        then
            mkswap -U clear --size ${SWAP_SIZE_IN_GB}G --file /mnt/swapfile \
                >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Create ${SWAP_SIZE_IN_GB}GB swapfile"
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
    fi
}

set_timezone()
{
    local user_timezone="$1"

    if [[ -z "$user_timezone" ]]
    then
        printf "\n\e[31m%s\e[0m %s\n" "[Error]" \
            "No user timezone passed to function, this shouldn't happen. Stopping."
        exit 1
    fi

    if ! cmp -s "/usr/share/zoneinfo/${user_timezone}" /etc/localtime &>/dev/null
    then
        ln -sf "/usr/share/zoneinfo/${user_timezone}" /etc/localtime \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Set live system timezone: '$user_timezone'"
        [[ $? -ne 0 ]] && exit 1
    fi
}

set_apt_cache_server()
{
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
}

copy_apt_sources_to_live_system()
{
    if ! cmp -s ./DebianInstaller/configuration_files/sources.list \
        /etc/apt/sources.list &>/dev/null
    then
        cp ./DebianInstaller/configuration_files/sources.list /etc/apt/sources.list \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Copy sources.list to the current live system"
        [[ $? -ne 0 ]] && exit 1
    fi
}

apt_update()
{
    if ! grep "^apt_update$" $COMPLETION_FILE &>/dev/null
    then
        apt-get update >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Update apt"
        [[ $? -ne 0 ]] && exit 1

        echo "apt_update" >> $COMPLETION_FILE
    fi
}

install_debootstrap()
{
    if ! grep "^apt_install_debootstrap$" $COMPLETION_FILE &>/dev/null
    then
        apt-get install --yes arch-install-scripts debootstrap \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Install arch-install-scripts and debootstrap"
        [[ $? -ne 0 ]] && exit 1

        echo "apt_install_debootstrap" >> $COMPLETION_FILE
    fi
}

run_debootstrap()
{
    if ! grep "^run_debootstrap$" $COMPLETION_FILE &>/dev/null
    then
        if [[ -n "$APT_CACHE_SERVER" ]]
        then
            debootstrap --arch amd64 --include=curl stable /mnt \
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
}

generate_fstab_file()
{
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
}

set_hostname()
{
    if ! grep "^set_hostname$" $COMPLETION_FILE &>/dev/null
    then
        echo "debian" > /mnt/etc/hostname &
        task_output $! "$STDERR_LOG_PATH" "Set the hostname to 'debian'"
        [[ $? -ne 0 ]] && exit 1

        echo -e "127.0.0.1 localhost\n127.0.1.1 debian" > /mnt/etc/hosts &
        task_output $! "$STDERR_LOG_PATH" "Populate the '/etc/hosts' file"
        [[ $? -ne 0 ]] && exit 1

        echo "set_hostname" >> $COMPLETION_FILE
    fi
}

copy_necessary_project_files_to_new_system()
{
    if ! cmp -s ./DebianInstaller/configuration_files/sources.list \
        /mnt/etc/apt/sources.list &>/dev/null
    then
        cp ./DebianInstaller/configuration_files/sources.list \
            /mnt/etc/apt/sources.list \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Copy sources.list to the new system"
        [[ $? -ne 0 ]] && exit 1
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
}

if [[ "$ENCRYPT_SYSTEM" == "y" ]]
then
    if [[ -n "$LUKS_KEYFILE_PARTITION" ]]
    then
        create_luks_keyfile_on_usb
        luks_format_root_with_keyfile
        luks_format_home_with_keyfile
    elif [[ -n "$LUKS_PASSWORD" ]]
    then
        luks_format_root_with_passphrase
        luks_format_home_with_passphrase
    else
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "LUKS_PASSWORD or LUKS_KEYFILE_PARTITION were empty. This shouldn't happen."
        exit 1
    fi

    luks_open_root
    luks_open_home

    format_partitions "/dev/mapper/crypt_home" "/dev/mapper/crypt_root"
    format_partitions "/dev/mapper/crypt_home" "/dev/mapper/crypt_root"
    mount_partitions "/dev/mapper/crypt_home" "/dev/mapper/crypt_root"

    populate_crypttab
elif [[ "$ENCRYPT_SYSTEM" == "n" ]]
then
    format_partitions "$HOME_PARTITION" "$ROOT_PARTITION"
    mount_partitions "$HOME_PARTITION" "$ROOT_PARTITION"
else
    printf "\n\e[31m%s %s\e[0m\n" "[Error]" \
        "\$ENCRYPT_SYSTEM variable in install_constants must be set to 'y' or 'n'"
fi

configure_swap
set_timezone "America/Chicago"
set_apt_cache_server
copy_apt_sources_to_live_system
apt_update
install_debootstrap
run_debootstrap
generate_fstab_file
set_hostname
copy_necessary_project_files_to_new_system

arch-chroot /mnt /bin/bash finish_install.sh
