#!/usr/bin/env bash
set -e

Asegurarse de ejecutar como root

if [ "$EUID" -ne 0 ]; then
echo "Por favor, ejecuta este script como root."
exit 1
fi

echo ""
echo "      POST-INSTALACIÓN GENTOO (GNOME BOXES)       "
echo ""

4. Agentes de integración para GNOME Boxes / QEMU / SPICE

echo ""
echo "--> 3. Instalando agentes de integración de GNOME Boxes..."
emerge --noreplace app-emulation/qemu-guest-agent x11-misc/spice-vdagent
rc-update add qemu-guest-agent default || true
rc-update add spice-vdagent default || true

5. Sincronizar y actualizar el sistema base

echo ""
echo "--> 4. Actualizando el árbol de Portage y paquetes base..."
emerge --sync
emerge @world

6. Selección de Entorno Gráfico

echo ""
echo ""
echo "         SELECCIÓN DE ENTORNO GRÁFICO             "
echo ""
echo "1) XFCE (Ligero, muy estable)"
echo "2) LXQt (Ultra ligero, basado en Qt)"
echo "3) GNOME (Entorno completo)"
echo "4) Ninguno / Configurar manualmente después"
read -p "Elige una opción [1-4] (Por defecto 1): " DESKTOP_CHOICE

case $DESKTOP_CHOICE in
2)
echo "--> Instalando LXQt y Xorg..."
emerge x11-base/xorg-server lxqt-base/lxqt-meta x11-misc/sddm
rc-update add display-manager default
sed -i 's/DISPLAYMANAGER="."/DISPLAYMANAGER="sddm"/' /etc/conf.d/display-manager 2>/dev/null || true
;;
3)
echo "--> Instalando GNOME..."
emerge gnome-base/gnome-light
rc-update add display-manager default
sed -i 's/DISPLAYMANAGER="."/DISPLAYMANAGER="gdm"/' /etc/conf.d/display-manager 2>/dev/null || true
;;
4)
echo "--> Omitiendo la instalación de entorno gráfico."
;;
)
echo "--> Instalando XFCE y LightDM..."
emerge x11-base/xorg-server xfce-base/xfce4-meta x11-misc/lightdm x11-misc/lightdm-gtk-greeter
rc-update add display-manager default
sed -i 's/DISPLAYMANAGER="."/DISPLAYMANAGER="lightdm"/' /etc/conf.d/display-manager 2>/dev/null || true
;;
esac

echo ""
echo ""
echo "    ¡POST-INSTALACIÓN COMPLETADA EXITOSAMENTE!   "
echo ""
echo "Puedes reiniciar el sistema escribiendo 'reboot'."
