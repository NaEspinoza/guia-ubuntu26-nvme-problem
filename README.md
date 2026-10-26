# Reparar Ubuntu 26.04 tras `do-release-upgrade` fallido — NVMe no detectado en arranque

> **Síntoma principal:** Después de actualizar de Ubuntu 24.04 a 26.04, el sistema cae en una shell de `initramfs` (BusyBox o dracut) y no puede montar el disco raíz. El disco NVMe no aparece en `/dev/nvme*`.

---

## ¿Por qué ocurre esto?

Ubuntu 26.04 introdujo dos cambios importantes respecto a 24.04:

1. **Cambió el generador de initramfs:** de `initramfs-tools` a `dracut`. Si el upgrade se interrumpe (por falta de espacio, luz, red, etc.), `dracut` puede quedar sin instalar.
2. **Los módulos del kernel quedan en estado `half-installed`:** El nuevo kernel (`7.0.0-34-generic`) se instala pero sus módulos `.ko` quedan de una versión intermedia. Esto produce el error `Exec format error` al intentar cargarlos, y el disco NVMe nunca aparece.

Ambos problemas combinados hacen que el sistema arranque en la shell de emergencia sin poder acceder al disco.

---

## Requisitos

- Un USB booteable de **Ubuntu Live** o **Linux Mint Live** (cualquier versión reciente basada en Ubuntu).
- Acceso físico al equipo.
- El disco raíz de Ubuntu en **`/dev/nvme0n1p5`** (ajustá según tu caso — verificalo con `lsblk`).

---

## Paso 1: Identificar tus particiones

Arrancá desde el USB Live y abrí una terminal:

```bash
sudo lsblk -f
sudo blkid
```

Anotá:

- Tu **partición raíz** de Ubuntu (tipo `ext4`, generalmente `/dev/nvme0n1p5` o similar)
- Tu **partición EFI** (tipo `vfat`, generalmente `/dev/nvme0n1p1`)

---

## Paso 2: Montar el sistema y entrar al chroot

Reemplazá `nvme0n1p5` y `nvme0n1p1` por tus particiones reales:

```bash
sudo mkdir -p /mnt/rescate
sudo mount /dev/nvme0n1p5 /mnt/rescate
sudo mount /dev/nvme0n1p1 /mnt/rescate/boot/efi

for i in dev proc sys run; do
  sudo mount --bind /$i /mnt/rescate/$i
done

sudo mount --bind /sys/firmware/efi/efivars /mnt/rescate/sys/firmware/efi/efivars

sudo chroot /mnt/rescate
```

> 💡 **Tip:** Podés crear un script con estos comandos para no repetirlos cada vez que entrés al Live USB.

---

## Paso 3: Verificar el estado del problema

Dentro del chroot, verificá si `dracut` está instalado:

```bash
dpkg -l dracut dracut-core | tail -2
```

- Si muestra `un` (uninstalled) → dracut falta, continuá al **Paso 4A**.
- Si muestra `ii` (installed) → dracut está, pero los módulos del kernel pueden estar corruptos, continuá al **Paso 4B**.

Verificá también el estado de los módulos del kernel:

```bash
modinfo -F vermagic /lib/modules/$(ls /lib/modules | tail -1)/kernel/drivers/nvme/host/nvme.ko.zst
```

Este comando debe devolver exactamente la misma versión que el kernel instalado (ej: `7.0.0-34-generic`). Si devuelve una versión diferente, los módulos están corruptos → **Paso 4B**.

---

## Paso 4A: Instalar dracut (si falta)

```bash
apt update
apt install dracut dracut-core
```

Luego continuá con el **Paso 5**.

---

## Paso 4B: Reinstalar el kernel completo (módulos corruptos)

Este es el paso más importante y la causa raíz del problema:

