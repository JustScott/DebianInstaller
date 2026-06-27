#!/bin/bash
# run_as_admin_after_reboot.sh - part of the DebianInstaller project
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

PRETTY_OUTPUT_LIBRARY=/pretty_output_library.sh

if ! source $PRETTY_OUTPUT_LIBRARY &>/dev/null
then
    printf "\n\n\e[31m%s %s\e[0m\n\n" \
        "[!] Couldn't source the pretty output library. Stopping..." \
    exit 1
fi

install_firmware()
{
    if ! dpkg -s isenkram-cli &>/dev/null
    then
        sudo -v || return 1
        sudo apt-get install --yes isenkram-cli \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" "Install isenkram-cli"
        [[ $? -ne 0 ]] && return 1
    fi

    # Can't just use task_output because for some reason isenkram returns 1
    # if there's no firmware to install, which isn't an error.
    printf "\r\e[36m[%s]\e[0m %s" "..." "Auto-install firmware with isenkram"
    sudo -v || return 1
    sudo isenkram-autoinstall-firmware >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH"
    exit_code=$?
    if [[ $exit_code -lt 2 ]]
    then
        printf "\r\e[32m[Success]\e[0m %s\n" "Auto-install firmware with isenkram"
    elif [[ $exit_code -gt 1 ]]
    then
        printf "\r\e[31m[Error]\e[0m %s (Exit code: %d)\n" "$task_message" "$exit_code"
        printf "\e[31m[!] Check error log: %s\e[0m\n" "$stderr_path"
        return 1
    fi
    unset exit_code

    sudo -v || return 1
    sudo apt-get purge --yes isenkram-cli \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" "Remove isenkram-cli"
    [[ $? -ne 0 ]] && return 1

    return 0
}

enable_gui_if_installed()
{
    gui_install="false"

    if dpkg -s gdm3 &>/dev/null
    then
        if ! [[ "$(ls -l /etc/systemd/system/display-manager.service)" =~ "gdm" ]]
        then
            sudo -v || return 1
            sudo ln -sf /lib/systemd/system/gdm.service \
                /etc/systemd/system/display-manager.service \
                >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
            task_output $! "$STDERR_LOG_PATH" \
                "soft link gdm.service to display-manager.service"
            [[ $? -ne 0 ]] && return 1
        fi

        gui_install="true"
    fi

    if [[ "$gui_install" == "false" ]]
    then
        return 0
    fi

    if [[ "$(systemctl get-default)" != "graphical.target" ]]
    then
        sudo systemctl set-default graphical.target \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Enable GUI (requires reboot)"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

remove_scripts()
{
    rm ./run_as_admin_after_reboot.sh >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "remove script: './run_as_admin_after_reboot.sh'"
    [[ $? -ne 0 ]] && return 1

    sudo -v || return 1
    sudo rm $PRETTY_OUTPUT_LIBRARY >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "remove script: '${PRETTY_OUTPUT_LIBRARY}'"
    [[ $? -ne 0 ]] && return 1

    return 0
}

install_firmware || exit 1
enable_gui_if_installed || exit 1
remove_scripts || exit 1
