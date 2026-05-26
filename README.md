# VM Launcher

Interactive QEMU/KVM VM launcher with automatic resource detection and validation.

## Dependencies

- `qemu-full`

## Usage

```bash
./setup.sh                    # interactive mode (default)
./setup.sh launch --name foo --iso /path/to.iso --ram 4096 --cpus 4
./setup.sh create --name foo --disk 64G
```

Resource over-allocation is blocked — RAM, CPU, and disk are checked against host availability.
