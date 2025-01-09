#!/usr/bin/env bash

set -eo pipefail

function clone_or_update() {
    local repo_url=$1
    local repo_dir=$2
    if [ -d "$repo_dir" ]; then
        echo "Updating $repo_dir"
        pushd "$repo_dir"
        git fetch --prune
        popd
    else
        echo "Cloning $repo_dir"
        git clone --mirror "$repo_url" "$repo_dir"
    fi
}

MPV_VERSION="0.39.0"
LIBASS_VERSION="0.17.3"
LIBPLACEBO_VERSION="7.349.0"
FFMPEG_VERSION="7.1"

CI_DEPLOY_PLATFORM="${CI_DEPLOY_PLATFORM:-linux-x86_64}"

export ARCH=amd64
export PREFIX=x86_64-linux-gnu
if [[ "$CI_DEPLOY_PLATFORM" == "linux-arm" ]]; then
  export ARCH=armhf
  export PREFIX=arm-linux-gnueabihf
  export USERLAND_BUILDME="buildme"
  echo "Currently not supported"
  exit 1
elif [[ "$CI_DEPLOY_PLATFORM" == "linux-arm64" ]]; then
  export ARCH=arm64
  export ARCH_CUDA=sbsa
  export PREFIX=aarch64-linux-gnu
  export USERLAND_BUILDME="buildme --aarch64"
  echo "Currently not supported"
  exit 1
elif [[ "$CI_DEPLOY_PLATFORM" == "linux-ppc64le" ]]; then
  export ARCH=ppc64le
  export ARCH_CUDA=ppc64le
  export PREFIX=powerpc64le-linux-gnu
  echo "Currently not supported"
  exit 1
elif [[ "$CI_DEPLOY_PLATFORM" == "linux-x86" ]]; then
  export ARCH=i386
  export PREFIX=i686-linux-gnu
elif [[ "$CI_DEPLOY_PLATFORM" == "linux-x86_64" ]]; then
  export ARCH=amd64
  export ARCH_CUDA=x86_64
  export PREFIX=x86_64-linux-gnu
fi

source /etc/os-release
export CODENAME=$UBUNTU_CODENAME

sudo sed -ie '/Architectures: .*/d' /etc/apt/sources.list.d/ubuntu.sources
sudo sed -i ':a;N;$!ba;s/\nComponents:/\nArchitectures: amd64 i386\nComponents:/g' /etc/apt/sources.list.d/ubuntu.sources
if [[ "$ARCH" == "i386" ]]; then
  sudo dpkg --add-architecture $ARCH
  TOOLCHAIN="gcc-$PREFIX g++-$PREFIX gfortran-$PREFIX"
elif [[ ! "$ARCH" == "amd64" ]]; then
  echo "Adding $ARCH architecture"
  sudo dpkg --add-architecture $ARCH
  sudo rm /etc/apt/sources.list.d/ubuntu-ports.list || true
  sudo echo deb [arch=$ARCH] http://ports.ubuntu.com/ubuntu-ports $CODENAME main restricted universe multiverse | sudo tee -a /etc/apt/sources.list.d/ubuntu-ports.list
  sudo echo deb [arch=$ARCH] http://ports.ubuntu.com/ubuntu-ports $CODENAME-updates main restricted universe multiverse | sudo tee -a /etc/apt/sources.list.d/ubuntu-ports.list
  sudo echo deb [arch=$ARCH] http://ports.ubuntu.com/ubuntu-ports $CODENAME-backports main restricted universe multiverse | sudo tee -a /etc/apt/sources.list.d/ubuntu-ports.list
  sudo echo deb [arch=$ARCH] http://ports.ubuntu.com/ubuntu-ports $CODENAME-security main restricted universe multiverse | sudo tee -a /etc/apt/sources.list.d/ubuntu-ports.list
  TOOLCHAIN="gcc-$PREFIX g++-$PREFIX gfortran-$PREFIX linux-libc-dev-$ARCH-cross binutils-multiarch"
