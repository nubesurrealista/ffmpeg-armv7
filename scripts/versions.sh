#!/usr/bin/env bash
# Version policy: fixed series, latest patch.

FFMPEG_SERIES="9.0"
FFMPEG_GPG_KEY="https://ffmpeg.org/ffmpeg-devel.asc"
FFMPEG_GPG_FPR="FCF986EA15E6E293A5644F10B4322F04D67658D8"

NDK_VERSION="r29"
NDK_REVISION="29.0.14206865"
NDK_SHA1="87e2bb7e9be5d6a1c6cdf5ec40dd4e0c6d07c30b"
NDK_URL="https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"

LAME_VERSION="3.100"
LAME_SHA256="ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e"
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz"

latest_ffmpeg() {
    local tags version
    tags=$(git ls-remote --tags --refs https://github.com/FFmpeg/FFmpeg.git \
        "refs/tags/n${FFMPEG_SERIES}.*") || return 1
    version=$(printf '%s\n' "$tags" |
        sed 's#.*refs/tags/n##' |
        grep -E "^${FFMPEG_SERIES//./\\.}\.[0-9]+$" |
        sort -V |
        tail -n 1) || true
    [ -n "$version" ] || { echo "ffmpeg ${FFMPEG_SERIES}.x not found" >&2; return 1; }
    printf '%s\n' "$version"
}
