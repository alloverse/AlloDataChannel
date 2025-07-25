#!/usr/bin/env bash
set -euo pipefail

########################################
# Settings
########################################
SRC_DIR=${SRC_DIR:-libdatachannel}
export MACOSX_DEPLOYMENT_TARGET=13.0
LINUX_IMAGE=${LINUX_IMAGE:-debian:bookworm}   # any recent distro works
OUTPUT_DIR=Binaries
XC_NAME=datachannel.xcframework
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

cmake -B "$MAC_BUILD" -DCMAKE_BUILD_TYPE=Release

(cd $MAC_BUILD && make -j4 )

# join all the deps of libdatachannel into a single large static archive
libtool -static \
  -o $MAC_BUILD/libdatachannel.a \
     $MAC_BUILD/third_party/lib/*.a


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
    apt-get install -y --no-install-recommends build-essential cmake git pkg-config python3 &&
    cmake -B $LINUX_BUILD -DCMAKE_BUILD_TYPE=Release &&
    (cd $LINUX_BUILD && make -j4 ) &&
    ar -qc  $LINUX_BUILD/libdatachannel.a  \
        $LINUX_BUILD/third_party/lib/*.a &&
    ranlib $LINUX_BUILD/libdatachannel.a
  "

########################################
# 5. Assemble XCFramework (macOS slice)
########################################
echo
echo "📦🖥️  Assembling XCFramework..."

rm -rf "$OUTPUT_DIR/$XC_NAME"
mkdir -p "$OUTPUT_DIR"

cp datachannel.modulemap "$SRC_DIR/include/module.modulemap"

xcodebuild -create-xcframework \
  -library "$MAC_BUILD/libdatachannel.a" \
  -headers "$SRC_DIR/include" \
  -output "$OUTPUT_DIR/$XC_NAME"

rm "$SRC_DIR/include/module.modulemap"

########################################
# 6. Stash Linux artefacts alongside
########################################
echo
echo "📦👾 Packing Linux library..."

mkdir -p "$OUTPUT_DIR/$XC_NAME/linux-x86_64"
cp "$LINUX_BUILD/libdatachannel.a" \
   "$OUTPUT_DIR/$XC_NAME/linux-x86_64/libdatachannel-x86_64.a"
rsync -a "$SRC_DIR/include/" \
   "$OUTPUT_DIR/$XC_NAME/linux-x86_64/Headers/"

echo "✅  Done"
