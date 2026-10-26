#!/bin/bash
# =============================================================================
# diagnose.sh — Diagnostica qué falló en el upgrade y qué pasos seguir
# =============================================================================
# Uso: ejecutar DENTRO del chroot del sistema dañado
#   sudo chroot /mnt/rescate
#   bash /diagnose.sh
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ISSUES=0
STEPS=()

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Ubuntu 26.04 Recovery — Diagnóstico del sistema ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# ── 1. Detectar kernel instalado ─────────────────────────────────────────────
echo -e "${CYAN}[1/6] Kernel instalado${NC}"
KVER=$(ls /lib/modules 2>/dev/null | sort -V | tail -1)
if [ -z "$KVER" ]; then
  echo -e "  ${RED}✗ No se encontró ningún kernel en /lib/modules${NC}"
  ((ISSUES++))
  STEPS+=("CRÍTICO: No hay módulos de kernel instalados. Reinstalá el kernel.")
else
  echo -e "  ${GREEN}✓ Kernel más reciente: $KVER${NC}"
fi

# ── 2. Verificar vmlinuz ─────────────────────────────────────────────────────
echo -e "${CYAN}[2/6] Imagen del kernel (vmlinuz)${NC}"
if [ -f "/boot/vmlinuz-$KVER" ]; then
  echo -e "  ${GREEN}✓ /boot/vmlinuz-$KVER existe${NC}"
else
  echo -e "  ${RED}✗ /boot/vmlinuz-$KVER NO existe${NC}"
  ((ISSUES++))
  STEPS+=("PASO 7: Reinstalar linux-image-$KVER")
fi

# ── 3. Verificar coincidencia de vermagic ────────────────────────────────────
echo -e "${CYAN}[3/6] Compatibilidad de módulos con el kernel${NC}"
NVME_KO="/lib/modules/$KVER/kernel/drivers/nvme/host/nvme.ko.zst"
if [ -f "$NVME_KO" ]; then
  VERMAGIC=$(modinfo -F vermagic "$NVME_KO" 2>/dev/null | awk '{print $1}')
  if [ "$VERMAGIC" = "$KVER" ]; then
    echo -e "  ${GREEN}✓ Los módulos coinciden con el kernel ($VERMAGIC)${NC}"
  else
    echo -e "  ${RED}✗ MÓDULOS INCORRECTOS: módulo=$VERMAGIC, kernel=$KVER${NC}"
    echo -e "  ${RED}  Este es el error 'Exec format error' que ves al arrancar${NC}"
    ((ISSUES++))
    STEPS+=("PASO 7: Reinstalar linux-modules-$KVER (módulos no coinciden con el kernel)")
  fi
else
  echo -e "  ${RED}✗ Módulo nvme no encontrado en /lib/modules/$KVER${NC}"
  ((ISSUES++))
  STEPS+=("PASO 7: Reinstalar linux-modules-$KVER (módulo nvme faltante)")
fi

# ── 4. Verificar estado de dpkg ──────────────────────────────────────────────
echo -e "${CYAN}[4/6] Estado de los paquetes del kernel${NC}"
BAD_PKGS=$(dpkg -l 2>/dev/null | grep linux | grep -v "^ii\|^rc\|^|" | grep "^." || true)
if [ -z "$BAD_PKGS" ]; then
  echo -e "  ${GREEN}✓ Todos los paquetes del kernel en estado correcto (ii)${NC}"
else
  echo -e "  ${RED}✗ Paquetes en estado incompleto:${NC}"
  echo "$BAD_PKGS" | while read -r line; do
    echo -e "    ${RED}$line${NC}"
  done
  ((ISSUES++))
  STEPS+=("PASO 7: Ejecutar 'dpkg --configure -a && apt --fix-broken install'")
fi

# ── 5. Verificar dracut ──────────────────────────────────────────────────────
echo -e "${CYAN}[5/6] Estado de dracut (generador de initramfs de Ubuntu 26)${NC}"
DRACUT_STATUS=$(dpkg -l dracut 2>/dev/null | grep dracut | awk '{print $1}' | head -1)
if [ "$DRACUT_STATUS" = "ii" ]; then
  echo -e "  ${GREEN}✓ dracut instalado correctamente${NC}"
  # Verificar hook
  if ls /etc/kernel/install.d/ 2>/dev/null | grep -q dracut; then
    echo -e "  ${GREEN}✓ Hook de dracut en /etc/kernel/install.d/ presente${NC}"
  else
    echo -e "  ${YELLOW}⚠ Hook de dracut no encontrado en /etc/kernel/install.d/${NC}"
    STEPS+=("PASO 6: Reinstalar dracut para restaurar el hook de instalación")
  fi
else
  echo -e "  ${RED}✗ dracut NO está instalado (estado: ${DRACUT_STATUS:-desconocido})${NC}"
  echo -e "  ${RED}  Ubuntu 26.04 requiere dracut como generador de initramfs${NC}"
  ((ISSUES++))
  STEPS+=("PASO 6: Instalar dracut y dracut-core")
fi

# ── 6. Verificar initramfs existente ─────────────────────────────────────────
echo -e "${CYAN}[6/6] Initramfs generado${NC}"
INITRD="/boot/initrd.img-$KVER"
if [ -f "$INITRD" ]; then
  SIZE=$(du -h "$INITRD" | cut -f1)
  # Verificar si contiene nvme
  NVME_IN_INITRD=$(lsinitrd "$INITRD" 2>/dev/null | grep nvme | wc -l)
  if [ "$NVME_IN_INITRD" -gt 0 ]; then
    echo -e "  ${GREEN}✓ $INITRD existe ($SIZE) y contiene módulos nvme${NC}"
  else
    echo -e "  ${YELLOW}⚠ $INITRD existe ($SIZE) pero NO contiene módulos nvme${NC}"
    ((ISSUES++))
    STEPS+=("PASO 8: Regenerar initramfs con dracut --force --no-hostonly")
  fi
else
  echo -e "  ${RED}✗ $INITRD NO existe${NC}"
  ((ISSUES++))
  STEPS+=("PASO 8: Generar initramfs con dracut")
fi

# ── Resumen ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  RESUMEN DEL DIAGNÓSTICO${NC}"
echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo ""

if [ "$ISSUES" -eq 0 ]; then
  echo -e "${GREEN}✓ No se encontraron problemas en el diagnóstico.${NC}"
  echo ""
  echo "Si el sistema igual no arranca, ejecutá el script fix-kernel-modules.sh"
  echo "para forzar una regeneración completa."
else
  echo -e "${RED}Se encontraron $ISSUES problema(s). Pasos necesarios:${NC}"
  echo ""
  for i in "${!STEPS[@]}"; do
    echo -e "  ${YELLOW}$((i+1)). ${STEPS[$i]}${NC}"
  done
  echo ""
  echo -e "Podés ejecutar ${CYAN}bash /fix-kernel-modules.sh${NC} para resolver todo automáticamente."
fi
echo ""
