FROM debian:sid-slim AS build-layer

ARG configuration=Release
ARG flags="-O3 -flto"

ENV SHELL=/bin/bash \
    CC="/usr/bin/ccache /usr/bin/clang-20" \
    CXX="/usr/bin/ccache /usr/bin/clang++-20" \
    LANG=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=0

WORKDIR /
SHELL ["/bin/bash", "-c"]

RUN \
    # Enable debug log during build
    set -x \
    # Enable contrib repository
    && sed -Ei 's/main/main contrib/;' /etc/apt/sources.list.d/debian.sources \
    # Enable LLVM repository as higher priority than Debian llvm
    && echo -e "Package: *\nPin: release sid\nPin-Priority: 600\n\nPackage: *\nPin: release llvm-toolchain\nPin-Priority: 800" > /etc/apt/preferences.d/docker \
    # Update system
    && apt-get update \
    && apt-get --option=Dpkg::Options::=--force-confdef -y upgrade \
    # Install libraries
    && apt-get --option=Dpkg::Options::=--force-confdef --no-install-recommends install -y libffi8 libpng16-16t64 libjpeg62-turbo libopus0 libopusfile0 libvorbis0a libvorbisenc2 libvorbisfile3 libogg0 libssl3t64 libfreetype6 zlib1g libstdc++6 libpcre2-32-0 libpcre2-posix3 libopenal1 lzma bzip2 ca-certificates curl libarchive-tools libuv1t64 \
    && export INSTALLED_PACKAGES=$(dpkg --get-selections | grep -v deinstall | cut -f 1) \
    # Install latest LLVM toolchain
    && echo "deb [trusted=yes] http://apt.llvm.org/unstable llvm-toolchain main" > /etc/apt/sources.list.d/llvm.list \
    && echo "deb [trusted=yes] https://deb.tohka.us sid main" > /etc/apt/sources.list.d/tohka.list \
    && apt-get update \
    # Install development tools
    && apt-get --no-install-recommends install -y clang-20 llvm-20 lld-20 ccache cmake ninja-build bison flex make libffi-dev libpng-dev libjpeg62-turbo-dev libopus-dev libopusfile-dev libvorbis-dev libogg-dev libssl-dev libfreetype-dev zlib1g-dev libeigen3-dev libpcre2-dev libopenal-dev liblzma-dev libbz2-dev linux-current-headers-all linux-current-headers-generic-$(dpkg --print-architecture) libbluetooth-dev rustc cargo dpkg-dev \
    # Setup compilation cache
    && ccache -s \
    # Setup clang as default compiler
    && rm -f /usr/bin/ld /usr/bin/cc \
    && ln -s $(which lld-20) /usr/bin/ld \
    && ln -s $(which clang-20) /usr/bin/cc \
    && ldconfig \
    # Install HAProxy (for SSL termination)
    && cd /tmp \
    && echo "Downloading HAProxy..." \
    && curl -SsL https://api.github.com/repos/haproxy/haproxy/zipball/master | bsdtar -x \
    && mv *haproxy* haproxy \
    && cd /tmp/haproxy \
    && make -j $(nproc) TARGET=linux-glibc USE_OPENSSL=1 USE_PCRE2_JIT=1 TARGET_CFLAGS="$flags" \
    && make install-bin \
    && ldconfig \
    && strip $(which haproxy) \
    && rm -rf /tmp/* \
    # Install Tauthon 2.8 (Python)
    && cd /tmp \
    && echo "Downloading Python..." \
    && curl -SsL https://github.com/naftaliharris/tauthon/archive/refs/heads/master.tar.gz | bsdtar -x \
    && mv *tauthon* python \ 
    && cd /tmp/python \
    && ./configure --prefix=/usr --enable-shared \
    && EXTRA_CFLAGS="$flags" LDFLAGS="-Wl,--strip-all" make -j$(nproc) \
    && EXTRA_CFLAGS="$flags" LDFLAGS="-Wl,--strip-all" make install \
    && cd /tmp \
    && rm -rf /tmp/* \
    # Setup Tauthon to Python symlinks
    && ln -s /usr/bin/tauthon2.8 /usr/bin/python2 \
    && ln -s /usr/bin/tauthon2.8 /usr/bin/python2.8 \
    && ln -s /usr/include/tauthon2.8 /usr/include/python \
    && ln -s /usr/include/tauthon2.8 /usr/include/python2.8 \
    && ln -s /usr/lib/libtauthon2.8.so /usr/lib/libpython2.8.so \
    && ln -s /usr/lib/tauthon2.8 /usr/lib/python2.8 \
    && ldconfig \
    # Install some Python dependencies
    && python2 -m ensurepip \
    && python2 -m pip install semidbm pyyaml pymongo pycryptodome jsonrpclib requests \
    # Build ODE
    && cd /tmp \
    && curl -SsL https://bitbucket.org/odedevs/ode/get/master.zip | bsdtar -x \
    && mv odedevs* ode \
    && cd /tmp/ode \
    && cmake -G"Ninja" -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" -DCMAKE_BUILD_TYPE="$configuration" -DCMAKE_INSTALL_PREFIX:PATH=/usr -DODE_WITH_DEMOS=OFF -DODE_WITH_TESTS=OFF . \
    && cmake --build . --target install --config $configuration --parallel $(nproc) \
    && rm -rf /tmp/* \
    # Build Panda3D
    && cd /tmp \
    && echo "Downloading Panda3D..." \
    && curl -SsL https://github.com/rocketprogrammer/panda3d/archive/refs/heads/py2.zip | bsdtar -x \
    && mv panda3d* p3d \
    && cd p3d \
    && python2 makepanda/makepanda.py --everything --no-egl --no-gles --no-gles2 --threads $(nproc) \
    && python2 makepanda/installpanda.py --prefix=/usr \
    && ldconfig \
    && cd / \
    && rm -rf /tmp/* \
    # Cleanup
    && ccache -s \
    && apt-get -y autoremove --purge $((comm -3 <(dpkg --get-selections | grep -v deinstall | cut -f 1 | sort) <(echo $INSTALLED_PACKAGES | xargs -n1 | sort)) | xargs) \
    && find /tmp -mindepth 1 -delete \
    && rm -rf /usr/include/ode /usr/cmake /var/lib/apt/lists/* /root/.cache /root/.cmake /var/cache