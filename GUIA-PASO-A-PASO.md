# 📋 Guía paso a paso — Recuperar Ubuntu 26.04 tras upgrade fallido

> **Antes de empezar:** esta guía asume que ya leíste el README y entendés el contexto.  
> Si llegaste directo acá desde Google: tu disco NVMe está bien, tus datos están intactos.  
> El problema es de drivers del kernel. Vamos a solucionarlo.

---

## Índice

1. [Lo que necesitás](#1-lo-que-necesitás)
2. [Bootear desde el Live USB](#2-bootear-desde-el-live-usb)
3. [Identificar tus particiones](#3-identificar-tus-particiones)
4. [Montar el sistema y entrar al chroot](#4-montar-el-sistema-y-entrar-al-chroot)
5. [Diagnóstico — qué falló exactamente](#5-diagnóstico--qué-falló-exactamente)
6. [Reparación A — Instalar dracut si falta](#6-reparación-a--instalar-dracut-si-falta)
7. [Reparación B — Reinstalar el kernel completo](#7-reparación-b--reinstalar-el-kernel-completo)
8. [Regenerar el initramfs con dracut](#8-regenerar-el-initramfs-con-dracut)
9. [Reinstalar GRUB](#9-reinstalar-grub)
10. [Salir, desmontar y reiniciar](#10-salir-desmontar-y-reiniciar)
11. [Limpieza final dentro de Ubuntu](#11-limpieza-final-dentro-de-ubuntu)
12. [¿Sigue sin funcionar?](#12-sigue-sin-funcionar)

---

## 1. Lo que necesitás

| Requisito | Detalle |
|---|---|
| **USB Live** | Ubuntu, Linux Mint, Xubuntu — cualquier distro basada en Ubuntu |
| **Acceso al BIOS/boot menu** | Para arrancar desde el USB |
| **Internet** | El equipo debe tener red desde el Live USB para reinstalar paquetes |
| **Tiempo** | ~30 minutos si todo va bien |

> 💡 **Linux Mint funciona igual que Ubuntu** para este proceso. Si tenés un USB Ventoy con cualquier ISO basada en Ubuntu, sirve.

---

## 2. Bootear desde el Live USB

1. Insertá el USB y reiniciá
2. Al aparecer el logo del fabricante, presioná la tecla de boot menu:
   - **Lenovo:** `F12`
   - **HP:** `F9` o `Esc`
   - **Dell:** `F12`
   - **ASUS:** `F8` o `Esc`
   - **Acer:** `F12`
3. Seleccioná el USB de la lista
4. Elegí **"Probar / Try"** — **NO instalar**
5. Abrí una terminal: `Ctrl + Alt + T`

---

## 3. Identificar tus particiones

```bash
sudo lsblk -f
```

Buscá en la salida:

```
NAME        FSTYPE  LABEL        UUID                                 MOUNTPOINT
nvme0n1
├─nvme0n1p1 vfat    SYSTEM DRV   8C66-B909                            ← tu partición EFI
├─nvme0n1p3 ntfs    Windows-SSD                                       ← Windows (no tocar)
└─nvme0n1p5 ext4                 237a6d59-b228-4345-94c4-5f219f17a6cd ← tu Ubuntu (raíz)
```

**Anotá:**
- Partición raíz (ext4): en este ejemplo `/dev/nvme0n1p5`
- Partición EFI (vfat): en este ejemplo `/dev/nvme0n1p1`

> ⚠️ **Dual boot con Windows:** las particiones NTFS son de Windows. No las montés ni las modifiquées.

Si tenés **disco SATA** en lugar de NVMe, tus particiones serán `/dev/sda1`, `/dev/sda2`, etc.

---

## 4. Montar el sistema y entrar al chroot

Reemplazá `nvme0n1p5` y `nvme0n1p1` con **tus particiones reales** del paso anterior:

```bash
# Crear el punto de montaje
sudo mkdir -p /mnt/rescate

# Montar la partición raíz de Ubuntu
sudo mount /dev/nvme0n1p5 /mnt/rescate

# Montar la partición EFI
sudo mount /dev/nvme0n1p1 /mnt/rescate/boot/efi

# Montar los filesystems virtuales (necesarios para apt y chroot)
for i in dev proc sys run; do
  sudo mount --bind /$i /mnt/rescate/$i
done

# Montar las variables EFI (necesario para reinstalar GRUB en UEFI)
sudo mount --bind /sys/firmware/efi/efivars /mnt/rescate/sys/firmware/efi/efivars

# Entrar al sistema dañado
sudo chroot /mnt/rescate
```

Deberías ver el prompt cambiar a algo como `root@mint:/#`.  
**Ahora estás "dentro" de tu Ubuntu.** Todo lo que hacés desde acá afecta a tu sistema instalado.

> 💡 **Tip:** Si vas a entrar y salir varias veces, usá el script `scripts/rescue-mount.sh` incluido en este repo para no repetir estos comandos.

---

## 5. Diagnóstico — qué falló exactamente

Ejecutá estos tres diagnósticos **en orden**. Cada uno te dice a qué paso ir.

### Diagnóstico 1: ¿Está dracut instalado?

```bash
dpkg -l dracut dracut-core 2>/dev/null | grep -E "^ii|^un" | awk '{print $1, $2}'
```

| Salida | Significa | Ir a |
|---|---|---|
| `un dracut` | dracut NO instalado | **Paso 6** |
| `ii dracut` | dracut instalado | Diagnóstico 2 |
| Sin salida | paquete desconocido | **Paso 6** |

---

### Diagnóstico 2: ¿Los módulos del kernel coinciden?

```bash
# Detectar el kernel más reciente
KVER=$(ls /lib/modules | sort -V | tail -1)
echo "Kernel detectado: $KVER"

# Verificar que los módulos son de esa versión exacta
modinfo -F vermagic /lib/modules/$KVER/kernel/drivers/nvme/host/nvme.ko.zst 2>/dev/null
```

| Salida | Significa | Ir a |
|---|---|---|
| `7.0.0-34-generic SMP preempt mod_unload...` (coincide con $KVER) | ✅ Módulos correctos | **Paso 8** |
| Una versión diferente | ❌ Módulos incorrectos | **Paso 7** |
| `Exec format error` o error de lectura | ❌ Módulos corruptos | **Paso 7** |

---

### Diagnóstico 3: Estado de los paquetes del kernel

```bash
dpkg -l | grep linux-image
```

| Estado (1ª col) | Significa |
|---|---|
| `ii` | Instalado correctamente ✅ |
| `iF`, `iH`, `iU` | Instalación incompleta ❌ → **Paso 7** |
| `rc` | Removido (normal para kernels viejos) |

---

## 6. Reparación A — Instalar dracut si falta

> **Hacé este paso si el Diagnóstico 1 mostró `un dracut`.**

```bash
# Actualizar lista de paquetes
apt update

# Instalar dracut
apt install dracut dracut-core
```

Verificá que quedó bien:

```bash
dpkg -l dracut dracut-core | grep "^ii"
# Debe mostrar dos líneas con "ii"

ls /etc/kernel/install.d/
# Debe mostrar archivos, incluyendo algo con "dracut"
```

Luego **saltá directo al Paso 8** (regenerar initramfs).

---

## 7. Reparación B — Reinstalar el kernel completo

> **Hacé este paso si el Diagnóstico 2 mostró versiones que no coinciden o el Diagnóstico 3 mostró paquetes incompletos.**  
> Este es el paso más importante — la causa raíz del problema en la mayoría de los casos.

### 7.1 Reparar paquetes interrumpidos

```bash
dpkg --configure -a
apt --fix-broken install
```

Si aparecen errores de dependencias no resolvibles:

```bash
apt install -f
```

### 7.2 Detectar la versión del kernel a reparar

```bash
KVER=$(ls /lib/modules | sort -V | tail -1)
echo "Reparando kernel: $KVER"
```

### 7.3 Reinstalar imagen y módulos del kernel

```bash
# Reinstalar la imagen del kernel (el binario vmlinuz)
apt install --reinstall linux-image-$KVER

# Reinstalar los módulos del kernel
apt install --reinstall linux-modules-$KVER

# Intentar módulos extra (puede no existir — es normal si falla)
apt install --reinstall linux-modules-extra-$KVER 2>/dev/null \
  && echo "Módulos extra instalados" \
  || echo "Módulos extra no disponibles (normal, continuar)"
```

> ⚠️ **Si apt no tiene internet:** verificá que `/etc/resolv.conf` tenga DNS.
> ```bash
> cat /etc/resolv.conf
> # Si está vacío o solo tiene comentarios:
> echo "nameserver 8.8.8.8" > /etc/resolv.conf
> apt update
> ```

### 7.4 Reconstruir el árbol de dependencias de módulos

```bash
depmod -a $KVER
```

### 7.5 Verificar que la reparación funcionó

```bash
modinfo -F vermagic /lib/modules/$KVER/kernel/drivers/nvme/host/nvme.ko.zst
```

**Debe mostrar exactamente** la misma versión que `$KVER`. Si sigue mostrando otra versión, repetí el paso 7.3.

---

## 8. Regenerar el initramfs con dracut

> ⚠️ **Importante:** En Ubuntu 26.04 usá **siempre `dracut`**, nunca `update-initramfs`.  
> El comando `update-initramfs -u` genera una imagen que GRUB ignora completamente.

### 8.1 Crear configuración para forzar drivers de almacenamiento

```bash
mkdir -p /etc/dracut.conf.d

cat > /etc/dracut.conf.d/storage-drivers.conf << 'CONF'
# Forzar inclusión de drivers de almacenamiento NVMe
# Necesario especialmente al regenerar desde un entorno chroot
add_drivers+=" nvme nvme_core nvme_auth "
CONF
```

### 8.2 Regenerar para todos los kernels instalados

```bash
for KVER in $(ls /lib/modules | sort -V); do
  echo ""
  echo "=== Regenerando initramfs para kernel $KVER ==="
  dracut --force --no-hostonly \
    /boot/initrd.img-$KVER \
    $KVER
  echo "=== Completado: $KVER ==="
done
```

> 💡 **Por qué `--no-hostonly`:** en modo `hostonly` (el default), dracut solo incluye drivers del hardware "actual". Desde un chroot en el Live USB, el hardware "actual" es el del Live USB — que no tiene NVMe. Sin `--no-hostonly`, el driver nvme no se incluye y el problema persiste.

### 8.3 Verificar que los módulos nvme quedaron incluidos

```bash
KVER=$(ls /lib/modules | sort -V | tail -1)
lsinitrd /boot/initrd.img-$KVER | grep nvme
```

Debe mostrar algo como:

```
usr/lib/modules/7.0.0-34-generic/kernel/drivers/nvme/host/nvme.ko.zst
usr/lib/modules/7.0.0-34-generic/kernel/drivers/nvme/host/nvme-core.ko.zst
usr/lib/modules/7.0.0-34-generic/kernel/drivers/nvme/host/nvme-auth.ko.zst
```

Si no muestra nada → revisá el Paso 7 (puede que los módulos no se reinstalaron correctamente).

---

## 9. Reinstalar GRUB

> Este paso es **obligatorio si GRUB estuvo involucrado en el problema** (pantalla negra sin menú de GRUB) o **recomendado como precaución** para asegurar que `grub.cfg` apunta a los initramfs recién generados.

### 9.1 Detectar si tu sistema es UEFI o BIOS Legacy

```bash
ls /sys/firmware/efi/efivars/ 2>/dev/null | wc -l
```

- **Número mayor a 0** → UEFI → seguí con **9.2**
- **Error o 0** → BIOS Legacy → seguí con **9.3**

### 9.2 Para sistemas UEFI (la mayoría de equipos post-2012)

```bash
grub-install \
  --target=x86_64-efi \
  --efi-directory=/boot/efi \
  --bootloader-id=ubuntu \
  --recheck
```

### 9.3 Para sistemas BIOS Legacy

```bash
# Reemplazá /dev/sda por tu disco principal (sin número de partición)
grub-install /dev/sda
```

### 9.4 Regenerar grub.cfg

```bash
update-grub
```

En la salida verificá que aparezcan:
- `Found linux image: /boot/vmlinuz-X.X.X-XX-generic` ✅
- `Found initrd image: /boot/initrd.img-X.X.X-XX-generic` ✅
- `Found Windows Boot Manager on ...` ✅ (si tenés dual boot)

---

## 10. Salir, desmontar y reiniciar

```bash
# Terminar cualquier trigger de dpkg pendiente
dpkg --configure -a

# Salir del chroot
exit

# Desmontar todo de forma segura (el -R desmonta recursivamente)
sudo umount -R /mnt/rescate

# Reiniciar
sudo reboot
```

**Retirá el USB cuando el equipo reinicie.** Si lo dejás conectado podría volver a bootear desde él.

---

## 11. Limpieza final dentro de Ubuntu

Una vez que Ubuntu 26.04 arranque correctamente:

```bash
# Terminar el upgrade que quedó incompleto
sudo dpkg --configure -a
sudo apt --fix-broken install

# Completar todos los paquetes pendientes del upgrade
sudo apt full-upgrade

# Limpiar kernels viejos y paquetes huérfanos
sudo apt autoremove --purge

# Verificar que no quedan paquetes en estado problemático
dpkg -l | grep -v "^ii\|^rc\|^|\|^+" | grep "^."
```

Si el último comando no devuelve nada → el sistema está limpio y la reparación fue exitosa.

---

## 12. ¿Sigue sin funcionar?

### Desde la shell de dracut, ejecutá el diagnóstico completo:

```bash
# ¿El disco NVMe existe para el kernel?
ls /dev/nvme*

# ¿Qué UUID busca el kernel?
cat /proc/cmdline

# ¿Ese UUID existe en /dev?
ls /dev/disk/by-uuid/ 2>/dev/null || echo "Directorio no existe"

# Intentar cargar el driver manualmente
modprobe nvme_core 2>&1
modprobe nvme 2>&1
ls /dev/nvme*

# Ver el log completo de dracut
cat /run/initramfs/rdsosreport.txt | tail -60
```

### Tabla de síntomas y soluciones adicionales

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Exec format error` al hacer modprobe | Módulos incorrectos | Volvé al Paso 7 |
| `/dev/nvme*` existe pero UUID no coincide | fstab desactualizado | Editar `/etc/fstab` con el UUID correcto |
| `/dev/nvme*` no existe ni con modprobe | Driver no incluido en initramfs | Volvé al Paso 8 con `--add-drivers "nvme nvme_core"` |
| `dracut` no se puede instalar (errores de dep) | Sistema muy fragmentado | Intentar `apt install -f` primero |
| Sin internet en el chroot | DNS no configurado | `echo "nameserver 8.8.8.8" > /etc/resolv.conf` |

### Si nada funciona: recuperar los datos y reinstalar

Si el sistema está demasiado fragmentado para reparar, tus datos siguen intactos. Desde el Live USB:

```bash
# Montar solo la partición de datos
sudo mount /dev/nvme0n1p5 /mnt/rescate

# Copiar tus archivos al disco FREEDISK u otro disco externo
sudo cp -r /mnt/rescate/home/TU_USUARIO/ /destino/

# Luego instalás Ubuntu 26.04 desde cero con el USB de instalación
```

---

*Para el contexto técnico completo de por qué ocurre esto → [README.md](README.md)*  
*Para los scripts automatizados → [scripts/](scripts/)*
