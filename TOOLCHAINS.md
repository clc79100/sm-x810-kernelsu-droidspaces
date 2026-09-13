# Toolchains y magiskboot — de dónde salen, qué son los symlinks, y qué hace que compile para ARM

Este documento detalla `toolchains/` (excluido del repo por `.gitignore`, 2.6 GB) y el
binario `magiskboot` (fuera del repo, en un directorio hermano) para quien necesite
reconstruirlos en otra máquina o entender qué hay ahí dentro.

## De dónde se descargan

Ambos toolchains son *mirrors*/releases republicados por
[ravindu644/Android-Kernel-Tutorials](https://github.com/ravindu644/Android-Kernel-Tutorials)
en su sección de [releases](https://github.com/ravindu644/Android-Kernel-Tutorials/releases/tag/toolchains)
— no son un fork ni código propio, son binarios prebuilt de terceros:

```bash
mkdir -p toolchains && cd toolchains

# Clang r450784e — build oficial de Google/AOSP para kernels Linux 5.15
wget https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/clang-r450784e.tar.gz
tar -xvf clang-r450784e.tar.gz

# ARM GNU Toolchain 14.2 — binutils/gcc oficial de ARM para aarch64
wget https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
tar -xvf arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
```

Confirmado en `Android-Kernel-Tutorials/toolchains/README.md` (línea de la sección
"Linux 5.15") que esta combinación es la correcta para el kernel 5.15.123–5.15.149 —
la SM-X810 corre 5.15.153, dentro de ese rango.

- **`clang-r450784e`**: build prebuilt de Clang/LLVM que Google usa internamente para
  compilar los kernels GKI (viene del repo AOSP `prebuilts/clang`, tag `r450784e`).
- **`arm-gnu-toolchain-14.2`**: distribución oficial de ARM Ltd. (`arm-gnu-toolchain`,
  antes "Linaro"), usada aquí solo para sus **binutils** (`as`, `ld`, `objcopy`, etc. con
  prefijo `aarch64-none-linux-gnu-`) — Clang genera el código, pero delega ensamblado y
  linkeo final a estas herramientas vía `CROSS_COMPILE`.

## Los symlinks — qué son (y qué NO son)

Al listar `toolchains/*/bin` y `toolchains/*/lib64` se ven ~90 symlinks en total. **No
tienen nada que ver con evitar el compilador amd64 de Debian** — son la estructura
interna normal de cualquier paquete de Clang o GCC prebuilt, de dos tipos:

**1. Alias de herramientas** (un mismo binario responde a varios nombres, según cómo se
lo invoque — patrón común en LLVM/binutils):
```
llvm-ranlib -> llvm-ar        # llvm-ar también implementa ranlib
llvm-lib    -> llvm-ar        # y "lib" (equivalente de MSVC)
ld.lld      -> lld            # lld es un linker multi-modo (ELF/Mach-O/COFF/wasm)
ld64.lld    -> lld
clang.real  -> clang-14       # el binario real de clang tiene el nombre versionado
clang-cl    -> clang.real     # front-end "estilo MSVC" del mismo binario
clang++.real -> clang.real    # el front-end de C++ es el mismo binario que C
```

**2. Versionado estándar de librerías compartidas** (`.so` → `.so.N` → `.so.N.N.N`, para
que el linker dinámico encuentre la versión exacta en runtime):
```
libstdc++.so.6 -> libstdc++.so.6.0.33
libc++.so      -> libc++.so.1
libcc1.so      -> libcc1.so.0.0.0
```

**3. El intérprete Python embebido de clang** (`clang-r450784e/python3/`):
```
python3 -> python3.9
```

Nada de esto decide qué arquitectura de código máquina se genera — es empaquetado
estándar, idéntico al que traería cualquier distro Linux para sus propios paquetes de
gcc/clang nativos.

## Qué es lo que SÍ hace que se compile para ARM y no para amd64

Dos cosas, ninguna es un symlink:

**1. `CC=` y `CROSS_COMPILE=` con rutas absolutas** (en `build_lkm.sh`, dentro de
`BUILD_OPTIONS`):
```bash
LLVM=1
LLVM_IAS=1
CC="${CLANG_DIR}/bin/clang"                              # ruta absoluta al clang de arriba
CROSS_COMPILE="${GCC_DIR}/bin/aarch64-none-linux-gnu-"   # prefijo absoluto para as/ld/objcopy
CLANG_TRIPLE=aarch64-linux-gnu-
ARCH=arm64
```
Al pasarle a `make` una ruta absoluta en `CC`, el build **nunca llega a mirar** el
`cc`/`gcc` del sistema (el de Debian, amd64) — ni siquiera importa si están en el
`$PATH` o no. Clang es un compilador cruzado por diseño: un solo binario `clang` sabe
generar código para cualquier arquitectura si se le dice `--target=aarch64-linux-gnu`
(eso es lo que hace `CLANG_TRIPLE` internamente en el build system del kernel). Por
eso solo hace falta **un** Clang, no una versión "para ARM" separada — lo que sí debe
ser específico de la arquitectura destino son los **binutils** del `CROSS_COMPILE`
(`aarch64-none-linux-gnu-as`, `-ld`, `-objcopy`...), que es justamente lo que aporta
`arm-gnu-toolchain-14.2`.

**2. `ARCH=arm64`**: le dice al Kbuild del kernel qué árbol de headers/asm usar
(`arch/arm64/` en vez de `arch/x86/`) — independiente del compilador.

`toolchains/path.sh` (que exporta ambos `bin/` al `$PATH`) es solo una comodidad para
poder invocar `clang --version` o `aarch64-none-linux-gnu-gcc --version` a mano en la
terminal — `build_lkm.sh` no depende de él porque usa rutas absolutas.

## magiskboot — de dónde sale y cómo se instala

`magiskboot` no es un toolchain de compilación — es el binario de
[Magisk](https://github.com/topjohnwu/Magisk) que sabe leer/escribir el formato de
`boot.img` de Android. Se usa después de compilar, para meter el `Image` custom dentro
de un `boot.img` flasheable (ver `README.md`). En este proyecto vive en un directorio
hermano (`magiskboot-linux-main/`), fuera del repo del kernel.

Instrucciones (adaptadas del `README.md` que trae ese propio directorio, basado en el
build de [magojohnji/magiskboot](https://github.com/magojohnji/magiskboot) — compilado
desde el source de Magisk vía GitHub Actions):

```bash
# Requiere una máquina Linux
wget https://github.com/magojohnji/magiskboot/archive/refs/heads/main.zip
unzip main.zip

# El binario para host Linux x86_64 está en la subcarpeta x86_64/ del zip
# (también trae arm64-v8a/, armeabi-v7a/ y x86/ — esos son para uso on-device, no para compilar)
chmod +x magiskboot-main/x86_64/magiskboot
```

Si no confías en un binario de terceros sin auditar, la alternativa es compilar
`magiskboot` vos mismo desde el [source oficial de Magisk](https://github.com/topjohnwu/Magisk)
— el `README.md` de `magiskboot-linux-main/` avisa explícitamente de esto ("If you do
not trust this, DO NOT use it!").

Para Windows: [svoboda18/magiskboot](https://github.com/svoboda18/magiskboot) (no
aplica a este pipeline, que corre en Linux).

## Referencia

Ver también `README.md` (raíz de este repo) para el pipeline completo de compilación,
y `Android-Kernel-Tutorials/toolchains/README.md` (fuera de este repo) para las
combinaciones de toolchain usadas en otras versiones de kernel.
