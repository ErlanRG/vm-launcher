#!/usr/bin/env bash

set -e

VM_DIR="$(dirname "$(readlink -f "$0")")"

detect_host_resources() {
    TOTAL_RAM=$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)
    TOTAL_CPUS=$(nproc)
    AVAIL_DISK_KB=$(df --output=avail "$VM_DIR" 2>/dev/null | tail -1)
}

suggest_resources() {
    detect_host_resources
    SUGGEST_RAM=$((TOTAL_RAM / 2))
    SUGGEST_CPUS=$((TOTAL_CPUS > 1 ? TOTAL_CPUS - 1 : 1))
    SUGGEST_DISK="64G"
}

validate_resources() {
    detect_host_resources

    local ram_mb="$1"
    local cpus="$2"
    local disk_gb

    disk_gb=$(echo "$DISK_SIZE" | sed 's/[Gg].*//')

    local max_ram=$((TOTAL_RAM * 75 / 100))
    local max_disk_gb=$((AVAIL_DISK_KB / 1024 / 1024 * 75 / 100))

    if [ "$ram_mb" -gt "$max_ram" ]; then
        echo "Error: Requested RAM (${ram_mb}MB) exceeds 75% of host RAM (${max_ram}MB)" >&2
        exit 1
    fi
    if [ "$cpus" -gt "$TOTAL_CPUS" ]; then
        echo "Error: Requested CPUs (${cpus}) exceeds available (${TOTAL_CPUS})" >&2
        exit 1
    fi
    if [ "${disk_gb:-0}" -gt "$max_disk_gb" ]; then
        echo "Error: Requested disk (${disk_gb}G) exceeds 75% of available space (${max_disk_gb}G)" >&2
        exit 1
    fi
}

interactive_mode() {
    suggest_resources
    echo "=== VM Setup (host: ${TOTAL_CPUS}cpus / ${TOTAL_RAM}MB ram) ==="
    read -rp "VM name [test]: " name
    VM_NAME="${name:-test}"
    read -rp "ISO path: " ISO_PATH
    read -rp "Disk size [${SUGGEST_DISK}]: " disk
    DISK_SIZE="${disk:-$SUGGEST_DISK}"
    read -rp "RAM in MB [${SUGGEST_RAM}]: " ram
    RAM="${ram:-$SUGGEST_RAM}"
    read -rp "Number of CPUs [${SUGGEST_CPUS}]: " cpus
    CPUS="${cpus:-$SUGGEST_CPUS}"

    if [ -z "$ISO_PATH" ]; then
        echo "Error: ISO path is required" >&2
        exit 1
    fi
    validate_resources "$RAM" "$CPUS"
}

arg_mode() {
    VM_NAME=""
    ISO_PATH=""
    DISK_SIZE="64G"
    RAM=""
    CPUS=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --name) VM_NAME="$2"; shift 2 ;;
            --iso) ISO_PATH="$2"; shift 2 ;;
            --disk) DISK_SIZE="$2"; shift 2 ;;
            --ram) RAM="$2"; shift 2 ;;
            --cpus) CPUS="$2"; shift 2 ;;
            --help|-h) show_help; exit 0 ;;
            *) echo "Unknown option: $1" >&2; show_help; exit 1 ;;
        esac
    done

    if [ -z "$VM_NAME" ]; then
        echo "Error: --name is required" >&2
        show_help
        exit 1
    fi
    if [ -n "$ISO_PATH" ] && [ ! -f "$ISO_PATH" ]; then
        echo "Error: ISO not found at $ISO_PATH" >&2
        exit 1
    fi
}

show_help() {
    cat <<EOF
Usage: $0 [mode] [options]

Modes:
  interactive    Prompt for all settings (default)
  launch         Launch VM with CLI args
  create         Create disk image only

Options:
  --name <name>  VM name (required)
  --iso <path>   Path to ISO (optional for launch/create)
  --disk <size>  Disk size, e.g. 64G (default: 64G)
  --ram <mb>     RAM in MB (default: half of host RAM)
  --cpus <n>     Number of CPUs (default: host CPUs - 1)
  --help, -h     Show this help

Examples:
  $0
  $0 launch --name myvm
  $0 launch --name myvm --iso /path/to.iso --ram 4096 --cpus 2
  $0 create --name myvm --disk 32G
EOF
}

create_disk() {
    DISK_PATH="${VM_DIR}/${VM_NAME}.qcow2"
    if [ ! -f "$DISK_PATH" ]; then
        echo "Creating disk image (${DISK_SIZE})..."
        qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
    else
        echo "Disk image already exists at $DISK_PATH"
    fi
}

launch_vm() {
    DISK_PATH="${VM_DIR}/${VM_NAME}.qcow2"
    echo "Launching $VM_NAME..."
    local args=(
        -name "$VM_NAME"
        -machine type=q35,accel=kvm
        -cpu host
        -smp "$CPUS"
        -m "$RAM"
        -drive file="$DISK_PATH",format=qcow2,if=virtio
        -nic user,model=virtio
        -vga virtio
        -display gtk,show-cursor=on,grab-on-hover=on
        -usb
        -device usb-tablet
        -audiodev pa,id=snd0
        -device intel-hda -device hda-duplex,audiodev=snd0
    )
    if [ -n "$ISO_PATH" ]; then
        args+=(-cdrom "$ISO_PATH")
    fi
    qemu-system-x86_64 "${args[@]}"
}

MODE="${1:-interactive}"
case "$MODE" in
    interactive)
        interactive_mode
        create_disk
        launch_vm
        ;;
    launch)
        shift
        arg_mode "$@"
        suggest_resources
        RAM="${RAM:-$SUGGEST_RAM}"
        CPUS="${CPUS:-$SUGGEST_CPUS}"
        validate_resources "$RAM" "$CPUS"
        DISK_PATH="${VM_DIR}/${VM_NAME}.qcow2"
        if [ ! -f "$DISK_PATH" ]; then
            echo "Error: Disk not found at $DISK_PATH" >&2
            exit 1
        fi
        launch_vm
        ;;
    create)
        shift
        arg_mode "$@"
        create_disk
        ;;
    --help|-h|help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
