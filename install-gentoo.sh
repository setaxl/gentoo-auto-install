#!/usr/bin/env bash
set -e

# --- CONFIGURACIÓN ---
DISK="/dev/vda"
HOSTNAME="gentoo-boxes"
TIMEZONE="America/Caracas"
ROOT_PASSWORD="TuPasswordAqui"
KERNEL_PKG="sys-kernel/gentoo-kernel-bin"

echo "=================================================="
echo "      SELECCIÓN DE PERFIL DE STAGE3 GENTOO        "
echo "=================================================="
echo "1) Base OpenRC (Minimal / Servidor)"
echo "2) Desktop OpenRC (Con perfiles de escritorio)"
read -p "Elige una opción [1 o 2] (Por defecto 1): " STAGE_CHOICE

case $STAGE_CHOICE in
    2)
        EXACT_STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/20261018T124555Z/stage3-amd64-desktop-openrc-20261018T124555Z.tar.xz"
        echo "--> Has seleccionado: Desktop OpenRC"
        ;;
    *)
        EXACT_STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/20261018T124555Z/stage3-amd64-openrc-20261018T124555Z.tar.xz"
        echo "--> Has seleccionado: Base OpenRC"
        ;;
esac
echo "=================================================="

echo "==> 0. Desmontando cualquier punto previo en $DISK..."
swapoff -a 2>/dev/null || true
umount -R /mnt/gentoo 2>/dev/null || true

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
mkdir -p /mnt/gentoo
mount "${DISK}3" /mnt/gentoo
mkdir -p /mnt/gentoo/boot/efi
mount "${DISK}1" /mnt/gentoo/boot/efi

echo "==> 4. Descargando y extrayendo el Stage3 elegido..."
cd /mnt/gentoo
wget "$EXACT_STAGE3_URL"
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
rm stage3-*.tar.xz

echo "==> 5. Configurando make.conf base..."
cat <<EOF >> /mnt/gentoo/etc/portage/make.conf
COMMON_FLAGS="-O2 -pipe -march=native"
CFLAGS="\${COMMON_FLAGS}"
CXXFLAGS="\${COMMON_FLAGS}"
FCFLAGS="\${COMMON_FLAGS}"
FFLAGS="\${COMMON_FLAGS}"
MAKEOPTS="-j3"
EMERGE_DEFAULT_OPTS="--jobs=2 --load-average=3.5"
ACCEPT_KEYWORDS="~amd64"
ACCEPT_LICENSE="*"
GRUB_PLATFORMS="efi-64"
EOF

echo "==> 6. Preparando entorno chroot..."
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run

# Montar variables EFI si el sistema anfitrión usa UEFI
if [ -d /sys/firmware/efi/efivars ]; then
    mkdir -p /mnt/gentoo/sys/firmware/efi/efivars
    mount --bind /sys/firmware/efi/efivars /mnt/gentoo/sys/firmware/efi/efivars
fi

echo "==> 7. Ejecutando la segunda fase dentro del chroot..."
cat <<CHROOT_SCRIPT > /mnt/gentoo/tmp/inside_chroot.sh
#!/usr/bin/env bash
set -e

source /etc/profile
export PS1="(chroot) \$PS1"

# Zona horaria básica
echo "$TIMEZONE" > /etc/timezone

# 1. Sincronizar repositorio de Portage
mkdir -p /var/db/repos/gentoo
emerge-webrsync

# 2. Configuraciones de entorno y localización
emerge --config sys-libs/timezone-data
echo "es_VE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set es_VE.utf8

# 3. Configurar USE flags requeridos por el kernel (evita bloqueos)
mkdir -p /etc/portage/package.use
echo "sys-kernel/installkernel dracut" >> /etc/portage/package.use/custom

# 4. Instalación del Kernel
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

# Instalación de GRUB con soporte removible/fallback para máquinas virtuales
emerge sys-boot/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> INSTALACIÓN COMPLETADA EXITOSAMENTE <=="
CHROOT_SCRIPT

chmod +x /mnt/gentoo/tmp/inside_chroot.sh
chroot /mnt/gentoo /tmp/inside_chroot.sh
rm /mnt/gentoo/tmp/inside_chroot.sh

echo "==> Desmontando particiones..."
umount -R /mnt/gentoo

echo "¡Listo! Puedes reiniciar el sistema con el comando 'reboot'."
