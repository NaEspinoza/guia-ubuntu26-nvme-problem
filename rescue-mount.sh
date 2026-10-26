#!/bin/bash
# =============================================================================
# rescue-mount.sh — Monta el sistema Ubuntu dañado para reparación
# =============================================================================
# Uso:
#   bash rescue-mount.sh                        # usa valores por defecto
#   bash rescue-mount.sh nvme0n1p5 nvme0n1p1   # especificá tus particiones
#
# Requiere: ejecutarse desde un Live USB de Ubuntu o Linux Mint
# =============================================================================

set -e

# ── Colores para output ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Sin color

# ── Parámetros ───────────────────────────────────────────────────────────────
ROOT_PART="${1:-}"
EFI_PART="${2:-}"
MOUNT_DIR="/mnt/rescate"

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Ubuntu 26.04 Recovery — rescue-mount    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
echo ""

# ── Detectar particiones si no se pasaron ────────────────────────────────────
if [ -z "$ROOT_PART" ]; then
  echo -e "${YELLOW}No especificaste particiones. Detectando automáticamente...${NC}"
  echo ""
  echo "Particiones disponibles:"
  echo "────────────────────────"
  lsblk -f | grep -E "NAME|ext4|vfat"
  echo ""
  echo -e "${YELLOW}Ingresá la partición RAÍZ de Ubuntu (ext4), ej: nvme0n1p5 o sda2:${NC}"
  read -r ROOT_PART
  echo -e "${YELLOW}Ingresá la partición EFI (vfat), ej: nvme0n1p1 o sda1:${NC}"
  read -r EFI_PART
fi

# ── Validar que existen ───────────────────────────────────────────────────────
if [ ! -b "/dev/$ROOT_PART" ]; then
  echo -e "${RED}ERROR: /dev/$ROOT_PART no existe o no es un dispositivo de bloque.${NC}"
  echo "Verificá el nombre con: lsblk -f"
  exit 1
fi

if [ ! -b "/dev/$EFI_PART" ]; then
  echo -e "${YELLOW}ADVERTENCIA: /dev/$EFI_PART no encontrado. Continuando sin montar EFI.${NC}"
  EFI_PART=""
fi

# ── Resumen antes de ejecutar ─────────────────────────────────────────────────
echo ""
echo "Configuración:"
echo "  Partición raíz : /dev/$ROOT_PART"
echo "  Partición EFI  : ${EFI_PART:+/dev/$EFI_PART}${EFI_PART:-"(no especificada)"}"
echo "  Punto de montaje: $MOUNT_DIR"
echo ""
echo -e "${YELLOW}¿Continuar? [S/n]${NC}"
read -r confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
  echo "Cancelado."
  exit 0
fi

# ── Montar ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}Montando sistema...${NC}"

sudo mkdir -p "$MOUNT_DIR"

echo -n "  [1/6] Partición raíz... "
sudo mount "/dev/$ROOT_PART" "$MOUNT_DIR" && echo -e "${GREEN}OK${NC}" || { echo -e "${RED}FALLO${NC}"; exit 1; }

if [ -n "$EFI_PART" ]; then
  echo -n "  [2/6] Partición EFI... "
  sudo mount "/dev/$EFI_PART" "$MOUNT_DIR/boot/efi" && echo -e "${GREEN}OK${NC}" || echo -e "${YELLOW}OMITIDO${NC}"
fi

echo -n "  [3/6] /dev... "
sudo mount --bind /dev "$MOUNT_DIR/dev" && echo -e "${GREEN}OK${NC}"

echo -n "  [4/6] /proc... "
sudo mount --bind /proc "$MOUNT_DIR/proc" && echo -e "${GREEN}OK${NC}"

echo -n "  [5/6] /sys... "
sudo mount --bind /sys "$MOUNT_DIR/sys" && echo -e "${GREEN}OK${NC}"

echo -n "  [6/6] /run... "
sudo mount --bind /run "$MOUNT_DIR/run" && echo -e "${GREEN}OK${NC}"

echo -n "  [+]   efivars... "
sudo mount --bind /sys/firmware/efi/efivars "$MOUNT_DIR/sys/firmware/efi/efivars" 2>/dev/null \
  && echo -e "${GREEN}OK${NC}" \
  || echo -e "${YELLOW}OMITIDO (sistema no UEFI o efivars no disponible)${NC}"

# ── Listo ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Sistema montado correctamente en $MOUNT_DIR   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "Siguiente paso:"
echo -e "  ${YELLOW}sudo chroot $MOUNT_DIR${NC}"
echo ""
echo "Para desmontar cuando termines:"
echo -e "  ${YELLOW}sudo umount -R $MOUNT_DIR${NC}"
echo ""
