#!/bin/bash
# =============================================================================
# Build script: SM-X810 (Galaxy Tab S9+ WiFi) — GKI 5.15.153
# Estrategia: KernelSU-Next en modo LKM (sin modificar el source del kernel)
#
# Kernel root compilado: kernel/kernel_platform/common/
# Toolchains usados: toolchains/clang-r450784e + toolchains/arm-gnu-toolchain-14.2
# (ambos ya están descargados, NO se descargan aquí)
#
# Uso: cd SM-X810_EUR_15_Opensource/ && bash build_lkm.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLCHAIN_BASE="${SCRIPT_DIR}/toolchains"
KERNEL_ROOT="${SCRIPT_DIR}/kernel/kernel_platform/common"
OUT_DIR="${SCRIPT_DIR}/out"
BUILD_DIR="${SCRIPT_DIR}/build"

CLANG_DIR="${TOOLCHAIN_BASE}/clang-r450784e"
GCC_DIR="${TOOLCHAIN_BASE}/arm-gnu-toolchain-14.2"

echo "[INFO] Script dir : ${SCRIPT_DIR}"
echo "[INFO] Kernel root: ${KERNEL_ROOT}"
echo "[INFO] Out dir    : ${OUT_DIR}"

# --- Validaciones previas ---
if [ ! -d "${CLANG_DIR}/bin" ]; then
    echo "[ERROR] clang-r450784e no encontrado en ${CLANG_DIR}"
    exit 1
fi
if [ ! -d "${GCC_DIR}/bin" ]; then
    echo "[ERROR] arm-gnu-toolchain-14.2 no encontrado en ${GCC_DIR}"
    exit 1
fi
if [ ! -f "${KERNEL_ROOT}/Makefile" ]; then
    echo "[ERROR] No se encontró Makefile en ${KERNEL_ROOT}"
    exit 1
fi

# --- Toolchain paths ---
export PATH="${CLANG_DIR}/bin:${GCC_DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${CLANG_DIR}/lib64:${LD_LIBRARY_PATH:-}"

echo "[INFO] Clang: $(clang --version | head -1)"
echo "[INFO] GCC  : $(aarch64-none-linux-gnu-gcc --version | head -1)"

# --- Variables de dispositivo Samsung (extraídas de build_kernel_GKI.sh) ---
export MODEL=gts9pwifi
export PROJECT_NAME=gts9pwifi
export REGION=eur
export CARRIER=open
export TARGET_BUILD_VARIANT=user
export PLATFORM_VERSION=15
export ANDROID_MAJOR_VERSION=v
export TARGET_SOC=kalama
export TARGET_PRODUCT=gki
export TARGET_BOARD_PLATFORM=gki

# --- Versión de KernelSU-Next ---
# El symlink common/drivers/kernelsu/ → KernelSU-Next/kernel/ pertenece al mismo
# repo git que el kernel (SM-X810_EUR_15_Opensource/), así el Kbuild ve
# GIT_ROOT == KERNEL_GIT_ROOT y activa el fallback KSU_VERSION=1.
# Calculamos la versión desde el repo real y la pasamos explícitamente a make.
KSU_DIR="$(realpath "${SCRIPT_DIR}/../KernelSU-Next")"
if [ -d "${KSU_DIR}/.git" ]; then
    KSU_GIT_COUNT=$(cd "${KSU_DIR}" && git rev-list --count HEAD 2>/dev/null || echo "0")
    KSU_GIT_TAG_VER=$(cd "${KSU_DIR}" && git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.1")
    echo "[INFO] KernelSU-Next version: $((30000 + KSU_GIT_COUNT)) (tag: ${KSU_GIT_TAG_VER})"
else
    echo "[WARN] KernelSU-Next no es un repo git; se usará versión fallback 1"
    KSU_GIT_COUNT="0"
    KSU_GIT_TAG_VER="v0.0.1"
fi

# --- Opciones de make ---
CLANG_BIN="${CLANG_DIR}/bin/clang"
GCC_PREFIX="${GCC_DIR}/bin/aarch64-none-linux-gnu-"

BUILD_OPTIONS=(
    -C "${KERNEL_ROOT}"
    O="${OUT_DIR}"
    -j"$(nproc)"
    ARCH=arm64
    LLVM=1
    LLVM_IAS=1
    CC="${CLANG_BIN}"
    CROSS_COMPILE="${GCC_PREFIX}"
    CLANG_TRIPLE=aarch64-linux-gnu-
    KBUILD_BUILD_USER="kernelsu-lkm"
    KBUILD_BUILD_HOST="sm-x810"
    # Red de seguridad: suprime warnings de variables no usadas en bloques
    # Samsung que quedan huérfanos cuando se deshabilitan sus configs.
    # NO suprime errores reales de función no declarada (-Wimplicit-function-declaration
    # se mantiene como error — ver nota sobre CONFIG_KNOX_NCM en custom.config).
    KCFLAGS="-Wno-error=unused-variable -Wno-unused-variable"
    # Fuerza la versión correcta de KernelSU-Next (ver comentario arriba)
    KSU_GIT_VERSION_VALID=1
    KSU_GIT_VERSION="${KSU_GIT_COUNT}"
    KSU_GIT_TAG="${KSU_GIT_TAG_VER}"
)

build_kernel() {
    mkdir -p "${OUT_DIR}" "${BUILD_DIR}"

    # 1. Generar .config base desde gki_defconfig
    echo ""
    echo "[INFO] === Paso 1: gki_defconfig ==="
    make "${BUILD_OPTIONS[@]}" gki_defconfig

    # 2. Merge custom.config (deshabilita anti-root, etc.)
    echo ""
    echo "[INFO] === Paso 2: merge custom.config ==="
    if [ -f "${KERNEL_ROOT}/custom.config" ]; then
        # Append al .config generado y regenerar con olddefconfig
        cat "${KERNEL_ROOT}/custom.config" >> "${OUT_DIR}/.config"
        make "${BUILD_OPTIONS[@]}" olddefconfig
        echo "[INFO] custom.config aplicado correctamente."
    else
        echo "[WARN] No se encontró custom.config en ${KERNEL_ROOT}. Continuando sin él."
        echo "[WARN] Ruta esperada: ${KERNEL_ROOT}/custom.config"
    fi

    # 3. (Opcional) menuconfig interactivo — descomentar si se quiere ajustar configs
    # echo "[INFO] === menuconfig ==="
    # make "${BUILD_OPTIONS[@]}" menuconfig

    # 4. Compilar Image
    echo ""
    echo "[INFO] === Paso 3: compilando kernel Image ==="
    make "${BUILD_OPTIONS[@]}" Image

    # 5. Copiar resultado
    cp "${OUT_DIR}/arch/arm64/boot/Image" "${BUILD_DIR}/Image"
    echo ""
    echo "[INFO] =============================================="
    echo "[INFO]  BUILD COMPLETADO"
    echo "[INFO]  Kernel Image en: ${BUILD_DIR}/Image"
    echo "[INFO] =============================================="
    echo ""
    echo "[NEXT] Para KernelSU-Next LKM:"
    echo "       1. Clonar KernelSU-Next y compilar el .ko contra este kernel:"
    echo "          KDIR=${OUT_DIR} make -C KernelSU-Next/kernel"
    echo "       2. El .ko resultante se incluye en AnyKernel3 junto con Image"
}

build_kernel
