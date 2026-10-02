#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT_DIR/Packaging/sources.env"
[[ "$(uname -sm)" == 'Darwin arm64' ]] || { echo 'FFmpeg build requires Apple Silicon macOS.' >&2; exit 1; }
DEST="$ROOT_DIR/build/Backend/bin"
LICENSES="$ROOT_DIR/build/Backend/licenses/ffmpeg"
ARCHIVE="$ROOT_DIR/build/downloads/ffmpeg-$FFMPEG_VERSION.tar.xz"
"$ROOT_DIR/Packaging/fetch_verified.sh" "$FFMPEG_URL" "$FFMPEG_SHA256" "$ARCHIVE"
WORK="$(mktemp -d "$ROOT_DIR/build/ffmpeg.XXXXXX")"
cleanup() {
  local status=$?
  if [[ "$status" != 0 && -f "$WORK/ffmpeg-$FFMPEG_VERSION/ffbuild/config.log" ]]; then
    mkdir -p "$LICENSES"
    cp "$WORK/ffmpeg-$FFMPEG_VERSION/ffbuild/config.log" "$LICENSES/CONFIGURE-FAILURE.log"
    tail -n 100 "$LICENSES/CONFIGURE-FAILURE.log" >&2
  fi
  rm -rf "$WORK"
  return "$status"
}
trap cleanup EXIT
tar -xf "$ARCHIVE" -C "$WORK"
cd "$WORK/ffmpeg-$FFMPEG_VERSION"
mkdir -p "$DEST" "$LICENSES"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
CLANG="$(xcrun --find clang)"

# Only local audio decoding and PCM WAV output. No optional codec libraries or network protocols.
./configure \
  --prefix="$WORK/install" --cc="$CLANG" --host-cc="$CLANG" --arch=arm64 --target-os=darwin \
  --sysroot="$SDKROOT" \
  --host-cflags="-isysroot $SDKROOT -mmacosx-version-min=26.0" \
  --host-ldflags="-isysroot $SDKROOT -mmacosx-version-min=26.0" \
  --extra-cflags='-mmacosx-version-min=26.0' --extra-ldflags='-mmacosx-version-min=26.0' \
  --disable-all --disable-autodetect --disable-network --disable-gpl --disable-nonfree \
  --disable-version3 --disable-doc --disable-debug --disable-shared --enable-static \
  --enable-pthreads --enable-ffmpeg --enable-ffprobe \
  --enable-avcodec --enable-avformat --enable-avfilter --enable-swresample \
  --enable-decoder=aac,aac_fixed,alac,flac,mp3,mp3float,pcm_s8,pcm_u8,pcm_s16be,pcm_s16le,pcm_s24be,pcm_s24le,pcm_s32be,pcm_s32le,pcm_f32be,pcm_f32le,pcm_f64be,pcm_f64le \
  --enable-parser=aac,flac,mpegaudio --enable-demuxer=mov,mp3,wav,aiff,flac \
  --enable-encoder=pcm_s16le,pcm_s24le,pcm_s32le,pcm_f32le --enable-muxer=wav,pcm_f32le \
  --enable-filter=aresample,aformat,anull,atrim,asetpts,pan --enable-protocol=file,pipe
make -j "${FFMPEG_BUILD_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || printf 1)}" ffmpeg ffprobe
install -m 755 ffmpeg ffprobe "$DEST/"
"$DEST/ffmpeg" -version > "$LICENSES/BUILD-CONFIGURATION.txt"
if grep -Eq -- '--enable-gpl|--enable-nonfree|--enable-version3' "$LICENSES/BUILD-CONFIGURATION.txt"; then
  echo 'Refusing GPL/nonfree FFmpeg build.' >&2
  exit 1
fi
cp COPYING.LGPLv2.1 LICENSE.md "$LICENSES/"
cp "$ARCHIVE" "$LICENSES/"
cp "$ROOT_DIR/Packaging/build_ffmpeg.sh" "$LICENSES/BUILD-RECIPE.sh"
printf 'Source: %s\nSHA256: %s\nUnmodified official FFmpeg source; build recipe and complete source archive included.\n' \
  "$FFMPEG_URL" "$FFMPEG_SHA256" > "$LICENSES/SOURCE.txt"
echo "LGPL FFmpeg/ffprobe ready: $DEST"
