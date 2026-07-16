#!/bin/bash
# safely_shutdown_system.sh - part of the DebianInstaller project
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

PRETTY_OUTPUT_LIBRARY=./DebianInstaller/pretty_output_library.sh

COMPLETION_FILE=/mnt/finish_install_completion.txt
FINISH_INSTALL_SCRIPT=/mnt/finish_install.sh
NEW_SYSTEM_PRETTY_OUTPUT_LIBRARY=/mnt/pretty_output_library.sh
NEW_SYSTEM_STDERR_LOG_PATH=/mnt/debianinstallererrors.log

if ! source $PRETTY_OUTPUT_LIBRARY &>/dev/null
then
    printf "\n\n\e[31m%s %s\e[0m\n\n" \
        "[!] Couldn't source the pretty output library. Make sure" \
        "to run \`bash ./DebianInstaller/start_install.sh\`"
    exit 1
fi

remove_sensitive_files()
{
    if [[ -f "$COMPLETION_FILE" ]]
    then
        rm $COMPLETION_FILE >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "remove sensitive file: $COMPLETION_FILE"
        [[ $? -ne 0 ]] && return 1
    fi

    if [[ -f "$FINISH_INSTALL_SCRIPT" ]]
    then
        rm $FINISH_INSTALL_SCRIPT >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "remove sensitive file: $FINISH_INSTALL_SCRIPT"
        [[ $? -ne 0 ]] && return 1
    fi

    if [[ -f "$NEW_SYSTEM_PRETTY_OUTPUT_LIBRARY" ]]
    then
        rm $NEW_SYSTEM_PRETTY_OUTPUT_LIBRARY >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "remove sensitive file: $NEW_SYSTEM_PRETTY_OUTPUT_LIBRARY"
        [[ $? -ne 0 ]] && return 1
    fi

    if [[ -f "$NEW_SYSTEM_STDERR_LOG_PATH" ]]
    then
        rm $NEW_SYSTEM_STDERR_LOG_PATH >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "remove sensitive file: $NEW_SYSTEM_STDERR_LOG_PATH"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

shutoff_swapfile()
{
    if swapon --show | grep "/swapfile" &>/dev/null
    then
        swapoff /mnt/swapfile >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Turn off system swap"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

unmount_system()
{
    if lsblk | grep "/mnt/boot/efi" &>/dev/null
    then
        umount -R /mnt/boot/efi >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Umount /mnt/boot/efi"
        [[ $? -ne 0 ]] && return 1
    fi

    if lsblk | grep "/mnt/boot" &>/dev/null
    then
        umount -R /mnt/boot >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Umount /mnt/boot"
        [[ $? -ne 0 ]] && return 1
    fi

    if lsblk | grep "/mnt/home" &>/dev/null
    then
        umount -R /mnt/home >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Umount /mnt/home"
        [[ $? -ne 0 ]] && return 1
    fi

    if lsblk | grep "/mnt" &>/dev/null
    then
        umount -R /mnt >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Umount /mnt"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

close_encrypted_partitions()
{
    if lsblk | grep "crypt_root" &>/dev/null
    then
        cryptsetup close crypt_root >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "close crypt_root"
        [[ $? -ne 0 ]] && return 1
    fi

    if lsblk | grep "crypt_home" &>/dev/null
    then
        cryptsetup close crypt_home >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "close crypt_home"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

remove_sensitive_files || exit 1
shutoff_swapfile || exit 1
unmount_system || exit 1
close_encrypted_partitions || exit 1



echo ""
# Gives the user so many seconds to cancel the shutdown 
for i in {5..1}; do
    printf "\r%s \e[1;36m%s\e[0m" "Shutting Down In:" "$i"
    sleep 1
done

shutdown now
