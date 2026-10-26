#!/bin/bash
# =============================================================================
# fix-kernel-modules.sh — Repara módulos del kernel y regenera el initramfs
# =============================================================================
# Uso: ejecutar DENTRO del chroot del sistema dañado
#   sudo chroot /mnt/rescate
#   bash /fix-kernel-modules.sh
#
# Qué hace:
#   1. Repara paquetes interrumpidos (dpkg --configure -a)
#   2. Reinstala el kernel y sus módulos completos
#   3. Instala dracut si falta
#   4. Regenera el initramfs con --no-hostonly
#   5. Reinstala GRUB
#   6. Regenera grub.cfg
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ERRORS=0

# ── Función de log ────────────────────────────────────────────────────────────
log_ok()   { echo -e "  ${GREEN}✓ $1${NC}"; }
log_err()  { echo -e "  ${RED}✗ $1${NC}"; ((ERRORS++)) || true; }
log_warn() { echo -e "  ${YELLOW}⚠ $1${NC}"; }
log_step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# ── Verificar que estamos en chroot ──────────────────────────────────────────
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Ubuntu 26.04 Recovery — fix-kernel-modules.sh   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$(stat -c %d:%i /)" = "$(stat -c %d:%i /proc/1/root/.)" ]; then
  echo -e "${RED}ERROR: Este script debe ejecutarse DENTRO del chroot.${NC}"
  echo ""
  echo "Pasos:"
  echo "  1. bash rescue-mount.sh [tu_particion_raiz] [tu_particion_efi]"
  echo "  2. sudo chroot /mnt/rescate"
  echo "  3. bash /fix-kernel-modules.sh"
  exit 1
fi

log_ok "Ejecutándose dentro del chroot"

# ── Verificar internet ───────────────────────────────────────────────────────
log_step "Verificando conectividad"
if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
  log_warn "Sin internet. Intentando configurar DNS..."
  echo "nameserver 8.8.8.8" > /etc/resolv.conf
  if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
    log_err "Sin conexión a internet. No se podrán reinstalar paquetes."
    echo ""
    echo -e "${YELLOW}Asegurate de que el Live USB tenga internet y volvé a intentar.${NC}"
    exit 1
  fi
fi
log_ok "Internet disponible"

# ── Paso 1: Reparar paquetes interrumpidos ───────────────────────────────────
log_step "Paso 1/6 — Reparando paquetes interrumpidos"

echo "  Ejecutando dpkg --configure -a..."
dpkg --configure -a 2>&1 | sed 's/^/    /' || true

echo "  Ejecutando apt --fix-broken install..."
apt --fix-broken install -y 2>&1 | grep -E "^(Inst|Remv|E:|W:)" | sed 's/^/    /' || true

log_ok "Paquetes reparados"

# ── Paso 2: Actualizar lista de repos ────────────────────────────────────────
log_step "Paso 2/6 — Actualizando repositorios"
apt update -qq 2>&1 | tail -3 | sed 's/^/  /'
log_ok "Repositorios actualizados"

# ── Paso 3: Detectar versión del kernel ──────────────────────────────────────
log_step "Paso 3/6 — Detectando kernel"
KVER=$(ls /lib/modules | sort -V | tail -1)
echo "  Kernel más reciente: $KVER"

# Verificar si los módulos ya coinciden
NVME_KO="/lib/modules/$KVER/kernel/drivers/nvme/host/nvme.ko.zst"
NEEDS_REINSTALL=false

if [ -f "$NVME_KO" ]; then
  VERMAGIC=$(modinfo -F vermagic "$NVME_KO" 2>/dev/null | awk '{print $1}')
  if [ "$VERMAGIC" != "$KVER" ]; then
    log_warn "Módulos incorrectos: módulo=$VERMAGIC, kernel=$KVER"
    NEEDS_REINSTALL=true
  else
    log_ok "Módulos coinciden con el kernel"
  fi
else
  log_warn "Módulo nvme no encontrado"
  NEEDS_REINSTALL=true
fi

# ── Paso 4: Reinstalar kernel si necesario ───────────────────────────────────
if [ "$NEEDS_REINSTALL" = true ]; then
  log_step "Paso 4/6 — Reinstalando kernel y módulos"

  echo "  Reinstalando linux-image-$KVER..."
  apt install --reinstall -y "linux-image-$KVER" 2>&1 \
    | grep -E "^(Inst|Unp|Set|E:|W:)" | sed 's/^/    /' \
    || log_err "Fallo al reinstalar linux-image-$KVER"

  echo "  Reinstalando linux-modules-$KVER..."
  apt install --reinstall -y "linux-modules-$KVER" 2>&1 \
    | grep -E "^(Inst|Unp|Set|E:|W:)" | sed 's/^/    /' \
    || log_err "Fallo al reinstalar linux-modules-$KVER"

  echo "  Intentando linux-modules-extra-$KVER (puede no existir)..."
  apt install --reinstall -y "linux-modules-extra-$KVER" 2>&1 \
    | grep -E "^(Inst|Unp|Set|E:|W:)" | sed 's/^/    /' \
    || log_warn "linux-modules-extra no disponible (es normal, continuando)"

  echo "  Reconstruyendo árbol de dependencias de módulos..."
  depmod -a "$KVER"

  # Verificar resultado
  VERMAGIC=$(modinfo -F vermagic "$NVME_KO" 2>/dev/null | awk '{print $1}')
  if [ "$VERMAGIC" = "$KVER" ]; then
    log_ok "Módulos reinstalados y verificados correctamente"
  else
    log_err "Los módulos siguen sin coincidir después de reinstalar. Vermagic: $VERMAGIC"
  fi