```bash
# Reparar paquetes a medio instalar
dpkg --configure -a
apt --fix-broken install

# Reinstalar kernel y módulos completos
apt install --reinstall linux-image-$(uname -r 2>/dev/null || ls /boot/vmlinuz-* | tail -1 | sed 's/.*vmlinuz-//')
apt install --reinstall linux-modules-$(ls /boot/vmlinuz-* | tail -1 | sed 's/.*vmlinuz-//')

# Verificar que ahora coinciden
KVER=$(ls /lib/modules | sort -V | tail -1)
modinfo -F vermagic /lib/modules/$KVER/kernel/drivers/nvme/host/nvme.ko.zst
```

La última línea debe mostrar exactamente `$KVER SMP preempt mod_unload modversions`.

---

## Paso 5: Regenerar el initramfs con dracut

```bash
# Regenerar para todos los kernels instalados
for KVER in $(ls /lib/modules); do
  echo "Regenerando initramfs para $KVER..."
  dracut --force --no-hostonly \
    /boot/initrd.img-$KVER \
    $KVER
done

# Verificar que el módulo nvme quedó incluido
KVER=$(ls /lib/modules | sort -V | tail -1)
lsinitrd /boot/initrd.img-$KVER | grep nvme | head -5
```

Debe mostrar rutas de módulos nvme. Si no muestra nada, algo falló en el Paso 4B.

---

## Paso 6: Reinstalar GRUB y regenerar configuración

```bash
# Reinstalar GRUB para UEFI
grub-install --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=ubuntu \
  --recheck

# Regenerar grub.cfg (detecta Ubuntu y Windows si hay dual boot)
update-grub
```

---

## Paso 7: Terminar y reiniciar

```bash
# Terminar triggers pendientes de dpkg
dpkg --configure -a

exit
sudo umount -R /mnt/rescate
sudo reboot
```

Retirá el USB Live cuando el equipo reinicie.

---

## Paso 8: Dentro de Ubuntu 26.04 — limpieza final

Una vez que el sistema arranque correctamente:

```bash
# Terminar la actualización que quedó incompleta
sudo dpkg --configure -a
sudo apt --fix-broken install
sudo apt full-upgrade

# Limpiar kernels viejos si quedaron
sudo apt autoremove --purge
```

---

## Diagnóstico adicional: si el sistema sigue sin arrancar

Si después de todos los pasos anteriores el sistema sigue cayendo en la shell de dracut, ejecutá esto desde esa shell para obtener más información:

```bash
# ¿El disco NVMe es visible?
ls /dev/nvme*

# ¿Qué UUID busca el kernel?
cat /proc/cmdline

# ¿Ese UUID existe?
ls /dev/disk/by-uuid/

# Intentar cargar el módulo manualmente
modprobe nvme_core
modprobe nvme
ls /dev/nvme*

# Si modprobe falla con 'Exec format error' → ir al Paso 4B
# Si modprobe funciona pero el disco no aparece → problema de hardware o BIOS
```

---

## Causas comunes del upgrade fallido

| Causa | Síntoma en el upgrade |
| --- | --- |
| Falta de espacio en `/boot` | Error al descomprimir paquetes del kernel |
| Corte de luz o reinicio forzado | Paquetes en estado `half-installed` |
| Pérdida de conexión a internet | `apt` no puede descargar paquetes del nuevo kernel |
| Timeout del proceso | El upgrade se interrumpe silenciosamente |

---

## Contexto técnico: los cambios de Ubuntu 26.04

- **Ubuntu 26.04** es la primera versión LTS en usar **dracut** como generador de initramfs por defecto (reemplazando a `initramfs-tools`, que queda instalado por compatibilidad pero ya no genera la imagen que usa GRUB).
- Si usás `update-initramfs` (herramienta de `initramfs-tools`) en un sistema 26.04, la imagen generada **es ignorada** por el hook de instalación de kernels, que usa dracut. Por eso los pasos con `update-initramfs -u` no funcionan en 26.04.
- Para regenerar el initramfs correctamente en 26.04, siempre usá **`dracut --force`**.

---

## Créditos y referencias

- Diagnóstico y guía desarrollados colaborativamente resolviendo un caso real (octubre 2026).
- [Ubuntu 26.04 dracut migration announcement](https://discourse.ubuntu.com/t/spec-switch-to-dracut/54776)
- [Documentación de dracut](https://dracut-ng.github.io/dracut/)
