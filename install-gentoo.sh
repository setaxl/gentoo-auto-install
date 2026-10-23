#!/usr/bin/env bash
set -e

# --- CONFIGURACIÓN ---
DISK="/dev/sda"
HOSTNAME="gentoo-vbox"
TIMEZONE="America/Caracas"
ROOT_PASSWORD="TuPasswordAqui"
KERNEL_PKG="sys-kernel/gentoo-kernel-bin"

echo "==> 1. Particionando disco $DISK..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 512MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary linux-swap 512MiB 4512MiB
parted -s "$DISK" mkpart primary ext4 4512MiB 100%

echo "==> 2. Formateando particiones..."
mkfs.vfat -F 32 "${DISK}1"
mkswap "${DISK}2"
swapon "${DISK}2"
mkfs.ext4 -F "${DISK}3"

echo "==> 3. Montando particiones..."
mount "${DISK}3" /mnt/gentoo
mkdir -p /mnt/gentoo/boot/efi
mount "${DISK}1" /mnt/gentoo/boot/efi

echo "==> 4. Descargando y extrayendo Stage3..."
cd /mnt/gentoo
# Descarga automáticamente el último tarball disponible de Stage3 OpenRC
STAGE3_URL=$(curl -s https://downloads.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-openrc.txt | grep -v '^#' | awk '{print $1}')
wget "https://downloads.gentoo.org/releases/amd64/autobuilds/${STAGE3_URL}"
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz

echo "==> 5. Configurando make.conf base..."
cat <<EOF >> /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"
ACCEPT_KEYWORDS="~amd64"
ACCEPT_LICENSE="*"
EOF

echo "==> 6. Preparando entorno chroot..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run

echo "==> 7. Ejecutando la segunda fase dentro del chroot..."
cat <<CHROOT_SCRIPT > /mnt/gentoo/tmp/inside_chroot.sh
#!/usr/bin/env bash
set -e

source /etc/profile
export PS1="(chroot) \$PS1"

# Zona horaria y Locale
echo "$TIMEZONE" > /etc/timezone
emerge --config sys-libs/timezone-data
echo "es_VE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set es_VE.utf8

# Sincronización y Kernel
emerge-webrsync
USE="-introspection -doc" emerge $KERNEL_PKG

# Tabla fstab
cat <<EOF > /etc/fstab
${DISK}1   /boot/efi   vfat    defaults,noatime   0 2
${DISK}2   none        swap    sw                 0 0
${DISK}3   /           ext4    noatime            0 1
EOF

# Red y Hostname
echo "$HOSTNAME" > /etc/hostname
emerge net-misc/dhcpcd
rc-update add dhcpcd default

# Contraseña Root
echo "root:$ROOT_PASSWORD" | chpasswd

# Instalación de GRUB
emerge sys-boot/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> INSTALACIÓN COMPLETADA EXITOSAMENTE <=="
CHROOT_SCRIPT

chmod +x /mnt/gentoo/tmp/inside_chroot.sh
chroot /mnt/gentoo /tmp/inside_chroot.sh
rm /mnt/gentoo/tmp/inside_chroot.sh

echo "==> Desmontando particiones..."
umount -R /mnt/gentoo

echo "¡Listo! Puedes reiniciar el sistema con el comando 'reboot'."