else
  log_step "Paso 4/6 — Reinstalación de kernel"
  log_ok "No necesario — módulos ya coinciden"
fi

# ── Paso 5: Instalar dracut si falta ─────────────────────────────────────────
log_step "Paso 5/6 — Verificando dracut"
DRACUT_STATUS=$(dpkg -l dracut 2>/dev/null | grep "^ii.*dracut " | awk '{print $1}')

if [ "$DRACUT_STATUS" != "ii" ]; then
  echo "  Instalando dracut..."
  apt install -y dracut dracut-core 2>&1 \
    | grep -E "^(Inst|Unp|Set|E:|W:)" | sed 's/^/    /' \
    || log_err "Fallo al instalar dracut"
  log_ok "dracut instalado"
else
  log_ok "dracut ya estaba instalado"
fi

# ── Paso 6: Configurar y regenerar initramfs ─────────────────────────────────
log_step "Paso 6/6 — Regenerando initramfs con dracut"

# Crear configuración para forzar drivers de almacenamiento
mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/storage-drivers.conf << 'CONF'
# Forzar inclusión de drivers de almacenamiento
# Necesario al regenerar desde entorno chroot (--no-hostonly no los detecta automáticamente)
add_drivers+=" nvme nvme_core nvme_auth "
CONF
log_ok "Configuración de dracut creada en /etc/dracut.conf.d/storage-drivers.conf"

# Regenerar para todos los kernels
for K in $(ls /lib/modules | sort -V); do
  echo ""
  echo -e "  Regenerando para $K..."
  if dracut --force --no-hostonly \
      /boot/initrd.img-$K \
      $K 2>&1 | grep -E "^(E|W|dracut)" | sed 's/^/    /'; then
    # Verificar que nvme quedó incluido
    NVME_COUNT=$(lsinitrd /boot/initrd.img-$K 2>/dev/null | grep -c nvme || true)
    if [ "$NVME_COUNT" -gt 0 ]; then
      log_ok "initrd.img-$K generado (contiene $NVME_COUNT entradas nvme)"
    else
      log_warn "initrd.img-$K generado pero no contiene módulos nvme"
    fi
  else
    log_err "Fallo al regenerar initramfs para $K"
  fi
done

# ── GRUB ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━ Reinstalando GRUB y regenerando configuración ━━━${NC}"

# Detectar UEFI vs BIOS
if [ -d /sys/firmware/efi/efivars ] && ls /sys/firmware/efi/efivars/ &>/dev/null; then
  echo "  Sistema UEFI detectado"
  grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id=ubuntu \
    --recheck 2>&1 | sed 's/^/    /' \
    && log_ok "GRUB UEFI reinstalado" \
    || log_warn "grub-install tuvo advertencias (puede ser normal)"
else
  echo "  Sistema BIOS Legacy detectado"
  log_warn "No se puede determinar el disco automáticamente en BIOS Legacy."
  echo "  Ejecutá manualmente: grub-install /dev/sda  (reemplazá sda por tu disco)"
fi

echo "  Regenerando grub.cfg..."
update-grub 2>&1 | grep -E "^(Found|Generating|Warning|Error)" | sed 's/^/    /' \
  && log_ok "grub.cfg regenerado" \
  || log_err "Fallo al regenerar grub.cfg"

# Terminar triggers pendientes
dpkg --configure -a 2>&1 | grep -v "^$" | sed 's/^/  /' || true

# ── Resumen final ────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  RESULTADO FINAL${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo ""

if [ "$ERRORS" -eq 0 ]; then
  echo -e "${GREEN}✅ Reparación completada sin errores.${NC}"
  echo ""
  echo "Próximos pasos:"
  echo -e "  1. ${YELLOW}exit${NC}                          ← salir del chroot"
  echo -e "  2. ${YELLOW}sudo umount -R /mnt/rescate${NC}   ← desmontar"
  echo -e "  3. ${YELLOW}sudo reboot${NC}                   ← reiniciar (sin el USB)"
  echo ""
  echo "Una vez en Ubuntu 26.04:"
  echo -e "  4. ${YELLOW}sudo apt full-upgrade${NC}"
  echo -e "  5. ${YELLOW}sudo apt autoremove --purge${NC}"
else
  echo -e "${RED}⚠ Se encontraron $ERRORS error(es) durante la reparación.${NC}"
  echo ""
  echo "Revisá los mensajes de error arriba y consultá GUIA-PASO-A-PASO.md"
  echo "para el Paso 12 (diagnóstico adicional)."
fi
echo ""
