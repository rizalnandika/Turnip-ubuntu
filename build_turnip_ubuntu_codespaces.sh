#!/bin/bash
# Build Turnip 26.1.0 R4 untuk UBUNTU (DroidSpaces) — via GitHub Codespaces
# Cross-compile: Codespace Ubuntu 24.04 x86_64 -> ARM64 Linux (glibc)
#
# CARA PAKAI DI CODESPACES:
#   1. Di GitHub, buka repo Turnip-ubuntu > tombol hijau Code >
#      Codespaces > Create codespace on main.
#   2. Tunggu Codespace terbuka (VS Code di browser).
#   3. Buka Terminal di Codespaces (Ctrl+` atau menu Terminal > New Terminal).
#   4. Upload script ini ke Codespace (drag & drop ke file explorer),
#      atau jalankan langsung dari repo kalau sudah di-commit.
#   5. Jalankan:
#        chmod +x build_turnip_ubuntu_codespaces.sh
#        ./build_turnip_ubuntu_codespaces.sh 2>&1 | tee ~/turnip-build.log
#   6. Tunggu sampai selesai (20-40 menit). Hasil:
#        ~/Turnip-Ubuntu-26.1.0-R4-aarch64.zip
#      Download zip itu dari file explorer Codespaces (klik kanan > Download),
#      atau dari terminal: file itu ada di home.
#
# Mesa yang dipakai = commit yang sama dengan Turnip 26.1.0 R4 asli:
#   1e1d8931c7de6316b2c7b4c2c20e370079c23402
set -o pipefail

MESA_COMMIT="1e1d8931c7de6316b2c7b4c2c20e370079c23402"
WORKDIR="$HOME/turnip-build"
PREFIX="$HOME/turnip-26.1.0"
ZIP_OUT="$HOME/Turnip-Ubuntu-26.1.0-R4-aarch64.zip"

echo "=== Turnip Ubuntu 26.1.0 R4 (Codespaces cross-compile) ==="
echo "Mesa commit: $MESA_COMMIT"
uname -m
lsb_release -a 2>/dev/null || cat /etc/os-release
CODENAME="$(lsb_release -cs 2>/dev/null || echo noble)"
echo "Ubuntu codename: $CODENAME"

