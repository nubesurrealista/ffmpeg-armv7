#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
# shellcheck source=versions.sh
source "$ROOT/scripts/versions.sh"

API=24
ABI=armeabi-v7a
CPU=armv7-a
JOBS=$(nproc)
WORK=${WORK_DIR:-$ROOT/build}
DIST=${DIST_DIR:-$ROOT/dist}
PREFIX=$WORK/prefix
export GNUPGHOME=$WORK/gnupg

FFMPEG_VERSION=${FFMPEG_VERSION:-$(latest_ffmpeg)}

echo "ffmpeg $FFMPEG_VERSION"
echo "ndk $NDK_REVISION"
echo "lame $LAME_VERSION"

rm -rf "$WORK" "$DIST"
mkdir -p "$WORK" "$DIST" "$GNUPGHOME"
chmod 700 "$GNUPGHOME"

fetch() {
    echo "fetch $1"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$2" "$1"
}

# ffmpeg: signed tarball
FFMPEG_TB=$WORK/ffmpeg-$FFMPEG_VERSION.tar.xz
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_TB"
fetch "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz.asc" "$FFMPEG_TB.asc"
curl -fsSL "$FFMPEG_GPG_KEY" | gpg --batch --quiet --import
status=$(gpg --batch --status-fd=1 --verify "$FFMPEG_TB.asc" "$FFMPEG_TB" 2>/dev/null) || {
    echo "ffmpeg signature invalid" >&2
    exit 1
}
grep -q "^\[GNUPG:\] VALIDSIG $FFMPEG_GPG_FPR " <<<"$status" || {
    echo "ffmpeg signing key mismatch" >&2
    exit 1
}

# ndk: official sha1 and revision
NDK_ZIP=$WORK/android-ndk-$NDK_VERSION-linux.zip
fetch "$NDK_URL" "$NDK_ZIP"
echo "$NDK_SHA1  $NDK_ZIP" | sha1sum -c -
unzip -q "$NDK_ZIP" -d "$WORK"
NDK=$WORK/android-ndk-$NDK_VERSION
REV=$(sed -n 's/^Pkg\.Revision[[:space:]]*=[[:space:]]*//p' "$NDK/source.properties" | tr -d '[:space:]')
[ "$REV" = "$NDK_REVISION" ] || { echo "ndk revision mismatch: $REV" >&2; exit 1; }

# lame: pinned hash
LAME_TB=$WORK/lame-$LAME_VERSION.tar.gz
fetch "$LAME_URL" "$LAME_TB"
echo "$LAME_SHA256  $LAME_TB" | sha256sum -c -

tar -xf "$FFMPEG_TB" -C "$WORK"
tar -xf "$LAME_TB" -C "$WORK"

HOST=linux-x86_64
TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/$HOST
export ANDROID_NDK_ROOT=$NDK
export PATH=$TOOLCHAIN/bin:$PATH

CC=$TOOLCHAIN/bin/armv7a-linux-androideabi${API}-clang
CXX=${CC}++
AR=$TOOLCHAIN/bin/llvm-ar
RANLIB=$TOOLCHAIN/bin/llvm-ranlib
NM=$TOOLCHAIN/bin/llvm-nm
STRIP=$TOOLCHAIN/bin/llvm-strip

for tool in "$CC" "$CXX" "$AR" "$RANLIB" "$NM" "$STRIP"; do
    [ -x "$tool" ] || { echo "missing $tool" >&2; exit 1; }
done

CFLAGS="-O2 -fPIC -march=$CPU -mfloat-abi=softfp -mfpu=neon -D__ANDROID_API__=$API -D_FILE_OFFSET_BITS=64"

# lame
cd "$WORK/lame-$LAME_VERSION"
CC="$CC" CXX="$CXX" AR="$AR" RANLIB="$RANLIB" NM="$NM" STRIP="$STRIP" LD="$CC" \
    CFLAGS="$CFLAGS" \
    ./configure --host=arm-linux-androideabi --prefix="$PREFIX" \
    --disable-shared --enable-static --disable-frontend --disable-gtktest
make -j"$JOBS"
make install

# ffmpeg
cd "$WORK/ffmpeg-$FFMPEG_VERSION"
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig
./configure \
    --prefix="$PREFIX" \
    --target-os=android \
    --arch=arm \
    --cpu="$CPU" \
    --enable-cross-compile \
    --enable-static \
    --disable-shared \
    --cc="$CC" \
    --cxx="$CXX" \
    --ar="$AR" \
    --as="$CC" \
    --ranlib="$RANLIB" \
    --nm="$NM" \
    --strip="$STRIP" \
    --sysroot="$TOOLCHAIN/sysroot" \
    --pkg-config=pkg-config \
    --pkg-config-flags=--static \
    --enable-jni \
    --enable-mediacodec \
    --enable-libmp3lame \
    --disable-network \
    --disable-vulkan \
    --disable-vaapi \
    --disable-vdpau \
    --disable-cuvid \
    --disable-nvenc \
    --disable-libdrm \
    --disable-v4l2-m2m \
    --disable-ffplay \
    --disable-doc \
    --disable-debug \
    --disable-symver \
    --disable-indevs \
    --disable-outdevs \
    --enable-indev=lavfi \
    --extra-cflags="$CFLAGS -I$PREFIX/include" \
    --extra-cxxflags="$CFLAGS -I$PREFIX/include" \
    --extra-ldflags="-L$PREFIX/lib" \
    --extra-libs="-landroid -lmediandk -lm -llog -ldl -latomic"
make -j"$JOBS"
make install

# package
install -m 0755 "$PREFIX/bin/ffmpeg" "$DIST/ffmpeg"
install -m 0755 "$PREFIX/bin/ffprobe" "$DIST/ffprobe"
"$STRIP" "$DIST/ffmpeg" "$DIST/ffprobe"
cp "$WORK/ffmpeg-$FFMPEG_VERSION/COPYING.LGPLv2.1" "$DIST/COPYING.LGPLv2.1"
cp "$WORK/lame-$LAME_VERSION/COPYING" "$DIST/COPYING.LAME"

cat > "$DIST/versions.txt" <<EOF
ffmpeg=$FFMPEG_VERSION
ndk=$NDK_REVISION
lame=$LAME_VERSION
api=$API
abi=$ABI
EOF
cat > "$DIST/versions.env" <<EOF
FFMPEG_VERSION=$FFMPEG_VERSION
NDK_REVISION=$NDK_REVISION
LAME_VERSION=$LAME_VERSION
EOF
(cd "$DIST" && sha256sum ffmpeg ffprobe > SHA256SUMS)
(cd "$DIST" && zip -9 -q "ffmpeg-armv7-$FFMPEG_VERSION.zip" \
    ffmpeg ffprobe versions.txt SHA256SUMS COPYING.LGPLv2.1 COPYING.LAME)

echo "built $DIST/ffmpeg-armv7-$FFMPEG_VERSION.zip"
