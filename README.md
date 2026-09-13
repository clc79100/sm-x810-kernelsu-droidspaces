# SM-X810 — Kernel custom con KernelSU-Next + DroidSpaces

Kernel 5.15.153 GKI 2.0 para la **Samsung Galaxy Tab S9+ WiFi (SM-X810)**, con
[KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) integrado en modo GKI
(`CONFIG_KSU=y`, compilado dentro de `Image`, no como módulo) y las configs necesarias
para que [DroidSpaces](https://github.com/ravindu644/Droidspaces-OSS) (contenedores
Linux vía namespaces) funcione sobre él.

> **Toolchains y magiskboot — de dónde salen y cómo se instalan:** ver
> [`TOOLCHAINS.md`](TOOLCHAINS.md) para el detalle de descarga de ambos toolchains, qué
> son los ~90 symlinks que traen (alias de herramientas y versionado de libs, no tienen
> relación con la arquitectura destino), qué es lo que realmente fuerza la compilación
> cruzada a ARM (`CC`/`CROSS_COMPILE` con rutas absolutas + `ARCH=arm64`, no el
> `$PATH`), y de dónde bajar `magiskboot`.

## Requisitos

Nada de esto viene incluido en este repo (están en `.gitignore` o son binarios externos
al proyecto padre):

| Qué | Dónde debería estar | Para qué |
|---|---|---|
| `clang-r450784e` | `toolchains/clang-r450784e/` | Compilador del kernel |
| `arm-gnu-toolchain-14.2` | `toolchains/arm-gnu-toolchain-14.2/` | Cross-compiler aarch64 |
| [`magiskboot`](TOOLCHAINS.md#magiskboot--de-dónde-sale-y-cómo-se-instala) | binario standalone (p.ej. `magiskboot-linux-main/magiskboot`) | Desempaquetar/reempaquetar el `boot.img` |
| `boot.img` stock | extraído de un firmware Samsung oficial (`AP_*.tar.md5`) | Base sobre la que se reemplaza el kernel |
| `adb` + Odin | tu máquina / una máquina Windows | Flashear el resultado final |

`magiskboot` no participa en la compilación del kernel — solo se usa después, para
convertir el `Image` compilado en un `boot.img` flasheable.

## Paso 1 — Compilar el kernel

```bash
bash build_lkm.sh
```

Internamente, el script:
1. Genera `.config` desde `gki_defconfig`.
2. Le aplica encima `kernel/kernel_platform/common/custom.config` (deshabilita
   protecciones anti-root de Samsung, habilita `CONFIG_KSU=y`, agrega las configs de
   DroidSpaces) y corre `olddefconfig`.
3. Compila el target `Image` con los toolchains de `toolchains/`.

Resultado: `build/Image`.

## Paso 2 — Empaquetar con magiskboot

```bash
# Extraer el boot.img stock del firmware
tar -xf AP_*.tar.md5 boot.img.lz4
lz4 -d boot.img.lz4 boot.img

# Desempaquetar
./magiskboot unpack boot.img

# Reemplazar el kernel y reempaquetar
cp build/Image kernel
./magiskboot repack boot.img new-boot.img
```

## Paso 3 — Preparar el `.tar.md5` para Odin

```bash
tar -c new-boot.img > new-boot.tar
md5sum -t new-boot.tar >> new-boot.tar
mv new-boot.tar new-boot.tar.md5
```

## Paso 4 — Flashear

```bash
adb reboot download
```
En Odin: slot **AP** → `new-boot.tar.md5`, desmarcar **Re-Partition**, dejar los demás
slots vacíos, **Start**. El primer boot tarda 2-3 minutos — no interrumpir.

## Notas importantes

- **KernelSU-Next en modo GKI, no LKM**: el módulo se compila dentro de `Image` para
  que sus hooks se instalen en `kernel_init`, antes de que RKP (Knox) se active
  completamente. En modo LKM (`.ko` cargado post-boot) RKP puede bloquearlo.
- **`CONFIG_KNOX_NCM` debe quedar en `=y`**: aunque es una protección Knox, deshabilitarla
  rompe el link porque `net/netfilter/nf_conntrack_core.c` de Samsung llama a sus
  funciones fuera de cualquier `#ifdef`. No bloquea KernelSU.
- **`CONFIG_BRIDGE_NETFILTER` y `CONFIG_NF_TABLES` — bootloop confirmado**: rompen el
  enum `skb_ext_id` (kABI break) e interactúan mal con los hooks Knox NCM de Samsung. No
  habilitar, ni siquiera para Docker/nftables dentro de DroidSpaces (usar NAT mode +
  `iptables-legacy` dentro del contenedor en su lugar).
- **Fix de `KSU_GIT_VERSION` en `build_lkm.sh`**: KernelSU-Next calcula su propio número
  de versión leyendo el repo git de origen. Como este kernel integra KernelSU-Next vía
  symlink dentro del mismo repo (`common/drivers/kernelsu/` → `KernelSU-Next/kernel/`),
  git ve "mismo repo" en ambos lados y KernelSU-Next cae a una versión de fallback (`1`),
  que su propia app rechaza por considerarla demasiado vieja (banner rojo, código
  `33110`). El fix calcula la versión real directamente desde el repo de
  `KernelSU-Next/` y se la pasa explícitamente a `make`. **Pendiente de verificar** con
  un recompile + reflasheo.

Más contexto y el detalle de "por qué" de cada decisión: `NOTES.md` y `TEMP.md` en el
directorio padre del proyecto.
