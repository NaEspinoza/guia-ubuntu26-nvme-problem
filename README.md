# 🛠️ Ubuntu 26.04 Recovery — do-release-upgrade NVMe Boot Fix

[![Ubuntu](https://img.shields.io/badge/Ubuntu-26.04_LTS-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![License](https://img.shields.io/badge/License-CC_BY_4.0-lightgrey)](https://creativecommons.org/licenses/by/4.0/)
[![Tested](https://img.shields.io/badge/tested-October_2026-blue)](.)
[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-brightgreen)](CONTRIBUTING.md)
[![Stars](https://img.shields.io/github/stars/TU_USUARIO/ubuntu-26-upgrade-recovery?style=social)](.)

> **Una guía nacida de una noche entera de depuración en tiempo real.**  
> Si llegaste acá desde Google porque tu Ubuntu no arranca después del upgrade, estás en el lugar correcto.

---

## 📖 La historia detrás de esta guía

Todo empezó como algo rutinario: un usuario ejecutó `sudo do-release-upgrade` para actualizar su sistema de Ubuntu 24.04 LTS a Ubuntu 26.04 LTS. El proceso empezó bien, pero en algún punto — ya sea por una interrupción, un timeout, o simplemente mala suerte — **el upgrade quedó incompleto**.

Al reiniciar, en lugar del escritorio habitual, apareció una pantalla negra con texto blanco. Primero fue la shell clásica de BusyBox:

```
BusyBox v1.37.0 (Ubuntu) built-in shell (ash)
(initramfs) _
```

Después de varios intentos de reparación, evolucionó a la shell de dracut:

```
[FAILED] Failed to start systemd-modules-load.service
Warning: "/dev/disk/by-uuid/237a6d59-b228-4345-94c4-5f219f17a6cd" does not exist
dracut:/root# _
```

**El disco NVMe había desaparecido para el sistema.** No se trataba de datos perdidos — el disco físicamente estaba ahí, funcionando perfectamente. El problema era que el kernel no podía cargar los drivers necesarios para acceder a él durante el arranque.

### El camino de diagnóstico

Lo que siguió fue una sesión de diagnóstico exhaustiva que duró varias horas y reveló **tres capas de problemas encadenados**, cada una más profunda que la anterior:

**Capa 1 — La pista falsa del UUID:**  
Los primeros errores decían que el UUID del disco no existía. Se revisó el `/etc/fstab`, se compararon los UUIDs con `blkid`, todo coincidía perfectamente. El fstab estaba sano.

**Capa 2 — El cambio silencioso de Ubuntu 26.04:**  
Ubuntu 26.04 es la primera versión LTS en migrar de `initramfs-tools` a `dracut` como generador de initramfs. Este cambio no se completó durante el upgrade interrumpido. `dracut` no estaba instalado, pero el sistema lo necesitaba. Cada intento de regenerar el initramfs con `update-initramfs -u` (el comando "clásico") parecía funcionar, pero la imagen generada era **ignorada por completo** — GRUB usaba la de dracut, que no existía correctamente.

**Capa 3 — La causa raíz real:**  
Incluso después de instalar dracut, el problema persistía. El diagnóstico desde la shell de dracut reveló el error definitivo:

```
modprobe nvme_core
→ ERROR: could not insert 'nvme_core': Exec format error
```

Los módulos del kernel (`.ko.zst`) y el binario del kernel (`vmlinuz`) tenían **versiones internas diferentes**. El upgrade había instalado el kernel nuevo pero los módulos habían quedado de una versión intermedia. El kernel rechazaba cargar sus propios drivers por incompatibilidad de firma interna (`vermagic`).

La solución: reinstalar completamente el kernel y sus módulos desde un chroot, regenerar el initramfs con dracut en modo `--no-hostonly`, y reconstruir la configuración de GRUB.

**Resultado: sistema funcionando.** Ubuntu 26.04 arrancó correctamente.

---

## 🎯 ¿Qué resuelve esta guía?

Esta guía resuelve específicamente el siguiente escenario:

| Condición | Detalle |
|---|---|
| **Sistema origen** | Ubuntu 24.04 LTS |
| **Sistema destino** | Ubuntu 26.04 LTS |
| **Método de upgrade** | `sudo do-release-upgrade` |
| **Tipo de fallo** | Upgrade interrumpido (cualquier causa) |
| **Síntoma principal** | Shell de initramfs/dracut al arrancar |
| **Causa subyacente** | Módulos del kernel incompatibles + dracut no instalado |
| **Tipo de disco** | NVMe (documentado con Micron 2500, aplica a otros) |
| **Firmware** | UEFI (con nota para BIOS Legacy) |
| **Dual boot** | Compatible con Windows 11 en el mismo equipo |

### Lo que NO daña esta guía
- ✅ Los datos del disco están intactos y seguros
- ✅ La instalación de Windows (en dual boot) no se toca
- ✅ No requiere reinstalar Ubuntu desde cero
- ✅ Funciona aunque no tengas un USB de Ubuntu — sirve cualquier Live USB basado en Ubuntu (Linux Mint, Xubuntu, etc.)

---

## 📁 Contenido de este repositorio

```
ubuntu-26-upgrade-recovery/
│
├── README.md                    ← Estás aquí: historia y contexto
│
├── GUIA-PASO-A-PASO.md          ← La guía completa de recuperación
│
├── scripts/
│   ├── rescue-mount.sh          ← Monta el sistema dañado automáticamente
│   ├── diagnose.sh              ← Detecta qué falló y qué pasos seguir
│   └── fix-kernel-modules.sh   ← Repara los módulos y regenera el initramfs
│
└── cases/
    └── micron-2500-lenovo-ubuntu26.md  ← Caso documentado en detalle
```

---

## ⚡ Inicio rápido

Si ya sabés lo que hacés y solo querés los comandos:

```bash
# 1. Desde el Live USB, montar el sistema dañado
bash scripts/rescue-mount.sh nvme0n1p5 nvme0n1p1

# 2. Entrar al chroot
sudo chroot /mnt/rescate

# 3. Ejecutar el script de diagnóstico y reparación
bash /fix-kernel-modules.sh

# 4. Salir y reiniciar
exit && sudo umount -R /mnt/rescate && sudo reboot
```

Para el proceso completo con explicaciones → **[GUIA-PASO-A-PASO.md](GUIA-PASO-A-PASO.md)**

---

## 🤝 Contribuciones

¿Te pasó algo similar con hardware diferente? ¿Encontraste un paso que no funciona en tu configuración?  
Abrí un Issue o un Pull Request — cada caso documentado ayuda a la próxima persona que googlee este error a las 2 de la madrugada.

Ver [CONTRIBUTING.md](CONTRIBUTING.md) para cómo reportar un caso.

---

## 📄 Licencia

[Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)  
Podés compartir y adaptar este contenido libremente citando la fuente.

---

*Documentado en tiempo real — octubre 2026.*
