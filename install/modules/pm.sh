#!/usr/bin/env bash

PM_MODULES_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/pm"

detect_package_manager() {
    # A Fedora system may also have pacman installed; choose by OS family first.
    if [ -r /etc/os-release ]; then
        local distro_id distro_like
        distro_id=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
        distro_like=$(awk -F= '/^ID_LIKE=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
        case " $distro_id $distro_like " in
            *" fedora "*) echo "dnf"; return 0 ;;
            *" arch "*) echo "pacman"; return 0 ;;
        esac
    fi

    if command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    fi
}

PM_NAME="$(detect_package_manager)"
PM_NAME="${PM_NAME:-pacman}"

PM_EXTRA_PKGS=()
PM_SDDM_EXTRA_PKGS=()
PM_SDDM_WAYLAND_DEFAULT=false
PM_SDDM_CURSOR_FIX=false

source "$PM_MODULES_DIR/$PM_NAME.sh"
