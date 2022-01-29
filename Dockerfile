# syntax=docker/dockerfile:1.3-labs
ARG bootstrap_step1=gentoo/stage3:musl-20220118
FROM $bootstrap_step1 as bootstrap_step1

RUN emerge-webrsync

RUN rm --force --recursive /etc/portage/package.use

COPY assets/bootstrap/1/ /

# Compile llvm/clang with gcc
RUN \
set -eux; \
nice --adjustment=19 \
emerge \
  clang \
  compiler-rt \
  lld \
  llvm \
  llvm-libunwind \
; \
:;

FROM bootstrap_step1 as bootstrap_step2

COPY assets/bootstrap/2/ /

# Compile llvm/clang with llvm/clang
RUN \
set -eux; \
nice --adjustment=19 \
emerge \
  clang \
  compiler-rt \
  libcxx \
  libcxxabi \
  lld \
  llvm \
  llvm-libunwind \
  z3 \
; \
:;

FROM bootstrap_step2 as bootstrap_step3

COPY assets/bootstrap/3/ /

# Re-compile optimized llvm/clang with llvm/clang
RUN \
set -eux; \
nice --adjustment=19 \
emerge \
  --newuse \
  --update \
  clang \
  compiler-rt \
  libcxx \
  libcxxabi \
  lld \
  llvm \
  llvm-libunwind \
; \
:;

FROM bootstrap_step3 as bootstrap_step4

COPY assets/bootstrap/4/ /

# Re-compile all system packages with optimized llvm/clang.
RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge \
  --deep \
  --emptytree \
  --newuse \
  --update \
  @world \
; \
:;

FROM bootstrap_step4 as bootstrap_step5

RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge --depclean; \
:;

# Compile zstd compression so we can package up our final builds (in case it somehow wasn't already installed)
RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge \
  app-arch/zstd \
; \
:;

# Re-compile all system packages with optimized llvm/clang (again).
# We do this twice to facilitate LTO / static linking.
# Perviously satisfied bootstrap dep libs are available statically after the first rebuild.
# Those libs are then candidates for static linking (and better LTO) in the second build.
# God willing, we should now be able to produce pre-compiled binaries of all our work :)
RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge \
  --deep \
  --emptytree \
  --newuse \
  --update \
  @world \
; \
:;

RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge --depclean; \
:;

FROM bootstrap_step5 as repo_step1

RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge \
  --verbose \
  --newuse \
  --deep \
  app-eselect/eselect-repository \
; \
:;

RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge \
  --verbose \
  --newuse \
  dev-vcs/git \
; \
:;

RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge \
  --verbose \
  --newuse \
  app-portage/repoman \
; \
:;

COPY ./assets/dpdk/00-libnl/ /
RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge \
  --verbose \
  --newuse \
  dev-libs/libnl \
; \
:;

RUN \
set -eux; \
touch /etc/portage/repos.conf; \
eselect repository create dpdk; \
:;


#ENV RDMA_CORE_VERSION="v38.1"
ENV ___TRY="1"
ENV RDMA_CORE_VERSION="fix-musl-build"

#RUN \
#set -eux; \
#mkdir -p /tmp/build; \
#cd /tmp/build; \
#git clone --depth 1 --branch ${RDMA_CORE_VERSION} "https://github.com/daniel-noland/rdma-core" rdma-core; \
#:;
#
#
#
RUN \
--mount=type=bind,source=./rdma-core,target=/tmp/build/rdma-core,readwrite \
set -eux; \
cd /tmp/build/rdma-core; \
mkdir build; \
cd build; \
PATH="/usr/lib/llvm/13/bin/:${PATH}" \
CC="clang" \
CXX="clang++" \
AR="llvm-ar" \
NM="llvm-nm" \
RANLIB="llvm-ranlib" \
LD="ld.lld" \
CFLAGS="-O3 -march=native -pipe -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -flto=thin" \
LDFLAGS="-Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -fuse-ld=lld" \
cmake \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_BINDIR=/usr/local/bin \
  -DCMAKE_INSTALL_INCLUDEDIR=/usr/local/include \
  -DCMAKE_INSTALL_LIBDIR=/usr/local/lib \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_INSTALL_SBINDIR=/usr/local/bin \
  -DCMAKE_INSTALL_SYSCONFDIR=/usr/local/etc \
  -DENABLE_STATIC=1 \
  -DENABLE_VALGRIND=0 \
  -DNO_MAN_PAGES=1 \
  -GNinja \
  .. \
; \
ninja; \
ninja install; \
:;


ENV DPDK_VERSION="v21.11-clang-lto"

