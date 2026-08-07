#!/bin/bash
# run_integration_tests.sh - part of the DebianInstaller project
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

GLOBAL_PARTITION_VARIABLES_FILE=./DebianInstaller/integration_tests_global_partition_variables

INSTALL_CONSTANTS_FILE=./DebianInstaller/install_constants
BACKUP_INSTALL_CONSTANTS_FILE=./DebianInstaller/install_constants.bak

SAFELY_CLOSE_SYSTEM_SCRIPT=./DebianInstaller/safely_close_system.sh

COMPLETION_FILE=./integration_tests_completion.txt

START_INSTALL_COMPLETION_FILE=./start_install_completion.txt

START_INSTALL_SCRIPT=./DebianInstaller/start_install.sh

if ! source $GLOBAL_PARTITION_VARIABLES_FILE &>/dev/null
then
    printf "\n\n\e[31m%s %s\e[0m\n\n" \
        "[!] Couldn't source the integration_tests_global_partition_variables" \
        "file. Make sure to run \`bash ./DebianInstaller/start_install.sh\`"
    exit 1
fi

if ! source $PRETTY_OUTPUT_LIBRARY &>/dev/null
then
    printf "\n\n\e[31m%s %s\e[0m\n\n" \
        "[!] Couldn't source the pretty output library. Make sure" \
        "to run \`bash ./DebianInstaller/start_install.sh\`"
    exit 1
fi

STDOUT_LOG_PATH="/tmp/integration_tests_stdout.log"
STDERR_LOG_PATH="/tmp/integration_tests_stderr.log"

check_global_partition_variables()
{
    if [[ -n "$DISK" ]]
    then
        if ! [[ -b "$DISK" ]]
        then
            printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
                "No disk '$DISK' exists on the system."
            return 1
        fi
    else
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "The '\$DISK' variable must be set in '$GLOBAL_PARTITION_VARIABLES_FILE'"
        return 1
    fi

    if [[ -n "$EFI_PARTITION" ]]
    then
        if ! [[ -b "$EFI_PARTITION" ]]
        then
            printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
                "No partition '$EFI_PARTITION' exists on the system."
            return 1
        fi
    else
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "The '\$EFI_PARTITION' variable must be set in '$GLOBAL_PARTITION_VARIABLES_FILE'"
        return 1
    fi

    if [[ -n "$BOOT_PARTITION" ]]
    then
        if ! [[ -b "$BOOT_PARTITION" ]]
        then
            printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
                "No partition '$BOOT_PARTITION' exists on the system."
            return 1
        fi
    else
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "The '\$BOOT_PARTITION' variable must be set in '$GLOBAL_PARTITION_VARIABLES_FILE'"
        return 1
    fi

    if [[ -n "$ROOT_PARTITION" ]]
    then
        if ! [[ -b "$ROOT_PARTITION" ]]
        then
            printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
                "No partition '$ROOT_PARTITION' exists on the system."
            return 1
        fi
    else
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "The '\$ROOT_PARTITION' variable must be set in '$GLOBAL_PARTITION_VARIABLES_FILE'"
        return 1
    fi

    if [[ -n "$HOME_PARTITION" ]]
    then
        if ! [[ -b "$HOME_PARTITION" ]]
        then
            printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
                "No partition '$HOME_PARTITION' exists on the system."
            return 1
        fi
    else
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "The '\$HOME_PARTITION' variable must be set in '$GLOBAL_PARTITION_VARIABLES_FILE'"
        return 1
    fi

    if [[ -n "$LUKS_KEYFILE_PARTITION" ]]
    then
        if ! [[ -b "$LUKS_KEYFILE_PARTITION" ]]
        then
            printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
                "No disk '$LUKS_KEYFILE_PARTITION' exists on the system."
            return 1
        fi
    else
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "The '\$LUKS_KEYFILE_PARTITION' variable must be set in '$GLOBAL_PARTITION_VARIABLES_FILE'"
        return 1
    fi

    return 0
}

check_global_partition_variables || exit $?

