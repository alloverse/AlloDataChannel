#!/usr/bin/env bash
set -euo pipefail

########################################
# Settings
########################################
SRC_DIR=${SRC_DIR:-libdatachannel}
MACOS_DEPLOY_TARGET=13.0
LINUX_IMAGE=${LINUX_IMAGE:-debian:bookworm}   # any recent distro works
OUTPUT_DIR=Binaries
XC_NAME=libdatachannel.xcframework
########################################

# 1. Sanity checks
echo "📋  Checking prerequisites..."
command -v cmake >/dev/null       || { echo "cmake not found"; exit 1; }
command -v xcodebuild >/dev/null  || { echo "xcodebuild not found"; exit 1; }
command -v docker >/dev/null      || { echo "docker not found"; exit 1; }

# 2. Make sure submodules are there (per BUILDING.md)  [oai_citation:1‡GitHub](https://raw.githubusercontent.com/paullouisageneau/libdatachannel/master/BUILDING.md)
echo "🚚  Checking out submodules..."
git -C "$SRC_DIR" submodule update --init --recursive --depth 1

mkdir -p build

########################################
# 3. Build macOS arm64 static slice
########################################
echo
echo "🔨🖥️  Building Mac slice"
MAC_BUILD=build/macos
cmake -S "$SRC_DIR" -B "$MAC_BUILD" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_DEPLOY_TARGET \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DUSE_GNUTLS=0 -DUSE_NICE=0

(cd $MAC_BUILD && make -j4 )

########################################
# 4. Build Linux x86-64 static slice in Docker
########################################
echo
echo "🔨👾 Building Linux slice"

LINUX_BUILD=build/linux
docker run --rm -t \
  -v "$(pwd)":/work -w /work \
  $LINUX_IMAGE bash -c "
    apt-get update -qq &&
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends build-essential cmake ninja-build git pkg-config libssl-dev &&
    cmake -S $SRC_DIR -B $LINUX_BUILD \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DUSE_GNUTLS=0 -DUSE_NICE=0 &&
    (cd $LINUX_BUILD && make -j4 )
  "

########################################
# 5. Assemble XCFramework (macOS slice)
########################################
echo
echo "📦🖥️  Assembling XCFramework"

rm -rf "$OUTPUT_DIR/$XC_NAME"
mkdir -p "$OUTPUT_DIR"

xcodebuild -create-xcframework \
  -library "$MAC_BUILD/libdatachannel.a" \
  -headers "$SRC_DIR/include" \
  -output "$OUTPUT_DIR/$XC_NAME"

########################################
# 6. Stash Linux artefacts alongside
########################################
echo
echo "📦👾 Assembling artifact bundle"

ARTIFACTBUNDLE="$OUTPUT_DIR/libdatachannel.artifactbundle"
mkdir -p "$ARTIFACTBUNDLE/include"
cp "$LINUX_BUILD/libdatachannel.a" "$ARTIFACTBUNDLE/libdatachannel.a"
cp -R "$SRC_DIR/include/" "$ARTIFACTBUNDLE/include/"
cat > "$ARTIFACTBUNDLE/info.json" <<JSON
{
"schemaVersion": "1.0",
"artifacts": {
"libdatachannel": { "type": "static-library" }
}
}
JSON

echo "✅  Done"