RUN \
set -eux; \
mkdir /tmp/build/dpdk; \
cd /tmp/build/dpdk; \
git clone --branch "${DPDK_VERSION}" --depth 1 "https://github.com/daniel-noland/dpdk" "dpdk-${DPDK_VERSION}"; \
:;
#RUN mkdir -p /tmp/build/dpdk \
# && wget -qO- https://fast.dpdk.org/rel/dpdk-${DPDK_VERSION}.tar.xz \
#  | tar xJf - -C /tmp/build/dpdk

COPY ./dpdk /tmp/build/dpdk/dpdk-${DPDK_VERSION}

ENV DPDK_DISABLED_DRIVERS=net/ark,net/atlantic,net/avp,net/axgbe,net/bnx2x,net/bnxt,net/cxgbe,net/dpaa,net/dpaa2,net/enetc,net/enic,net/fm10k,net/hinic,net/hns3,net/iavf,net/igc,net/liquidio,net/netvsc,net/nfp,net/octeontx,net/octeontx2,net/pfe,net/qede,net/sfc,net/softnic,net/thunderx,net/txgbe,net/vmxnet3,common/dpaax,common/octeontx,common/octeontx2,common/sfc_efx,event/dlb,event/dlb2,baseband/*,net/mlx4

# TODO: turn these into proper patch files and use git to apply them.  sed hacks are just here to get off the ground
#       quickly.
# This include line is missing for musl in the stock dpdk build
RUN sed -i '8i#include <fcntl.h>' /tmp/build/dpdk/dpdk-${DPDK_VERSION}/lib/eal/unix/eal_file.c
RUN sed -i 's/^typedef cpu_set_t/typedef struct cpu_set_t/' /tmp/build/dpdk/dpdk-${DPDK_VERSION}/lib/eal/linux/include/rte_os.h;
RUN sed -i 's/^#define RTE_BACKTRACE.*/#undef RTE_BACKTRACE/' /tmp/build/dpdk/dpdk-${DPDK_VERSION}/config/rte_config.h

RUN \
--security=insecure \
set -eux; \
nice --adjustment=19 \
emerge \
  --verbose \
  --newuse \
  dev-python/pyelftools \
  sys-libs/queue-standalone \
; \
:;


RUN \
set -eux; \
cd /tmp/build; \
git clone --depth 1 --branch "v20180201" "https://github.com/resslinux/libexecinfo.git"; \
cd libexecinfo; \
PATH="/usr/lib/llvm/13/bin/:${PATH}" \
CC="clang" \
CXX="clang++" \
AR="llvm-ar" \
NM="llvm-nm" \
RANLIB="llvm-ranlib" \
LD="ld.lld" \
CFLAGS="-O3 -march=native -pipe -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -flto=thin" \
LDFLAGS="-Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -fuse-ld=lld" \
make --jobs="$(nproc)"; \
make install; \
:;

ARG LINK_TIME_OPTIMIZATION=true
RUN \
#--mount=type=bind,source=./dpdk,target=/tmp/build/dpdk/dpdk-21.11,readwrite \
cd /tmp/build/dpdk/dpdk-${DPDK_VERSION} \
 && for p in /usr/lib/llvm/13/bin/*; do ln -s $p /usr/local/bin; done \
 && \
DPDK_DISABLED_DRIVERS="net/ark,net/atlantic,net/avp,net/axgbe,net/bnx2x,net/bnxt,net/cxgbe,net/dpaa,net/dpaa2,net/enetc,net/enic,net/fm10k,net/hinic,net/hns3,net/iavf,net/igc,net/liquidio,net/netvsc,net/nfp,net/octeontx,net/octeontx2,net/pfe,net/qede,net/sfc,net/softnic,net/thunderx,net/txgbe,net/vmxnet3,common/dpaax,common/octeontx,common/octeontx2,common/sfc_efx,event/dlb,event/dlb2,baseband/*,net/mlx4" \
LINK_TIME_OPTIMIZATION="true" \
PATH="/usr/lib/llvm/13/bin/:${PATH}" \
CC="clang" \
CXX="clang++" \
AR="llvm-ar" \
NM="llvm-nm" \
RANLIB="llvm-ranlib" \
LD="ld.lld" \
CFLAGS="-O3 -march=native -pipe -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -flto=thin" \
LDFLAGS="-Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -fuse-ld=lld -Wl,--thinlto-jobs=6" \
 meson \
  --buildtype=release \
  -Ddefault_library=static \
  -Db_lto="${LINK_TIME_OPTIMIZATION}" \
  -Ddisable_drivers="${DPDK_DISABLED_DRIVERS}" \
  -Denable_docs=false \
  -Denable_trace_fp=false \
  -Dmax_lcores=64 \
  -Dmax_numa_nodes=2 \
  build \
&& \
cd /tmp/build/dpdk/dpdk-${DPDK_VERSION}/build \
&& ninja \
&& ninja install

#RUN cd /tmp/build/dpdk/dpdk-${DPDK_VERSION}/build \
# && ninja install
