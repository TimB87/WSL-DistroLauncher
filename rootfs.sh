#!/bin/sh

set -e

if test $(id -u) -ne 0
then
    echo 'This must be run as root.'
    exit 1
fi

if [ -z "$1" -o -z "$2" ]
then
    echo "Usage: $0 <iso> <arch>"
    exit 1
fi

for bin in 7z
do
    if ! command -V "$bin" 2>&1 > /dev/null
    then
        echo "Missing utility: $bin"
	exit 1
    fi
done

DIR="$(pwd)"
ISO="$(realpath "$1")"
ARCH="$2"
TMP="$(mktemp -d)"

cd "$TMP"
trap "rm -rf '$TMP'" EXIT

mkdir -p iso rootfs/var/lib/pkg
touch rootfs/var/lib/pkg/db

(cd iso; 7z x "$ISO")
RELEASE="$(cat iso/crux-media)"
VERSION="${RELEASE%-*}"
DATE="${RELEASE#*-}"
for i in iso/crux/core/*.pkg.tar.*
do
    echo "Adding $(basename "$i")"
    pkgadd -r rootfs "$i"
done
rm -rf iso

# Insert hostname templates
sed -i -e '/HOSTNAME=/cHOSTNAME=LXC_NAME' rootfs/etc/rc.conf
sed -i -e 's;localhost.*;& LXC_NAME;' rootfs/etc/hosts

# Fix default networking
cat > rootfs/etc/rc.d/net << 'EOF'
#!/bin/sh
#
# /etc/rc.d/net: start/stop network interface
#

case $1 in
    start)
        /sbin/dhcpcd -4 eth0
        ;;
    stop)
        /sbin/dhcpcd -x eth0
        ;;
    restart)
        $0 stop
        $0 start
        ;;
    *)
        echo "Usage: $0 [start|stop|restart]"
        ;;
esac
EOF

# Remove noclear from agettys
# Replace linux with xterm on agettys
# Remove serial console
# Remove existing powerfail entries
# Add an entry to allow LXC/LXD to shutdown the container
sed -i \
    -e 's;--noclear ;;' \
    -e 's;linux;xterm;' \
    -e '/s1:2:/d' \
    -e '/:powerfail:/d' \
    -e '/ctrlaltdel/cpf::powerfail:/sbin/telinit 0' \
    rootfs/etc/inittab

# Disable klogd in containers as it doesn't work
sed -i -e '/KLOG/d' -e 's;and klog ;;' rootfs/etc/rc.d/sysklogd

# Export a default LANG
sed -i -e '/LESS=/iexport LANG="C"' rootfs/etc/profile

# Disable startup functionality that doesn't work in a container
sed -i \
    -e '/# Start udev/,/^ *$/d' \
    -e '/# Create device-mapper device nodes and scan for LVM volume groups/,/^ *$/d' \
    -e '/# Mount root read-only/,/^ *$/d' \
    -e '/-f \/forcefsck/,/^ *$/d' \
    -e '/# Check filesystems/,/^ *$/d' \
    -e '/# Mount local filesystems/,/^ *$/d' \
    -e '/# Activate swap/,/^ *$/d' \
    -e '/hwclock/d' \
    -e '/# Load console font/,/^ *$/d' \
    -e '/# Load console keymap/,/^ *$/d' \
    -e '/# Screen blanks after 15 minutes idle time/,/^ *$/d' \
    -e '/# Run module initialization script/,/^ *$/d' \
    rootfs/etc/rc

# Disable shutdown functionality that doesn't work in a container
sed -i \
    -e '/# Set linefeed mode to avoid staircase effect/,/^ *$/d' \
    -e '/# Save system clock/,/^ *$/d' \
    -e '/# Turn off swap/,/^ *$/d' \
    -e '/# Unmount file systems/,/^ *$/d' \
    -e '/# Remount root filesystem read-only/,/^ *$/d' \
    rootfs/etc/rc.shutdown

# Disable certain functionality in single user login
sed -i \
    -e '/# Start udev/,/^ *$/d' \
    rootfs/etc/rc.single

# Remove variables that are not used in containers
sed -i -e '/FONT=/d' -e '/KEYMAP=/d' rootfs/etc/rc.conf

# Create the root tarball
cd rootfs
tar -czvf "$DIR/crux-$VERSION-$ARCH-$DATE-rootfs.tar.gz" *
cd ..
rm -rf rootfs
