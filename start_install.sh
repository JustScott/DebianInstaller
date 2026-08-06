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

PRETTY_OUTPUT_LIBRARY=./DebianInstaller/pretty_output_library.sh

COMPLETION_FILE=./start_install_completion.txt

INSTALL_CONSTANTS_FILE=./DebianInstaller/install_constants

FIRMWARE_PACKAGES=()

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

STDOUT_LOG_PATH="/tmp/start_install_stdout.log"
STDERR_LOG_PATH="/tmp/start_install_stderr.log"

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
        return 1
    fi
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

    if [[ -n "$RAID_LEVEL" ]]
    then
        if ! [[ "$RAID_LEVEL" =~ ^(0|1|4|5|6|10)$ ]]
        then
            printf "\n\n\e[31m%s %s\e[0m \e[36m%s\e[0m\n" "[ERROR]" \
                "Raid level '$RAID_LEVEL' not supported." \
                "Support levels are 0,1,4,5,6,10"
            return 1
        fi

        if [[ -z "$RAID_ARRAY_DEVICE" ]]
        then
            printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
                "\$RAID_PARTITIONS constant must be populated if \$RAID_LEVEL is set."
            return 1
        fi

        if [[ -z "${RAID_PARTITIONS[*]}" ]]
        then
            printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
                "\$RAID_PARTITIONS constant must be populated if \$RAID_LEVEL is set."
            return 1
        fi

        for raid_partition in ${RAID_PARTITIONS[@]}
        do
            if ! [[ -b "$raid_partition" ]]
            then
                printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
                    "'$raid_partition' in the install constant '\$RAID_PARTITIONS' is not a valid partition"
                return 1
            fi
        done

        HOME_PARTITION="$RAID_ARRAY_DEVICE"
    elif [[ ${#RAID_PARTITIONS[@]} > 1 ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "\$RAID_LEVEL constant must be populated if \$RAID_PARTITIONS is set."
        return 1
    fi

    if [[ "$OVERWRITE_HOME_PARTITION" != 'y' && "$OVERWRITE_HOME_PARTITION" != 'n' ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" \
            "[!] \$OVERWRITE_HOME_PARTITION constant must be 'y' or 'n'," \
            "this is fatal...stopping"
        return 1
    fi

    if [[ -z "$HOSTNAME" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] \$HOSTNAME constant not set, this is fatal...stopping"
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

    if [[ "$ENABLE_WIFI" != 'y' && "$ENABLE_WIFI" != 'n' ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" \
            "[!] \$ENABLE_WIFI constant must be 'y' or 'n'." \
        return 1
    fi

    OVERWRITE_ROOT_PARTITION='y'
    if [[ "$SKIP_INSTALLING_PACKAGES" != 'y' && "$SKIP_INSTALLING_PACKAGES" != 'n' ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" \
            "[!] \$SKIP_INSTALLING_PACKAGES constant must be 'y' or 'n'." \
        return 1
    elif [[ "$SKIP_INSTALLING_PACKAGES" == 'y' ]]
    then
        OVERWRITE_ROOT_PARTITION='n'
    fi

    if [[ -n "$LUKS_KEYFILE_PARTITION" && -n "$LUKS_PASSWORD" ]]
    then
        if [[ "$USE_KEYFILE_AT_BOOT" != 'y' && "$USE_KEYFILE_AT_BOOT" != 'n' ]]
        then
            printf "\n\e[31m%s %s\e[0m\n" \
                "[!] \$USE_KEYFILE_AT_BOOT constant must be 'y' or 'n'."
            return 1
        fi
    fi

    return 0
}

check_required_install_constants || exit $?

if [[ -n "$LUKS_PASSWORD" || -n "$LUKS_KEYFILE_PARTITION" ]]
then
    ENCRYPT_SYSTEM='y'
else
    ENCRYPT_SYSTEM='n'
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

check_for_cache_server || exit $?

stop_raid_arrays()
{
    if ! [[ -f /proc/mdstat ]]
    then
        return 1
    fi

    if grep "md[0-9]\+ : active" /proc/mdstat &>/dev/null
    then
        mdadm --stop --scan >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Stop active RAID array(s)"
        if [[ $? -ne 0 ]]
        then
            printf "\n\n\e[36m%s %s %s %s\e[0m\n" "[TIP]" \
                "If the live system is still mounted, try running" \
                "DebianInstaller/safely_close_system.sh before" \
                "running start_install.sh again"

            return 1
        fi
    fi

    return 0
}

create_raid_array()
{
    if ! grep "^create_raid_array$" $COMPLETION_FILE &>/dev/null
    then
        if [[ "$OVERWRITE_HOME_PARTITION" != 'y' ]] # Double check before overwriting anything
        then
            printf "\n\e[31m%s %s\e[0m\n" \
                "[!] \$OVERWRITE_HOME_PARTITION not set to 'y' yet 'setup_raid_array'," \
                "function is being called... This shouldn't happen. Stopping"
            return 1
        fi

        wipefs --all "${RAID_PARTITIONS[@]}" >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Wipe old partition data from RAID partitions: ${RAID_PARTITIONS[*]}"
        [[ $? -ne 0 ]] && return 1

        sudo mdadm --create $RAID_ARRAY_DEVICE \
            --level=$RAID_LEVEL \
            --raid-devices=${#RAID_PARTITIONS[@]} \
            --metadata=1.2 \
            --bitmap=internal \
            --run \
            "${RAID_PARTITIONS[@]}" >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Create RAID $RAID_LEVEL array on partitions ${RAID_PARTITIONS[*]}"
        [[ $? -ne 0 ]] && return 1

        echo "create_raid_array" >> $COMPLETION_FILE
    fi

    return 0
}

configure_raid_array()
{
    if ! [[ -d "/mnt/etc/mdadm" ]]
    then
        mkdir -p /mnt/etc/mdadm >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Create /mnt/etc/mdadm for mdadm.conf"
        [[ $? -ne 0 ]] && return 1
    fi

    sudo mdadm --detail --scan | sudo tee /mnt/etc/mdadm/mdadm.conf \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "Add RAID array details to /mnt/etc/mdadm/mdadm.conf (Automatically starts raid array at boot)"
    [[ $? -ne 0 ]] && return 1

    return 0
}

assemble_existing_raid_array()
{
    mdadm --assemble $RAID_ARRAY_DEVICE "${RAID_PARTITIONS[@]}" \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "Assemble existing RAID array '$RAID_ARRAY_DEVICE' with partitions: ${RAID_PARTITIONS[*]}"
    [[ $? -ne 0 ]] && return 1

    return 0
}

create_luks_keyfile_on_usb()
{
    if ! [[ -b /dev/disk/by-label/keyfile_usb ]]
    then
        echo 'y' | mkfs.fat -F 32 -n "keyfile_usb" $LUKS_KEYFILE_PARTITION \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Format keyfile_usb partition with FAT32"
        [[ $? -ne 0 ]] && return 1
    fi

    if ! [[ -d /media/keyfile_usb ]]
    then
        mount --mkdir /dev/disk/by-label/keyfile_usb /media/keyfile_usb \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount keyfile_usb partition"
        [[ $? -ne 0 ]] && return 1
    fi

    if ! [[ -f /media/keyfile_usb/luks_keyfile ]]
    then
        dd if=/dev/urandom of=/media/keyfile_usb/luks_keyfile bs=1024 count=2 \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Create luks_keyfile on keyfile_usb"
        [[ $? -ne 0 ]] && return 1

        chmod 400 /media/keyfile_usb/luks_keyfile \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Set permissions on luks_keyfile (400)"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

luks_format_root_with_keyfile()
{
    if ! grep "^luksFormatRootWithKeyfile$" $COMPLETION_FILE &>/dev/null
    then
        cryptsetup luksFormat --key-file /media/keyfile_usb/luks_keyfile \
            --batch-mode $ROOT_PARTITION \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "luksFormat root ($ROOT_PARTITION) with USB keyfile"
        [[ $? -ne 0 ]] && return 1

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
        [[ $? -ne 0 ]] && return 1

        echo "luksFormatHomeWithKeyfile" >> $COMPLETION_FILE
    fi

    return 0
}

luks_format_root_with_passphrase() {
    if [[ -z "$LUKS_PASSWORD" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "Luks password not set in 'install_constants' file"
        return 1
    fi

    if ! grep "^luksFormatRootWithPassphrase$" $COMPLETION_FILE &>/dev/null
    then
        echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat -s 512 -h sha512 \
            --key-file=- $ROOT_PARTITION >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "luksFormat root ($ROOT_PARTITION) with passphrase"
        [[ $? -ne 0 ]] && return 1

        echo "luksFormatRootWithPassphrase" >> $COMPLETION_FILE
    fi

    return 0
}

luks_format_home_with_passphrase() {
    if [[ -z "$LUKS_PASSWORD" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "Luks password not set in 'install_constants' file"
        return 1
    fi

    if ! grep "^luksFormatHomeWithPassphrase$" $COMPLETION_FILE &>/dev/null
    then
        echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat -s 512 -h sha512 \
            --key-file=- $HOME_PARTITION >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "luksFormat home ($HOME_PARTITION) with passphrase"
        [[ $? -ne 0 ]] && return 1

        echo "luksFormatHomeWithPassphrase" >> $COMPLETION_FILE
    fi

    return 0
}

luks_add_passphrase_to_root()
{
    if [[ -z "$LUKS_PASSWORD" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "Luks password not set in 'install_constants' file"
        return 1
    fi

    if ! grep "^luksAddPassphraseToRoot$" $COMPLETION_FILE &>/dev/null
    then
        echo -n "$LUKS_PASSWORD" | cryptsetup luksAddKey \
            --key-file /media/keyfile_usb/luks_keyfile \
            $ROOT_PARTITION >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Add LUKS passphrase to root ($ROOT_PARTITION)"
        [[ $? -ne 0 ]] && return 1

        echo "luksAddPassphraseToRoot" >> $COMPLETION_FILE
    fi

    return 0
}

luks_add_passphrase_to_home()
{
    if [[ -z "$LUKS_PASSWORD" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "Luks password not set in 'install_constants' file"
        return 1
    fi

    if ! grep "^luksAddPassphraseToHome$" $COMPLETION_FILE &>/dev/null
    then
        echo -n "$LUKS_PASSWORD" | cryptsetup luksAddKey \
            --key-file /media/keyfile_usb/luks_keyfile \
            $HOME_PARTITION >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Add LUKS passphrase to home ($HOME_PARTITION)"
        [[ $? -ne 0 ]] && return 1

        echo "luksAddPassphraseToHome" >> $COMPLETION_FILE
    fi

    return 0
}

luks_add_keyfile_to_root()
{
    if [[ -z "$LUKS_PASSWORD" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "Luks password not set in 'install_constants' file"
        return 1
    fi

    if ! grep "^luksAddKeyFileToRoot$" $COMPLETION_FILE &>/dev/null
    then
        echo -n "$LUKS_PASSWORD" | cryptsetup luksAddKey --key-file=- \
            $ROOT_PARTITION /media/keyfile_usb/luks_keyfile \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Add LUKS keyfile to root ($ROOT_PARTITION)"
        [[ $? -ne 0 ]] && return 1

        echo "luksAddKeyFileToRoot" >> $COMPLETION_FILE
    fi

    return 0
}

luks_add_keyfile_to_home()
{
    if [[ -z "$LUKS_PASSWORD" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "Luks password not set in 'install_constants' file"
        return 1
    fi

    if ! grep "^luksAddKeyFileToHome$" $COMPLETION_FILE &>/dev/null
    then
        echo -n "$LUKS_PASSWORD" | cryptsetup luksAddKey --key-file=- \
            $HOME_PARTITION /media/keyfile_usb/luks_keyfile \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Add LUKS keyfile to home ($HOME_PARTITION)"
        [[ $? -ne 0 ]] && return 1

        echo "luksAddKeyFileToHome" >> $COMPLETION_FILE
    fi

    return 0
}

luks_open_root()
{
    if ! grep "^luksOpenRoot$" $COMPLETION_FILE &>/dev/null
    then
        cryptsetup close crypt_root &>/dev/null

        if [[ -n "$LUKS_PASSWORD" && -z "$LUKS_KEYFILE_PARTITION" ]]
        then
            echo -n "$LUKS_PASSWORD" | cryptsetup open --key-file=- $ROOT_PARTITION \
                crypt_root >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted root partition with passphrase"
            if [[ $? -ne 0 ]]
            then
                if [[ "$OVERWRITE_ROOT_PARTITION" == 'n' ]]
                then
                    printf "\n\n\e[36m%s %s %s\e[0m\n" "[TIP]" \
                        "Probably used the wrong partition passphrase, try" \
                        "changing it in install_constants"
                fi
                return 1
            fi
        elif [[ -n "$LUKS_KEYFILE_PARTITION" && -z "$LUKS_PASSWORD" ]]
        then
            cryptsetup open --key-file /media/keyfile_usb/luks_keyfile \
                $ROOT_PARTITION crypt_root >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted root partition with USB keyfile"
            if [[ $? -ne 0 ]]
            then
                if [[ "$OVERWRITE_ROOT_PARTITION" == 'n' ]]
                then
                    printf "\n\n\e[36m%s %s %s\e[0m\n" "[TIP]" \
                        "Probably used the wrong partition passphrase, try" \
                        "changing it in install_constants"
                fi
                return 1
            fi
        elif [[ -n "$LUKS_PASSWORD" && -n "$LUKS_KEYFILE_PARTITION" ]]
        then
            cryptsetup open --key-file /media/keyfile_usb/luks_keyfile \
                $ROOT_PARTITION crypt_root >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted root partition with USB keyfile"
            local luks_open_return_code=$?
            if [[ $luks_open_return_code -eq 0 && "$OVERWRITE_ROOT_PARTITION" == 'n' ]]
            then
                cryptsetup close crypt_root &>/dev/null
                echo -n "$LUKS_PASSWORD" | cryptsetup open --key-file=- $ROOT_PARTITION \
                    crypt_root >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
                task_output $! "$STDERR_LOG_PATH" \
                    "open luks encrypted root partition with passphrase"
                if [[ $? -ne 0 ]]
                then
                    printf "\n\e[36m%s %s\e[0m\n\n" "[TIP]" \
                        "It's okay if this fails, as long as subsequent steps don't"
                    luks_add_passphrase_to_root
                    luks_open_root
                fi
            elif [[ $luks_open_return_code -ne 0 && "$OVERWRITE_ROOT_PARTITION" == 'n' ]]
            then
                printf "\n\e[36m%s %s\e[0m\n\n" "[TIP]" \
                        "It's okay if this fails, as long as subsequent steps don't"
                echo -n "$LUKS_PASSWORD" | cryptsetup open --key-file=- $ROOT_PARTITION \
                    crypt_root >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
                task_output $! "$STDERR_LOG_PATH" \
                    "open luks encrypted root partition with passphrase"
                if [[ $? -eq 0 ]]
                then
                    luks_add_keyfile_to_root
                else
                    printf "\n\n\e[36m%s %s %s %s\e[0m\n" "[TIP]" \
                        "Neither the passphrase nor the keyfile could unlock" \
                        "the root partition. Did you mean to set" \
                        "SKIP_INSTALLING_PACKAGES='y' in install_constants?"
                    return 1
                fi
            elif [[ $luks_open_return_code -ne 0 && "$OVERWRITE_ROOT_PARTITION" == 'y' ]]
            then
                printf "\n\n\e[36m%s %s %s\e[0m\n" "[TIP]" \
                    "The root partition is being overwritten, so this luksOpen" \
                    "step should never fail. Must be a logic error."
                return 1
            fi
        fi

        echo "luksOpenRoot" >> $COMPLETION_FILE
    fi

    return 0
}

luks_open_home()
{
    if ! grep "^luksOpenHome$" $COMPLETION_FILE &>/dev/null
    then
        cryptsetup close crypt_home &>/dev/null

        if [[ -n "$LUKS_PASSWORD" && -z "$LUKS_KEYFILE_PARTITION" ]]
        then
            echo -n "$LUKS_PASSWORD" | cryptsetup open --key-file=- $HOME_PARTITION \
                crypt_home >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted home partition with passphrase"
            if [[ $? -ne 0 ]]
            then
                if [[ "$OVERWRITE_HOME_PARTITION" == 'n' ]]
                then
                    printf "\n\n\e[36m%s %s %s %s\e[0m\n" "[TIP]" \
                        "Probably used the wrong partition passphrase, or set" \
                        "OVERWRITE_HOME_PARTITION='n' when you meant 'y', try"
                        "changing it in install_constants"
                fi
                return 1
            fi
        elif [[ -n "$LUKS_KEYFILE_PARTITION" && -z "$LUKS_PASSWORD" ]]
        then
            cryptsetup open --key-file /media/keyfile_usb/luks_keyfile \
                $HOME_PARTITION crypt_home >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted home partition with USB keyfile"
            if [[ $? -ne 0 ]]
            then
                if [[ "$OVERWRITE_HOME_PARTITION" == 'n' ]]
                then
                    printf "\n\n\e[36m%s %s %s\e[0m\n" "[TIP]" \
                        "Probably used the wrong partition passphrase, try" \
                        "changing it in install_constants"
                fi
                return 1
            fi
        elif [[ -n "$LUKS_PASSWORD" && -n "$LUKS_KEYFILE_PARTITION" ]]
        then
            cryptsetup open --key-file /media/keyfile_usb/luks_keyfile \
                $HOME_PARTITION crypt_home >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "open luks encrypted home partition with USB keyfile"
            local luks_open_return_code=$?
            if [[ $luks_open_return_code -eq 0 && "$OVERWRITE_HOME_PARTITION" == 'n' ]]
            then
                cryptsetup close crypt_home &>/dev/null
                echo -n "$LUKS_PASSWORD" | cryptsetup open --key-file=- $HOME_PARTITION \
                    crypt_home >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
                task_output $! "$STDERR_LOG_PATH" \
                    "open luks encrypted home partition with passphrase"
                if [[ $? -ne 0 ]]
                then
                    printf "\n\e[36m%s %s\e[0m\n\n" "[TIP]" \
                        "It's okay if this fails, as long as subsequent steps don't"
                    luks_add_passphrase_to_home
                    luks_open_home
                fi
            elif [[ $luks_open_return_code -ne 0 && "$OVERWRITE_HOME_PARTITION" == 'n' ]]
            then
                printf "\n\e[36m%s %s\e[0m\n\n" "[TIP]" \
                    "It's okay if this fails, as long as subsequent steps don't"
                echo -n "$LUKS_PASSWORD" | cryptsetup open --key-file=- $HOME_PARTITION \
                    crypt_home >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
                task_output $! "$STDERR_LOG_PATH" \
                    "open luks encrypted home partition with passphrase"
                if [[ $? -eq 0 ]]
                then
                    luks_add_keyfile_to_home
                else
                    printf "\n\n\e[36m%s %s %s %s\e[0m\n" "[TIP]" \
                        "Neither the passphrase nor the keyfile could unlock" \
                        "the home partition. Did you mean to set" \
                        "OVERWRITE_HOME_PARTITION='y' in install_constants?"
                    return 1
                fi
            elif [[ $luks_open_return_code -ne 0 && "$OVERWRITE_HOME_PARTITION" == 'y' ]]
            then
                printf "\n\n\e[36m%s %s %s\e[0m\n" "[TIP]" \
                    "The home partition is being overwritten, so this luksOpen" \
                    "step should never fail. Must be a logic error."
                return 1
            fi
        fi

        echo "luksOpenHome" >> $COMPLETION_FILE
    fi

    return 0
}

format_partitions()
{
    local home_partition="$1"
    local root_partition="$2"

    if [[ "$OVERWRITE_ROOT_PARTITION" = 'y' ]]
    then
        if ! grep "^mkfs_efi$" $COMPLETION_FILE &>/dev/null
        then
            echo 'y' | mkfs.fat -F 32 $EFI_PARTITION \
                >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Format EFI partition ($EFI_PARTITION) with FAT32"
            [[ $? -ne 0 ]] && return 1

            echo "mkfs_efi" >> $COMPLETION_FILE
        fi

        if ! grep "^mkfs_boot$" $COMPLETION_FILE &>/dev/null
        then
            echo 'y' | mkfs.ext4 $BOOT_PARTITION \
                >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Format boot partition ($BOOT_PARTITION) with EXT4"
            [[ $? -ne 0 ]] && return 1

            echo "mkfs_boot" >> $COMPLETION_FILE
        fi

        if ! grep "^mkfs_root$" $COMPLETION_FILE &>/dev/null
        then
            echo 'y' | mkfs.ext4 "$root_partition" \
                >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Format root partition ($ROOT_PARTITION) with EXT4"
            [[ $? -ne 0 ]] && return 1

            echo "mkfs_root" >> $COMPLETION_FILE
        fi
    fi

    if [[ $OVERWRITE_HOME_PARTITION == 'y' ]]
    then
        if ! grep "^mkfs_home$" $COMPLETION_FILE &>/dev/null
        then
            echo 'y' | mkfs.ext4 "$home_partition" \
                >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Format home partition ($HOME_PARTITION) with EXT4"
            [[ $? -ne 0 ]] && return 1

            echo "mkfs_home" >> $COMPLETION_FILE
        fi
    fi

    return 0
}

mount_partitions()
{
    local home_partition="$1"
    local root_partition="$2"

    if ! grep "^mount_root$" $COMPLETION_FILE &>/dev/null
    then
        mount "$root_partition" /mnt >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount the root partition ($ROOT_PARTITION)"
        [[ $? -ne 0 ]] && return 1

        echo "mount_root" >> $COMPLETION_FILE
    fi

    if ! grep "^mount_home$" $COMPLETION_FILE &>/dev/null
    then
        mount --mkdir "$home_partition" /mnt/home \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount the home partition ($HOME_PARTITION)"
        if [[ $? -ne 0 ]]
        then
            printf "\n\n\e[36m%s %s %s\e[0m\n" "[TIP]" \
                "Is it possible OVERWRITE_HOME_PARTITION is set to 'n' in" \
                "install_constants, but the existing home partition is empty?"
            return 1
        fi

        echo "mount_home" >> $COMPLETION_FILE
    fi

    if ! grep "^mount_boot$" $COMPLETION_FILE &>/dev/null
    then
        mount --mkdir $BOOT_PARTITION /mnt/boot \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount the boot partition ($BOOT_PARTITION)"
        [[ $? -ne 0 ]] && return 1

        echo "mount_boot" >> $COMPLETION_FILE
    fi

    if ! grep "^mount_efi$" $COMPLETION_FILE &>/dev/null
    then
        mount --mkdir $EFI_PARTITION /mnt/boot/efi \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Mount the efi partition ($EFI_PARTITION)"
        [[ $? -ne 0 ]] && return 1

        echo "mount_efi" >> $COMPLETION_FILE
    fi

    return 0
}

populate_crypttab()
{
    LUKS_ROOT_PARTITION_UUID="$(blkid -s UUID -o value $ROOT_PARTITION)"
    LUKS_HOME_PARTITION_UUID="$(blkid -s UUID -o value $HOME_PARTITION)"

    if [[ -z "$LUKS_ROOT_PARTITION_UUID" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] Couldn't find encrypted root partition in blkid output"
        return 1
    fi

    if [[ -z "$LUKS_HOME_PARTITION_UUID" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "[!] Couldn't find encrypted home partition in blkid output"
        return 1
    fi

    if ! [[ -d /mnt/etc/ ]]
    then
        mkdir -p /mnt/etc 1>/dev/null 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Create /mnt/etc for crypttab"
        [[ $? -ne 0 ]] && return 1
    fi

    if [[ -n "$LUKS_PASSWORD" ]]
    then
        if [[ "$USE_KEYFILE_AT_BOOT" == 'n' || -z "$LUKS_KEYFILE_PARTITION" ]]
        then
            echo "crypt_root UUID=$LUKS_ROOT_PARTITION_UUID none luks,discard,keyscript=decrypt_keyctl,initramfs" \
                > /mnt/etc/crypttab 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Add LUKS entry for root to /mnt/etc/crypttab"
            [[ $? -ne 0 ]] && return 1
            echo "crypt_home UUID=$LUKS_HOME_PARTITION_UUID none luks,discard,keyscript=decrypt_keyctl,initramfs" \
                >> /mnt/etc/crypttab 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Add LUKS entry for home to /mnt/etc/crypttab"
            [[ $? -ne 0 ]] && return 1
        fi
    fi
    if [[ -n "$LUKS_KEYFILE_PARTITION" ]]
    then
        if [[ "$USE_KEYFILE_AT_BOOT" == 'y' || -z "$LUKS_PASSWORD" ]]
        then
            echo "crypt_root UUID=$LUKS_ROOT_PARTITION_UUID /dev/disk/by-label/keyfile_usb:/luks_keyfile:60 luks,discard,keyscript=passdev,tries=2,initramfs" \
                > /mnt/etc/crypttab 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Add LUKS entry for root to /mnt/etc/crypttab"
            [[ $? -ne 0 ]] && return 1
            echo "crypt_home UUID=$LUKS_HOME_PARTITION_UUID /dev/disk/by-label/keyfile_usb:/luks_keyfile:60 luks,discard,keyscript=passdev,tries=2,initramfs" \
                >> /mnt/etc/crypttab 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Add LUKS entry for home to /mnt/etc/crypttab"
            [[ $? -ne 0 ]] && return 1
        fi
    fi

    return 0
}

configure_swap()
{
    if [[ -n "$SWAP_SIZE_IN_GB" ]]
    then
        if ! [[ "$SWAP_SIZE_IN_GB" =~ ^[1-9][0-9]*$ ]]
        then
            printf "\n\e[31m%s\e[0m\n" "[!] Invalid swap size: '$SWAP_SIZE_IN_GB'"
            return 1
        fi

        if [[ "$SWAP_SIZE_IN_GB" -gt 32 ]]
        then
            printf "\n\e[31m%s\e[0m\n" "[!] Max swap size is 32GB"
            return 1
        fi

        if ! grep "^mkswap$" $COMPLETION_FILE &>/dev/null
        then
            if [[ -f "/mnt/swapfile" ]]
            then
                swapoff /mnt/swapfile &>/dev/null
                rm /mnt/swapfile &>/dev/null
            fi

            mkswap -U clear --size ${SWAP_SIZE_IN_GB}G --file /mnt/swapfile \
                >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Create ${SWAP_SIZE_IN_GB}GB swapfile"
            [[ $? -ne 0 ]] && return 1

            echo "mkswap" >> $COMPLETION_FILE
        fi

        if ! grep "^swapon$" $COMPLETION_FILE &>/dev/null
        then
            swapon /mnt/swapfile >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" "Enable the swapfile"
            [[ $? -ne 0 ]] && return 1

            echo "swapon" >> $COMPLETION_FILE
        fi
    fi

    return 0
}

set_timezone()
{
    local user_timezone="$1"

    if [[ -z "$user_timezone" ]]
    then
        printf "\n\e[31m%s\e[0m %s\n" "[Error]" \
            "No user timezone passed to function, this shouldn't happen. Stopping."
        return 1
    fi

    if ! cmp -s "/usr/share/zoneinfo/${user_timezone}" /etc/localtime &>/dev/null
    then
        ln -sf "/usr/share/zoneinfo/${user_timezone}" /etc/localtime \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Set live system timezone: '$user_timezone'"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
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
            [[ $? -ne 0 ]] && return 1
        fi

        if ! apt-config dump | grep "Proxy" &>/dev/null
        then
            printf "\n\n\e[31m%s %s\e[0m\n\n" \
                "[!] The apt proxy isn't set up correctly. This shouldn't" \
                "happen...stopping"
            return 1
        fi
    fi

    return 0
}

copy_apt_sources_to_live_system()
{
    if ! cmp -s ./DebianInstaller/configuration_files/sources.list \
        /etc/apt/sources.list &>/dev/null
    then
        cp ./DebianInstaller/configuration_files/sources.list /etc/apt/sources.list \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Copy sources.list to the current live system"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

apt_update()
{
    if ! grep "^apt_update$" $COMPLETION_FILE &>/dev/null
    then
        apt-get update >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Update apt"
        [[ $? -ne 0 ]] && return 1

        echo "apt_update" >> $COMPLETION_FILE
    fi

    return 0
}

# DISCLAIMER: Only AMD CPU microcode, AMD iGPU firmware, and mediatek firmware
#             have been tested.
find_correct_firmware()
{
    if ! dpkg -s pciutils &>/dev/null
    then
        apt-get install --yes pciutils \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Install pciutils for finding the correct firmware with lspci"
        [[ $? -ne 0 ]] && return 1
    fi

    # GPU firmware
    local LSPCI_OUTPUT="$(lspci -nn)"

    # GPU firmware
    if [[ -n "$DESKTOP_ENVIRONMENT" ]]
    then
        if echo "$LSPCI_OUTPUT" | grep "VGA compatible controller" \
            | grep "Advanced Micro Devices" &>/dev/null
        then
            if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "firmware-amd-graphics" &>/dev/null
            then
                FIRMWARE_PACKAGES+=(firmware-amd-graphics)
            fi
            if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "mesa-vulkan-drivers" &>/dev/null
            then
                FIRMWARE_PACKAGES+=(mesa-vulkan-drivers)
            fi
        elif echo "$LSPCI_OUTPUT" | grep "VGA compatible controller" | grep -i "intel" &>/dev/null
        then
            if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "firmware-misc-nonfree" &>/dev/null
            then
                FIRMWARE_PACKAGES+=(firmware-misc-nonfree)
            fi
            if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "mesa-vulkan-drivers" &>/dev/null
            then
                FIRMWARE_PACKAGES+=(mesa-vulkan-drivers)
            fi
        fi
    fi
        # REQUIRES non-free in apt sources... not sure if I want to support that yet
        #    elif echo "$LSPCI_OUTPUT" | grep "VGA compatible controller" | grep -i "nvidia" &>/dev/null
        #    then
        #        if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "nvidia-driver" &>/dev/null
        #        then
        #            FIRMWARE_PACKAGES+=(nvidia-driver)
        #        fi
        #        if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "firmware-nvidia-gsp" &>/dev/null
        #        then
        #            FIRMWARE_PACKAGES+=(firmware-nvidia-gsp)
        #        fi
        #    fi

    # CPU microcode
    if cat /proc/cpuinfo | grep -m1 -i "vendor_id" | grep -i "amd" &>/dev/null
    then
        if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "amd64-microcode" &>/dev/null
        then
            FIRMWARE_PACKAGES+=(amd64-microcode)
        fi
    elif cat /proc/cpuinfo | grep -m1 -i "vendor_id" | grep -i "intel" &>/dev/null
    then
        if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "intel-microcode" &>/dev/null
        then
            FIRMWARE_PACKAGES+=(intel-microcode)
        fi
    fi

    # Wifi firmware (no elif, incase multiple chips)
    if [[ "$ENABLE_WIFI" == 'y' ]]
    then
        if echo "$LSPCI_OUTPUT" | grep "Network controller" | grep -i "mediatek" &>/dev/null
        then
            if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "firmware-mediatek" &>/dev/null
            then
                FIRMWARE_PACKAGES+=(firmware-mediatek)
            fi
        fi

        if echo "$LSPCI_OUTPUT" | grep "Network controller" | grep -i "iwlwifi" &>/dev/null
        then
            if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "firmware-iwlwifi" &>/dev/null
            then
                FIRMWARE_PACKAGES+=(firmware-iwlwifi)
            fi
        fi

        if echo "$LSPCI_OUTPUT" | grep "Network controller" | grep -i "realtek" &>/dev/null
        then
            if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "firmware-realtek" &>/dev/null
            then
                FIRMWARE_PACKAGES+=(firmware-realtek)
            fi
        fi

        if echo "$LSPCI_OUTPUT" | grep "Network controller" | grep -i "qualcomm atheros" &>/dev/null
        then
            if ! echo "${FIRMWARE_PACKAGES[*]}" | grep "firmware-atheros" &>/dev/null
            then
                FIRMWARE_PACKAGES+=(firmware-atheros)
            fi
        fi
    fi

    return 0
}

install_installer_scripts()
{
    local PACKAGES=(arch-install-scripts)

    if [[ -b "$RAID_ARRAY_DEVICE" ]]
    then
        PACKAGES+=(mdadm)
    fi

    if ! grep "^apt_install_installer_scripts$" $COMPLETION_FILE &>/dev/null
    then
        apt-get install --yes "${PACKAGES[@]}" \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Install scripts needed for base system setup"
        [[ $? -ne 0 ]] && return 1

        echo "apt_install_installer_scripts" >> $COMPLETION_FILE
    fi

    return 0
}

install_debootstrap()
{
    if ! grep "^apt_install_debootstrap$" $COMPLETION_FILE &>/dev/null
    then
        apt-get install --yes debootstrap \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Install debootstrap"
        [[ $? -ne 0 ]] && return 1

        echo "apt_install_debootstrap" >> $COMPLETION_FILE
    fi

    return 0
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
            [[ $? -ne 0 ]] && return 1
        else
            debootstrap --arch amd64 stable /mnt https://deb.debian.org/debian \
                >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "Run debootstrap (this could take a while on slow internet)"
            [[ $? -ne 0 ]] && return 1
        fi

        echo "run_debootstrap" >> $COMPLETION_FILE
    fi

    return 0
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
            return 1
        fi

        echo "genfstab" >> $COMPLETION_FILE
    fi

    return 0
}

set_hostname()
{
    if [[ "$(cat /mnt/etc/hostname)" != "$HOSTNAME" ]]
    then
        echo "$HOSTNAME" > /mnt/etc/hostname &
        task_output $! "$STDERR_LOG_PATH" "Set the hostname to 'debian'"
        [[ $? -ne 0 ]] && return 1
    fi

    if ! grep "^127.0.1.1 ${HOSTNAME}$" /mnt/etc/hosts &>/dev/null
    then
        echo -e "127.0.0.1 localhost\n127.0.1.1 $HOSTNAME" > /mnt/etc/hosts &
        task_output $! "$STDERR_LOG_PATH" "Populate the '/etc/hosts' file"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
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
        [[ $? -ne 0 ]] && return 1
    fi

    if ! cmp -s $PRETTY_OUTPUT_LIBRARY \
        /mnt/$(basename $PRETTY_OUTPUT_LIBRARY) &>/dev/null
    then
        cp $PRETTY_OUTPUT_LIBRARY /mnt/ \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Copy '$PRETTY_OUTPUT_LIBRARY' to the new system"
        [[ $? -ne 0 ]] && return 1
    fi

    if ! cmp -s ./DebianInstaller/finish_install.sh /mnt/finish_install.sh &>/dev/null
    then
        cp ./DebianInstaller/finish_install.sh /mnt \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Copy 'finish_install.sh' to the new system"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

export_necessary_variables()
{
    local failed_variables=()
    export DISK \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("DISK")
    export OVERWRITE_HOME_PARTITION \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("OVERWRITE_HOME_PARTITION")
    export RAID_ARRAY_DEVICE \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("RAID_ARRAY_DEVICE")

    export ADMIN_USERNAME \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("ADMIN_USERNAME")
    export ADMIN_PASSWORD \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("ADMIN_PASSWORD")
    export USER_USERNAME \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("USER_USERNAME")
    export USER_PASSWORD \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("USER_PASSWORD")
    export TIMEZONE \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("TIMEZONE")

    FIRMWARE_PACKAGES_STRING="${FIRMWARE_PACKAGES[@]}"
    export FIRMWARE_PACKAGES_STRING \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("FIRMWARE_PACKAGES")

    export SKIP_INSTALLING_PACKAGES \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("SKIP_INSTALLING_PACKAGES")

    export LUKS_KEYFILE_PARTITION \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("LUKS_KEYFILE_PARTITION")
    export LUKS_PASSWORD \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("LUKS_PASSWORD")

    export DESKTOP_ENVIRONMENT \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("DESKTOP_ENVIRONMENT")

    export APT_CACHE_SERVER \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("APT_CACHE_SERVER")
    export APT_CACHE_FILE \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" \
        || failed_variables+=("APT_CACHE_FILE")


    if [[ -n "${failed_variables[@]}" ]]
    then
        printf "\n\e[31m%s\e[0m\n" \
            "Couldn't export variables: ${failed_variables[@]}"
        return 1
    fi

    printf "\r\e[32m[Success]\e[0m %s\n" \
        "Export variables for finish_install.sh"

    return 0
}

set_timezone "$TIMEZONE" || exit $?

set_apt_cache_server || exit $?
copy_apt_sources_to_live_system || exit $?
apt_update || exit $?
install_installer_scripts || exit $?

if [[ -n "$RAID_ARRAY_DEVICE" ]]
then
    stop_raid_arrays || exit $?

    if [[ $OVERWRITE_HOME_PARTITION == 'y' ]]
    then
        create_raid_array || exit $?
    else
        assemble_existing_raid_array || exit $?
    fi
fi

if [[ "$ENCRYPT_SYSTEM" == "y" ]]
then
    if [[ -n "$LUKS_KEYFILE_PARTITION" ]]
    then
        create_luks_keyfile_on_usb || exit $?

        if [[ "$OVERWRITE_ROOT_PARTITION" == 'y' ]]
        then
            luks_format_root_with_keyfile || exit $?
        fi
        if [[ "$OVERWRITE_HOME_PARTITION" == 'y' ]]
        then
            luks_format_home_with_keyfile || exit $?
        fi
    fi

    if [[ "$OVERWRITE_HOME_PARTITION" == 'n' ]]
    then
        luks_open_home || exit $?
    fi
    if [[ "$OVERWRITE_ROOT_PARTITION" == 'n' ]]
    then
        luks_open_root || exit $?
    fi

    if [[ -n "$LUKS_PASSWORD" ]]
    then
        if [[ -n "$LUKS_KEYFILE_PARTITION" ]]
        then
            if [[ "$OVERWRITE_ROOT_PARTITION" == 'y' ]]
            then
                luks_add_passphrase_to_root || exit $?
            fi
            if [[ "$OVERWRITE_HOME_PARTITION" == 'y' ]]
            then
                luks_add_passphrase_to_home || exit $?
            fi
        else
            if [[ "$OVERWRITE_ROOT_PARTITION" == 'y' ]]
            then
                luks_format_root_with_passphrase || exit $?
            fi
            if [[ "$OVERWRITE_HOME_PARTITION" == 'y' ]]
            then
                luks_format_home_with_passphrase || exit $?
            fi
        fi
    fi

    if [[ "$OVERWRITE_HOME_PARTITION" == 'y' ]]
    then
        luks_open_home || exit $?
    fi
    if [[ "$OVERWRITE_ROOT_PARTITION" == 'y' ]]
    then
        luks_open_root || exit $?
    fi

    # Doesn't overwrite home if "$OVERWRITE_HOME_PARTITION" == 'y'
    #
    # Doesn't overwrite root if "$SKIP_INSTALLING_PACKAGES" == 'y'
    format_partitions "/dev/mapper/crypt_home" "/dev/mapper/crypt_root" || exit $?
    mount_partitions "/dev/mapper/crypt_home" "/dev/mapper/crypt_root" || exit $?

    populate_crypttab || exit $?
elif [[ "$ENCRYPT_SYSTEM" == "n" ]]
then
    # Doesn't overwrite home if "$OVERWRITE_HOME_PARTITION" == 'y'
    #
    # Doesn't overwrite root if "$SKIP_INSTALLING_PACKAGES" == 'y'
    format_partitions "$HOME_PARTITION" "$ROOT_PARTITION" || exit $?
    mount_partitions "$HOME_PARTITION" "$ROOT_PARTITION" || exit $?
else
    printf "\n\e[31m%s %s\e[0m\n" "[Error]" \
        "\$ENCRYPT_SYSTEM variable in install_constants must be set to 'y' or 'n'"
    exit $?
fi

if [[ -n "$RAID_ARRAY_DEVICE" ]]
then
    configure_raid_array || exit $?
fi

configure_swap || exit $?

if [[ "$SKIP_INSTALLING_PACKAGES" != 'y' ]]
then
    find_correct_firmware || exit $?
    install_debootstrap || exit $?
    run_debootstrap || exit $?
fi

generate_fstab_file || exit $?
set_hostname || exit $?
copy_necessary_project_files_to_new_system || exit $?
export_necessary_variables || exit $?

arch-chroot /mnt /bin/bash finish_install.sh || exit $?

exit 0