backup_the_install_constants_file()
{
    if ! [[ -f "$BACKUP_INSTALL_CONSTANTS_FILE" ]]
    then
        cp $INSTALL_CONSTANTS_FILE $BACKUP_INSTALL_CONSTANTS_FILE \
            >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "Backup the original install_constants file"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

pre_test_preparations()
{
    bash $SAFELY_CLOSE_SYSTEM_SCRIPT || return 1

    cp $BACKUP_INSTALL_CONSTANTS_FILE $INSTALL_CONSTANTS_FILE \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "Restore the original install_contants file from the backup for test"
    [[ $? -ne 0 ]] && return 1

    if [[ -f "$START_INSTALL_COMPLETION_FILE" ]]
    then
        rm "$START_INSTALL_COMPLETION_FILE" >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
        task_output $! "$STDERR_LOG_PATH" \
            "remove  file: $START_INSTALL_COMPLETION_FILE"
        [[ $? -ne 0 ]] && return 1
    fi

    return 0
}

post_test_cleanup()
{
    bash $SAFELY_CLOSE_SYSTEM_SCRIPT || return 1

    return 0
}

restore_the_install_constants_file()
{
    mv $BACKUP_INSTALL_CONSTANTS_FILE $INSTALL_CONSTANTS_FILE \
        >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "Restore the original install_contants file from the backup"
    [[ $? -ne 0 ]] && return 1

    return 0
}

set_variable() {
    local TEST_NAME="$1"
    local VARIABLE_NAME="$2"
    local VARIABLE_VALUE="${@:3}"

    # Thank you chatgpt for: `\(# \?\)\?`
    #   * In my own words, there are two `\` for escaping `(` and `)`, then the
    #     `# \?` inside means `#` is mandator and the space after is optional,
    #     and finally the `\?` outside the `()` means the whole thing is optional
    #     effectively allow a comment with a space or just a comment before any
    #     of the variables
    if ! grep "^\(# \?\)\?$VARIABLE_NAME=" "$INSTALL_CONSTANTS_FILE" &>/dev/null
    then
        printf "\n\e[31m%s %s\e[0m\n" "[FATAL ERROR]" \
            "Test '$TEST_NAME' failed trying to set non-existant variable '$VARIABLE_NAME'"
        # Exception for exiting from function to keep code clean
        exit 1
    fi

    # Thank you Lumo AI for the sed help
    #
    # LUMO COMMENT: Escape &, backslash, and your comma delimiter
    local SAFE_VALUE=$(printf '%s' "$VARIABLE_VALUE" | sed 's/[&\\,]/\\&/g')

    sed -i "s,^\(# \?\)\?${VARIABLE_NAME}=.*,${VARIABLE_NAME}=${SAFE_VALUE}," \
        "$INSTALL_CONSTANTS_FILE" >>"$STDOUT_LOG_PATH" 2>>"$STDERR_LOG_PATH" &
    task_output $! "$STDERR_LOG_PATH" \
        "TEST ['$TEST_NAME']: Set $VARIABLE_NAME='$SAFE_VALUE'"
    # Exception for exiting from function to keep code clean
    [[ $? -ne 0 ]] && exit 1

    return 0
}

replace_install_constants_partition_variables()
{
    set_variable "set_partitions" "DISK" "$DISK"
    set_variable "set_partitions" "EFI_PARTITION" "$EFI_PARTITION"
    set_variable "set_partitions" "BOOT_PARTITION" "$BOOT_PARTITION"
    set_variable "set_partitions" "ROOT_PARTITION" "$ROOT_PARTITION"
    set_variable "set_partitions" "HOME_PARTITION" "$HOME_PARTITION"

    return 0
}

introduce_test()
{
    local TEST_NAME="$1"
    local TEST_DESCRIPTION="${@:2}"

    if [[ -z "$TEST_NAME" ]]
    then
        printf "\n\e[31m%s %s\e[0m\n" "[ERROR]" \
            "No test name passed to the introduce_test function. Stopping."
        exit 1
    fi

    printf "\n\n\e[36m%s %s %s \n\n  %s\e[0m\n\n" \
        "--------" "TEST: $TEST_NAME" "--------" \
        "Description: $TEST_DESCRIPTION"

    return 0
}

# The create_ function below should only be ran during system creation
# and not during every test run as it installs and configures the full suite
# of packages to setup the system, while all other tests just configure the
# system from these existing packages
create_fresh_luks_system()
{
    local TEST_NAME="create_fresh_luks_system"
    local TEST_DESCRIPTION="Setup initial system, installing all packages. Luks Encrypted."
    
    if ! grep "^${TEST_NAME}$" $COMPLETION_FILE &>/dev/null
    then
        introduce_test "$TEST_NAME" "$TEST_DESCRIPTION"

        pre_test_preparations

        set_variable "$TEST_NAME" "OVERWRITE_HOME_PARTITION" "'y'"
        set_variable "$TEST_NAME" "SKIP_INSTALLING_PACKAGES" "'n'"

        set_variable "$TEST_NAME" "LUKS_KEYFILE_PARTITION" "''"
        set_variable "$TEST_NAME" "LUKS_PASSWORD" "'test'"

        set_variable "$TEST_NAME" "USE_KEYFILE_AT_BOOT" "'n'"

        bash $START_INSTALL_SCRIPT || return $?

        echo "$TEST_NAME" >> $COMPLETION_FILE

        post_test_cleanup
    fi

    return 0
}

# All the tests below are not built to be ran on an unencrypted system, so
# if you need to run this test, run it alone.
create_fresh_no_luks_system()
{
    local TEST_NAME="create_fresh_no_luks_system"
    local TEST_DESCRIPTION="Setup initial system, installing all packages. No luks."

    if ! grep "^${TEST_NAME}$" $COMPLETION_FILE &>/dev/null
    then
        introduce_test "$TEST_NAME" "$TEST_DESCRIPTION"

        pre_test_preparations

        set_variable "$TEST_NAME" "OVERWRITE_HOME_PARTITION" "'y'"
        set_variable "$TEST_NAME" "SKIP_INSTALLING_PACKAGES" "'n'"

        set_variable "$TEST_NAME" "LUKS_KEYFILE_PARTITION" "''"
        set_variable "$TEST_NAME" "LUKS_PASSWORD" "''"

        set_variable "$TEST_NAME" "USE_KEYFILE_AT_BOOT" "''"

        bash $START_INSTALL_SCRIPT || return $?

        echo "$TEST_NAME" >> $COMPLETION_FILE

        post_test_cleanup
    fi

    return 0
}

test_1()
{
    local TEST_NAME="test_1"
    local TEST_DESCRIPTION="Test adding keyfile to existing LUKS system encrypted with password"

    if ! grep "^${TEST_NAME}$" $COMPLETION_FILE &>/dev/null
    then
        introduce_test "$TEST_NAME" "$TEST_DESCRIPTION"

        pre_test_preparations

        set_variable "$TEST_NAME" "OVERWRITE_HOME_PARTITION" "'n'"
        set_variable "$TEST_NAME" "SKIP_INSTALLING_PACKAGES" "'y'"

        set_variable "$TEST_NAME" "LUKS_KEYFILE_PARTITION" "'$LUKS_KEYFILE_PARTITION'"
        set_variable "$TEST_NAME" "LUKS_PASSWORD" "'test'"

        set_variable "$TEST_NAME" "USE_KEYFILE_AT_BOOT" "'y'"

        bash $START_INSTALL_SCRIPT || return $?

        echo "$TEST_NAME" >> $COMPLETION_FILE

        post_test_cleanup
    fi

    return 0
}

test_2()
{
    local TEST_NAME="test_2"
    local TEST_DESCRIPTION="Test changing the existing LUKS password using the keyfile"

    if ! grep "^${TEST_NAME}$" $COMPLETION_FILE &>/dev/null
    then
        introduce_test "$TEST_NAME" "$TEST_DESCRIPTION"

        pre_test_preparations

        set_variable "$TEST_NAME" "OVERWRITE_HOME_PARTITION" "'n'"
        set_variable "$TEST_NAME" "SKIP_INSTALLING_PACKAGES" "'y'"

        set_variable "$TEST_NAME" "LUKS_KEYFILE_PARTITION" "'$LUKS_KEYFILE_PARTITION'"
        set_variable "$TEST_NAME" "LUKS_PASSWORD" "'test2'"

        set_variable "$TEST_NAME" "USE_KEYFILE_AT_BOOT" "'n'"

        bash $START_INSTALL_SCRIPT || return $?

        echo "$TEST_NAME" >> $COMPLETION_FILE

        post_test_cleanup
    fi

    return 0
}

test_3()
{
    local TEST_NAME="test_3"
    local TEST_DESCRIPTION="Test changing the primary boot method to use keyfile at boot"

    if ! grep "^${TEST_NAME}$" $COMPLETION_FILE &>/dev/null
    then
        introduce_test "$TEST_NAME" "$TEST_DESCRIPTION"

        pre_test_preparations

        set_variable "$TEST_NAME" "OVERWRITE_HOME_PARTITION" "'n'"
        set_variable "$TEST_NAME" "SKIP_INSTALLING_PACKAGES" "'y'"

        set_variable "$TEST_NAME" "LUKS_KEYFILE_PARTITION" "'$LUKS_KEYFILE_PARTITION'"
        set_variable "$TEST_NAME" "LUKS_PASSWORD" "'test2'"

        set_variable "$TEST_NAME" "USE_KEYFILE_AT_BOOT" "'y'"

        bash $START_INSTALL_SCRIPT || return $?

        echo "$TEST_NAME" >> $COMPLETION_FILE

        post_test_cleanup
    fi

    return 0
}

test_4()
{
    local TEST_NAME="test_4"
    local TEST_DESCRIPTION="Test replacing the home partition with a raid 1 array"

    if ! grep "^${TEST_NAME}$" $COMPLETION_FILE &>/dev/null
    then
        introduce_test "$TEST_NAME" "$TEST_DESCRIPTION"

        pre_test_preparations

        set_variable "$TEST_NAME" "OVERWRITE_HOME_PARTITION" "'y'"
        set_variable "$TEST_NAME" "SKIP_INSTALLING_PACKAGES" "'n'"

        set_variable "$TEST_NAME" "RAID_ARRAY_DEVICE" "'/dev/md0'"
        set_variable "$TEST_NAME" "RAID_LEVEL" "'1'"
        set_variable "$TEST_NAME" "RAID_PARTITIONS" "(${RAID_PARTITIONS[*]})"

        set_variable "$TEST_NAME" "LUKS_KEYFILE_PARTITION" "'$LUKS_KEYFILE_PARTITION'"
        set_variable "$TEST_NAME" "LUKS_PASSWORD" "'test4'"

        set_variable "$TEST_NAME" "USE_KEYFILE_AT_BOOT" "'y'"

        bash $START_INSTALL_SCRIPT || return $?

        echo "$TEST_NAME" >> $COMPLETION_FILE

        post_test_cleanup
    fi

    return 0
}

# All tests only change their required variables, meaning they all depend on
# the original install_constants file before running

backup_the_install_constants_file
replace_install_constants_partition_variables

# -- SETUP --

# All tests work on a LUKS encrypted system, despite not LUKS encrypting it
# being an option during real installation... because it's a bit unnecessary
# to retest all the same functionality in a much simpler setup. However I may
# eat those words some day.
create_fresh_luks_system || exit $?

# Tests do not have unique names because it would be a waste of time when you
# can just read the correlating function if one of the tests fail to see exactly
# what it's doing. With so many tests, the names would be crazy long as well.
#
# Test must be ran in order
#
# -- TESTS --
test_1 || exit $?
test_2 || exit $?
test_3 || exit $?
test_4 || exit $?

# -- TESTS FINISHED --

post_test_cleanup
restore_the_install_constants_file

exit 0