fi
echo "sources.list:"
cat /etc/apt/sources.list
for f in /etc/apt/sources.list.d/*.sources; do echo "$f:"; cat $f; done

sudo apt-get update
sudo apt-get -y install gcc-multilib g++-multilib gfortran-multilib
sudo apt-get -y install pkgconf ccache clang $TOOLCHAIN git file wget unzip tar bzip2 gzip patch autoconf-archive autogen automake cmake make libtool flex perl nasm ragel curl libcurl4-openssl-dev libssl-dev libffi-dev libbz2-dev zlib1g-dev rapidjson-dev


BUILD_DIR="$(pwd)/build/$CI_DEPLOY_PLATFORM"
OUTPUT_DIR="$BUILD_DIR/output"
rm -rf "$BUILD_DIR" || true
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

CROSS_FILE="$BUILD_DIR/meson-cross-$PREFIX.txt"

MESON_CROSS_ARGS=""
NATIVE_ARCH=$(dpkg --print-architecture)
if [ "$NATIVE_ARCH" != "$ARCH" ]; then
    cat <<EOF > "$CROSS_FILE"
[binaries]
c = '$PREFIX-gcc'
cpp = '$PREFIX-g++'
ar = '$PREFIX-ar'
strip = '$PREFIX-strip'
pkgconfig = '$PREFIX-pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'x86'
cpu = 'x86_64'
endian = 'little'
EOF
    MESON_CROSS_ARGS="--cross-file $CROSS_FILE"
fi

sudo apt-get update -y
sudo apt-get install -y software-properties-common git

wget -qO - https://packages.lunarg.com/lunarg-signing-key-pub.asc | sudo apt-key add -
sudo wget -qO /etc/apt/sources.list.d/lunarg-vulkan-1.3.296-noble.list https://packages.lunarg.com/vulkan/1.3.296/lunarg-vulkan-1.3.296-noble.list

sudo apt-get update
sudo apt-get install -y python3:$NATIVE_ARCH python3-pip python3-setuptools python3-wheel ninja-build cmake nasm
sudo apt-get install -y liblcms-dev:$ARCH libunwind-dev:$ARCH libjpeg-dev:$ARCH libpng-dev:$ARCH \
    libtiff-dev:$ARCH libwebp-dev:$ARCH libfreetype-dev:$ARCH libfribidi-dev:$ARCH libharfbuzz-dev:$ARCH \
    libfontconfig1-dev:$ARCH libopenal-dev:$ARCH libpulse-dev:$ARCH libvdpau-dev:$ARCH libva-dev:$ARCH \
    libvdpau-dev:$ARCH libegl1-mesa-dev:$ARCH libgles2-mesa-dev:$ARCH libgbm-dev:$ARCH libdrm-dev:$ARCH \
    libx11-dev:$ARCH libxext-dev:$ARCH libxrandr-dev:$ARCH libxinerama-dev:$ARCH libxcursor-dev:$ARCH \
    libxi-dev:$ARCH libxv-dev:$ARCH libxss-dev:$ARCH libxtst-dev:$ARCH libxkbcommon-dev:$ARCH \
    libwayland-dev:$ARCH libwayland-egl-backend-dev:$ARCH libgl1-mesa-dev:$ARCH libglu1-mesa-dev:$ARCH \
    libgles1:$ARCH libgles2:$ARCH libegl1:$ARCH libegl1-mesa-dev:$ARCH libegl1-mesa-dev:$ARCH \
    libegl1-mesa-dev:$ARCH libbluray-dev:$ARCH libsrt-openssl-dev:$ARCH opencl-headers:$ARCH \
    libgraphite2-dev:$ARCH libvulkan-dev:$ARCH libva-drm2:$ARCH libva-glx2:$ARCH libva-x11-2:$ARCH \
    libva-wayland2:$ARCH libwayland-client0:$ARCH libwayland-cursor0:$ARCH libwayland-egl1:$ARCH \
    libx11-xcb1:$ARCH libxcb-dri2-0:$ARCH libxcb-dri3-0:$ARCH libxcb-glx0:$ARCH \
    libpipewire-0.3-dev:$ARCH libarchive-dev:$ARCH wayland-protocols:$ARCH \
    libxpresent-dev:$ARCH libvulkan1:$ARCH libvulkan-dev:$ARCH
sudo pip3 install meson --break-system-packages

LIBASS_REPO_DIR="$(pwd)/.repos/libass"
LIBPLACEBO_REPO_DIR="$(pwd)/.repos/libplacebo"
MPV_REPO_DIR="$(pwd)/.repos/mpv"
FFMPEG_REPO_DIR="$(pwd)/.repos/ffmpeg"

mkdir -p .repos
clone_or_update "https://github.com/libass/libass" "$LIBASS_REPO_DIR"
clone_or_update "https://github.com/haasn/libplacebo" "$LIBPLACEBO_REPO_DIR"
clone_or_update "https://github.com/mpv-player/mpv.git" "$MPV_REPO_DIR"
clone_or_update "https://gitlab.freedesktop.org/gstreamer/meson-ports/ffmpeg.git" "$FFMPEG_REPO_DIR"

# Build
pushd "$BUILD_DIR"
git clone "$MPV_REPO_DIR" mpv
pushd mpv
git checkout "v$MPV_VERSION"
mkdir -p subprojects

cat <<EOF > subprojects/libass.wrap
[wrap-git]
revision = $LIBASS_VERSION
url = $LIBASS_REPO_DIR
depth = 1
EOF

cat <<EOF > subprojects/libplacebo.wrap
[wrap-git]
url = $LIBPLACEBO_REPO_DIR
revision = v$LIBPLACEBO_VERSION
depth = 1
clone-recursive = true
EOF

cat <<EOF > subprojects/ffmpeg.wrap
[wrap-git]
url = $FFMPEG_REPO_DIR
revision = meson-$FFMPEG_VERSION
depth = 1
[provide]
libavcodec = libavcodec_dep
libavdevice = libavdevice_dep
libavfilter = libavfilter_dep
libavformat = libavformat_dep
libavutil = libavutil_dep
libswresample = libswresample_dep
libswscale = libswscale_dep
EOF

meson setup build -Dlibmpv=true -Ddefault_library=static -Dlibass:default_library=static -Dffmpeg:default_library=static \
   -Dwayland=disabled -Dx11=disabled -Dlibarchive=disabled -Dlibplacebo:vk-proc-addr=disabled -Dprefix=/ $MESON_CROSS_ARGS
ninja -C build libmpv.a subprojects/libass/libass/libass.a subprojects/libplacebo/src/libplacebo.a

# Copy the static libraries to the output directory
DESTDIR="$OUTPUT_DIR" meson install -C build
popd; popd

pushd "$OUTPUT_DIR"
if [ -d lib/$PREFIX ]; then
    mv lib/$PREFIX/* lib/
    rmdir lib/$PREFIX
fi
rm lib/{libavcodec,libavdevice,libavfilter,libavformat,libavutil,libpostproc,libswresample,libswscale}.a
rm lib/pkgconfig/{libavcodec,libavdevice,libavfilter,libavformat,libavutil,libpostproc,libswresample,libswscale}.pc
rm -r include/{libavcodec,libavdevice,libavfilter,libavformat,libavutil,libpostproc,libswresample,libswscale}/
rm -r bin/
rm -r etc/
rm -r share/
popd