# --- 0. Batasi repo bawaan ke amd64, aktifkan deb-src, tambah repo ARM64 ---
echo "--- Membatasi repo bawaan ke amd64 ---"
for f in /etc/apt/sources.list.d/*.sources; do
    if [ -f "$f" ] && ! grep -q "^Architectures:" "$f"; then
        echo "  patch $f"
        sudo sed -i '/^Types:/a Architectures: amd64' "$f"
    fi
    sudo sed -i 's/^Types: deb$/Types: deb deb-src/' "$f" || true
done
grep -H "^Architectures:" /etc/apt/sources.list.d/*.sources 2>/dev/null || true
grep -H "^Types:" /etc/apt/sources.list.d/*.sources 2>/dev/null || true

sudo dpkg --add-architecture arm64 || true

cat <<EOF | sudo tee /etc/apt/sources.list.d/arm64-ports.list
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME main universe
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME-updates main universe
deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports $CODENAME-security main universe
EOF

sudo apt-get update || echo "WARN: apt update ada yang gagal, lanjut..."

# build-dep Mesa: minta ke Ubuntu daftar SEMUA paket build Mesa untuk arm64
sudo apt-get build-dep -y -a arm64 mesa || echo "build-dep gagal / tidak ada deb-src, lanjut dengan daftar manual"

# --- 1. Host tools + Meson baru dari pip ---
echo "--- Install host tools ---"
sudo apt-get install -y --no-install-recommends \
    meson ninja-build build-essential git python3-pip pkg-config \
    flex bison python3-mako python3-yaml \
    glslang-tools libglvnd-dev libwayland-bin || {
    echo "ERROR: install host tools gagal"
    sudo apt-get install -y -f || true
    sudo apt-get install -y --no-install-recommends meson ninja-build build-essential git pkg-config glslang-tools libglvnd-dev || exit 1
}
# Meson dari apt di 24.04 itu 1.3.2, Mesa 26.1.0 butuh >= 1.4.0
pip install --break-system-packages -U meson ninja mako
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
which meson ninja
meson --version
ninja --version
command -v glslangValidator || echo "PERINGATAN: glslangValidator tidak ketemu"

# --- 2. Cross toolchain ---
echo "--- Install cross toolchain ---"
sudo apt-get install -y --no-install-recommends \
    gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross || exit 1
aarch64-linux-gnu-gcc --version | head -1

sudo apt-get install -y pkg-config-aarch64-linux-gnu 2>/dev/null || {
    echo "pkg-config-aarch64-linux-gnu tidak ketemu, buat wrapper manual"
    cat <<'WRAPPER' | sudo tee /usr/bin/aarch64-linux-gnu-pkg-config >/dev/null
#!/bin/sh
export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/
exec /usr/bin/pkg-config "$@"
WRAPPER
    sudo chmod +x /usr/bin/aarch64-linux-gnu-pkg-config || true
}
ls -l /usr/bin/aarch64-linux-gnu-pkg-config || true
export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/
aarch64-linux-gnu-pkg-config --modversion libdrm || echo "libdrm belum ketemu di tahap ini (cek lagi setelah install lib ARM64)"

# --- 3. Library ARM64 ---
echo "--- Install library ARM64 ---"
sudo apt-get install -y --no-install-recommends \
    libdrm-dev:arm64 libwayland-dev:arm64 wayland-protocols \
    libwayland-egl-backend-dev:arm64 \
    libdisplay-info-dev:arm64 libudev-dev:arm64 libxrandr-dev:arm64 \
    libvulkan-dev:arm64 libegl-dev:arm64 libgbm-dev:arm64 \
    libglvnd-dev:arm64 \
    libx11-dev:arm64 libxext-dev:arm64 libxdamage-dev:arm64 \
    libxfixes-dev:arm64 libxxf86vm-dev:arm64 \
    libxcb-glx0-dev:arm64 libxcb-dri2-0-dev:arm64 libxcb-dri3-dev:arm64 \
    libxcb-present-dev:arm64 libxcb-randr0-dev:arm64 libxshmfence-dev:arm64 \
    libxcb-shm0-dev:arm64 libxcb-sync-dev:arm64 libxcb-xfixes0-dev:arm64 \
    libxcb-xkb-dev:arm64 libxcb-shape0-dev:arm64 libxkbcommon-dev:arm64 \
    libxkbcommon-x11-dev:arm64 libxinerama-dev:arm64 libxcursor-dev:arm64 \
    libelf-dev:arm64 libexpat1-dev:arm64 libzstd-dev:arm64 zlib1g-dev:arm64 || {
    echo "WARN: sebagian lib ARM64 gagal, coba perbaiki dan ulangi..."
    sudo apt-get install -y -f || true
    sudo apt-get install -y --no-install-recommends \
        libdrm-dev:arm64 libwayland-dev:arm64 wayland-protocols \
        libwayland-egl-backend-dev:arm64 \
        libglvnd-dev:arm64 \
        libx11-dev:arm64 libxext-dev:arm64 libxdamage-dev:arm64 \
        libxfixes-dev:arm64 libxxf86vm-dev:arm64 \
        libxcb-glx0-dev:arm64 libxcb-dri2-0-dev:arm64 libxcb-dri3-dev:arm64 \
        libxcb-present-dev:arm64 libxcb-randr0-dev:arm64 libxshmfence-dev:arm64 \
        libxcb-shm0-dev:arm64 libxcb-sync-dev:arm64 libxcb-xfixes0-dev:arm64 \
        libelf-dev:arm64 libexpat1-dev:arm64 libzstd-dev:arm64 zlib1g-dev:arm64 || exit 1
}

# --- 4. Ambil Mesa commit R4 — TARBALL ---
set -e
mkdir -p "$WORKDIR"
cd "$WORKDIR"
rm -rf mesa mesa.tar.gz
echo "--- Download Mesa tarball $MESA_COMMIT ---"
if curl -L --fail -o mesa.tar.gz "https://gitlab.freedesktop.org/mesa/mesa/-/archive/${MESA_COMMIT}/mesa-${MESA_COMMIT}.tar.gz"; then
    ls -lh mesa.tar.gz
    tar xzf mesa.tar.gz
    mv "mesa-${MESA_COMMIT}" mesa
    echo "Mesa dari tarball, commit: $MESA_COMMIT"
else
    echo "Tarball gagal, fallback ke git clone full (ini yang lama)..."
    git clone https://gitlab.freedesktop.org/mesa/mesa.git mesa
    cd mesa
    git checkout "$MESA_COMMIT"
    echo "Mesa HEAD: $(git rev-parse HEAD)"
    cd "$WORKDIR"
fi
cd "$WORKDIR/mesa"
cat VERSION 2>/dev/null || true

# --- 5. Cross file aarch64 ---
cat > "$WORKDIR/aarch64-linux-gnu.txt" <<'EOF'
[binaries]
ar = 'aarch64-linux-gnu-ar'
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'aarch64-linux-gnu-pkg-config'
[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
[properties]
pkg_config_libdir = '/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig'
sys_root = '/'
EOF
cat "$WORKDIR/aarch64-linux-gnu.txt"
export PKG_CONFIG_PATH=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/
aarch64-linux-gnu-pkg-config --modversion libdrm
aarch64-linux-gnu-pkg-config --modversion libdisplay-info || true

# --- 6. Configure + build ---
meson setup build \
    --cross-file "$WORKDIR/aarch64-linux-gnu.txt" \
    --prefix "$PREFIX" \
    -Dbuildtype=release \
    -Dplatforms=x11,wayland \
    -Dgallium-drivers=freedreno \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=kgsl \
    -Degl=enabled \
    -Dglx=dri \
    -Dgbm=enabled \
    -Dopengl=true \
    -Dgles1=enabled \
    -Dgles2=enabled \
    -Dshared-glapi=enabled \
    -Dvulkan-beta=true \
    -Dllvm=disabled \
    -Dzstd=enabled \
    -Dwerror=false \
    --force-fallback-for=spirv-tools,spirv-headers

ninja -C build -j"$(nproc)"
ninja -C build install

# --- 7. Verifikasi ---
echo "=== Verifikasi ==="
LIB="$(find "$PREFIX" -name 'libvulkan_freedreno.so' | head -1)"
echo "Lib: $LIB"
file "$LIB"
strings "$LIB" | grep -m1 "26.1.0-devel" || echo "PERINGATAN: string 26.1.0-devel tidak ketemu"
find "$PREFIX" -name '*freedreno*.json'
cat "$(find "$PREFIX" -name '*freedreno*.json' | head -1)" 2>/dev/null || true

# --- 8. Zip hasil ---
rm -f "$ZIP_OUT"
cd "$HOME"
zip -r "$ZIP_OUT" turnip-26.1.0
ls -lh "$ZIP_OUT"
unzip -l "$ZIP_OUT" | head -40

echo "=== SELESAI ==="
echo "Hasil: $ZIP_OUT"
