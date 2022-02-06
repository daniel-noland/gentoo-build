# syntax=docker/dockerfile:1.3.0-labs
ARG upstream_snapshot="20220204"
ARG bootstrap_step0="gentoo/stage3:musl-${upstream_snapshot}"
ARG build_niceness="15"
FROM $bootstrap_step0 as bootstrap_step0
ARG upstream_snapshot
ARG build_niceness

# Sync with timestamped "master" gentoo repo (we can't emerge anything without this)
# we use our upstream_snapshot arg to make sure we are getting exactly the same packages every time.
# NOTE: gentoo only seems to hold these snapshots for about a month.  If you might need to go back farther than that
# then we should most likely push the container after the emerge-webrsync to hold it in docker (or set up our own
# rsync mirror).
RUN \
set -eux; \
emerge-webrsync --revert="${upstream_snapshot}"; \
:;

# Copy in stage 0 config files
COPY ./assets/bootstrap/0/ /

# Rebuild the world as a sanity check.
# If we can't do this then the whole rest of the process is doomed anyway.
RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --deep \
  --emptytree \
  --newuse \
  --update \
  --verbose \
  @world \
; \
:;

RUN \
set -eux; \
emerge --depclean; \
:;

RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --verbose \
  --newuse \
  --deep \
  app-eselect/eselect-repository \
  dev-vcs/git \
; \
:;

RUN \
set -eux; \
emerge --depclean; \
:;

FROM bootstrap_step0 as bootstrap_step1
ARG build_niceness

COPY ./assets/bootstrap/1/ /

# Remove the official gentoo repo (we want the snapshot instead)
RUN \
set -eux; \
mv /usr/share/portage/config/repos.conf{,.orig}; \
touch /usr/share/portage/config/repos.conf; \
:;

# Make it fairly difficult to accidentally re-enable the official gentoo repo.
# (in case a dispatch-conf wants to overwrite it I expect it to fail here)
RUN \
--security=insecure \
set -eux; \
chattr +i /usr/share/portage/config/repos.conf; \
chattr +i /etc/portage/repos.conf; \
chattr +i /etc/portage/repos.conf/dnoland.conf; \
:;

# Remove any trace of the original gentoo repo from our cache (it is just wasting space at this point)
RUN rm --force --recursive /var/db/repos/gentoo

# Sync with the snapshot repo
RUN emaint sync --allrepos

RUN \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  sys-devel/clang \
  sys-devel/lld \
  sys-devel/llvm \
  sys-libs/compiler-rt \
  sys-libs/llvm-libunwind \
; \
:;

RUN \
set -eux; \
emerge --depclean; \
:;

FROM bootstrap_step1 as bootstrap_step2
ARG build_niceness

COPY assets/bootstrap/2/ /

# Compile llvm/clang with llvm/clang
RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
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
ARG build_niceness

COPY assets/bootstrap/3/ /

# Re-compile optimized llvm/clang with llvm/clang
RUN \
--mount=type=tmpfs,target=/run \
--mount=type=tmpfs,target=/var/tmp/portage \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --newuse \
  --update \
  --with-bdeps=y \
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

FROM bootstrap_step3 as bootstrap_step4_0
ARG build_niceness

COPY assets/bootstrap/4/ /

# Re-compile all system packages with optimized llvm/clang.
RUN \
--mount=type=tmpfs,target=/run \
--mount=type=tmpfs,target=/var/tmp/portage \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --emptytree \
  --newuse \
  --update \
  --with-bdeps=y \
  @world \
; \
:;

RUN \
set -eux; \
emerge --depclean; \
:;

FROM bootstrap_step4_0 as bootstrap_step4_1
ARG build_niceness

# Re-compile all system packages with optimized llvm/clang (again).
# We do this twice to facilitate LTO / static linking.
# Perviously satisfied bootstrap dep libs are available statically after the first rebuild.
# Those libs are then candidates for static linking (and better LTO) in the second build.
RUN \
--mount=type=tmpfs,target=/run \
--mount=type=tmpfs,target=/var/tmp/portage \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --emptytree \
  --newuse \
  --update \
  --with-bdeps=y \
  @world \
; \
:;

RUN \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge --depclean; \
:;

FROM bootstrap_step4_1 as catalyst_install
COPY ./assets/catalyst-install/ /

RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
emerge \
  app-arch/pixz \
  dev-util/catalyst \
  sys-fs/squashfs-tools \
; \
:;

FROM catalyst_install as catalyst_stage1
RUN mkdir --parent /run/step1

COPY assets/catalyst/tmp/ /tmp/

#RUN \
#set -eux; \
#mkdir --parent /var/tmp/catalyst/builds/musl/; \
#rm --force --recursive /run/step1/var/db/repos/gentoo; \
#rm --force --recursive /run/step1/var/cache/distfiles; \
#ln --relative --symbolic /run/step1/var/db/repos/dnoland /run/step1/var/db/repos/gentoo; \
#git clone \
#  --depth 1 \
#  --branch 'v0.1/timestamp/2022-01-30T19.28.43+00.00' \
#  'https://github.com/daniel-noland/gentoo' \
#  /run/step1/var/db/repos/dnoland \
#; \
#tar --create --gz --file /var/tmp/catalyst/builds/musl/stage3-amd64-musl.tar.gz --directory=/run/step1 .; \
#:;

COPY --from=bootstrap_step4_1 / /run/stage3

RUN \
set -eux; \
mkdir --parent /var/tmp/catalyst/builds/musl; \
truncate --size=0 /run/stage3/usr/share/portage/config/repos.conf; \
mkdir --parent /run/stage3/etc/portage/repos.conf/; \
cp --archive /tmp/catalyst/stage1/etc/portage/repos.conf/dnoland.conf /run/stage3/etc/portage/repos.conf/dnoland.conf; \
:;

ARG gentoo_branch="profile{musl.clang}"

ENV _nothing=1
RUN \
set -eux; \
rm --force --recursive /run/stage3/var/db/repos/gentoo; \
git clone \
  --depth 1 \
  --branch "${gentoo_branch}" \
  "https://github.com/daniel-noland/gentoo" \
  /run/stage3/var/db/repos/gentoo \
; \
:;

RUN \
set -eux; \
for binary in /run/stage3/usr/lib/llvm/13/bin/*; do \
  ln --symbolic --relative "${binary}" "/run/stage3/usr/bin/$(basename "${binary}")"; \
done; \
:;

RUN \
set -eux; \
mkdir --parent /var/tmp/catalyst/builds/musl/clang; \
tar \
  --gz \
  --create \
  --file /var/tmp/catalyst/builds/musl/clang/stage3-amd64-musl-clang.tar.gz \
  --directory=/run/stage3 \
  . \
; \
:;

RUN \
set -eux; \
mkdir --parent /var/tmp/catalyst/snapshots; \
cd /run/stage3/var/db/repos/; \
mksquashfs gentoo /var/tmp/catalyst/snapshots/gentoo-latest.sqfs; \
:;

COPY assets/catalyst/etc/ /etc/

COPY assets/catalyst/specs/stage1.spec /specs/

#RUN \
#--security=insecure \
#--mount=type=tmpfs,target=/run \
#set -eux; \
#nice --adjustment="${build_niceness}" \
#catalyst --file /specs/stage1.spec; \
#:;

#COPY assets/catalyst/specs/stage2.spec /specs/
#
#RUN \
#--security=insecure \
#set -eux; \
#nice --adjustment="${build_niceness}" \
#catalyst --file /specs/stage2.spec; \
#:;
#
#COPY assets/catalyst/specs/stage3.spec /specs/
#
#RUN \
#--security=insecure \
#set -eux; \
#nice --adjustment="${build_niceness}" \
#catalyst --file /specs/stage3.spec; \
#:;
#
##
##RUN \
##--mount=type=tmpfs,target=/run \
##set -eux; \
##mkdir --parent /var/tmp/catalyst/snapshots; \
##git clone \
##  --depth 1 \
##  --branch 'v0.1/timestamp/2022-01-30T19.28.43+00.00' \
##  'https://github.com/daniel-noland/gentoo' \
##  /run/dnoland \
##; \
##mksquashfs /run/dnoland /var/tmp/catalyst/snapshots/gentoo-latest.sqfs; \
##:;
#
##RUN \
##--mount=type=tmpfs,target=/run \
##set -eux; \
##mkdir --parent /var/tmp/catalyst/snapshots; \
##wget --output-document="/run/portage-snapshot.tar.xz" \
##  "https://distfiles.gentoo.org/snapshots/gentoo-latest.tar.xz"; \
##mkdir --parent /run/squashfs; \
##tar --extract --file /run/portage-snapshot.tar.xz --strip-components=1 --directory=/run/squashfs; \
##mksquashfs /run/squashfs /var/tmp/catalyst/snapshots/gentoo-latest.sqfs; \
##:;
#
##COPY assets/catalyst/ /
#
##RUN \
##set -eux; \
##wget --output-document=- \
##  "http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-musl/stage3-amd64-musl-20220130T170547Z.tar.xz"; \
##  mksquashfs -
##
##:;
#
#
##RUN \
##--security=insecure \
##set -eux; \
##catalyst --snapshot 20220129; \
##:;
#
### Rebuild the world as a sanity check.
### If we can't do this then the whole rest of the process is doomed anyway.
##RUN \
##--mount=type=tmpfs,target=/run \
##set -eux; \
##nice --adjustment="${build_niceness}" \
##emerge \
##  --deep \
##  --emptytree \
##  --newuse \
##  --update \
##  --verbose \
##  @world \
##; \
##:;
##
##RUN \
##set -eux; \
##emerge --depclean; \
##:;
##
### Compile llvm/clang with gcc
##RUN \
##--mount=type=tmpfs,target=/run \
##set -eux; \
##nice --adjustment="${build_niceness}" \
##emerge \
##  clang \
##  compiler-rt \
##  lld \
##  llvm \
##  llvm-libunwind \
##; \
##:;
##
##FROM bootstrap_step5 as repo_step1
##ARG build_niceness
##
##COPY ./assets/dpdk/00-libnl/ /
##
##RUN \
##--mount=type=tmpfs,target=/run \
##set -eux; \
##nice --adjustment="${build_niceness}" \
##emerge \
##  --verbose \
##  --newuse \
##  --deep \
##  '=dev-util/catalyst-9999' \
##  app-eselect/eselect-repository \
##  app-portage/repoman \
##  dev-vcs/git \
##; \
##:;
##
##
###COPY ./assets/dpdk/00-libnl/ /
###RUN \
###--security=insecure \
###set -eux; \
###nice --adjustment="${build_niceness}" \
###emerge \
###  --verbose \
###  --newuse \
###  dev-libs/libnl \
###; \
###:;
##
###RUN \
###set -eux; \
###touch /etc/portage/repos.conf; \
###eselect repository create dpdk; \
###:;
##
##
###ENV RDMA_CORE_VERSION="v38.1"
###ENV ___TRY="1"
###ENV RDMA_CORE_VERSION="fix-musl-build"
##
###RUN \
###set -eux; \
###mkdir -p /tmp/build; \
###cd /tmp/build; \
###git clone --depth 1 --branch ${RDMA_CORE_VERSION} "https://github.com/daniel-noland/rdma-core" rdma-core; \
###:;
###
###
###
###RUN \
###--mount=type=bind,source=./rdma-core,target=/tmp/build/rdma-core,readwrite \
###set -eux; \
###cd /tmp/build/rdma-core; \
###mkdir build; \
###cd build; \
###PATH="/usr/lib/llvm/13/bin/:${PATH}" \
###CC="clang" \
###CXX="clang++" \
###AR="llvm-ar" \
###NM="llvm-nm" \
###RANLIB="llvm-ranlib" \
###LD="ld.lld" \
###CFLAGS="-O3 -march=native -pipe -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -flto=thin" \
###LDFLAGS="-Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -fuse-ld=lld" \
###cmake \
###  -DCMAKE_C_COMPILER=clang \
###  -DCMAKE_BUILD_TYPE=Release \
###  -DCMAKE_INSTALL_BINDIR=/usr/local/bin \
###  -DCMAKE_INSTALL_INCLUDEDIR=/usr/local/include \
###  -DCMAKE_INSTALL_LIBDIR=/usr/local/lib \
###  -DCMAKE_INSTALL_PREFIX=/usr/local \
###  -DCMAKE_INSTALL_SBINDIR=/usr/local/bin \
###  -DCMAKE_INSTALL_SYSCONFDIR=/usr/local/etc \
###  -DENABLE_STATIC=1 \
###  -DENABLE_VALGRIND=0 \
###  -DNO_MAN_PAGES=1 \
###  -GNinja \
###  .. \
###; \
###ninja; \
###ninja install; \
###:;
###
###
###ENV DPDK_VERSION="v21.11-clang-lto"
###
###RUN \
###set -eux; \
###mkdir /tmp/build/dpdk; \
###cd /tmp/build/dpdk; \
###git clone --branch "${DPDK_VERSION}" --depth 1 "https://github.com/daniel-noland/dpdk" "dpdk-${DPDK_VERSION}"; \
###:;
####RUN mkdir -p /tmp/build/dpdk \
#### && wget -qO- https://fast.dpdk.org/rel/dpdk-${DPDK_VERSION}.tar.xz \
####  | tar xJf - -C /tmp/build/dpdk
###
###COPY ./dpdk /tmp/build/dpdk/dpdk-${DPDK_VERSION}
###
###ENV DPDK_DISABLED_DRIVERS=net/ark,net/atlantic,net/avp,net/axgbe,net/bnx2x,net/bnxt,net/cxgbe,net/dpaa,net/dpaa2,net/enetc,net/enic,net/fm10k,net/hinic,net/hns3,net/iavf,net/igc,net/liquidio,net/netvsc,net/nfp,net/octeontx,net/octeontx2,net/pfe,net/qede,net/sfc,net/softnic,net/thunderx,net/txgbe,net/vmxnet3,common/dpaax,common/octeontx,common/octeontx2,common/sfc_efx,event/dlb,event/dlb2,baseband/*,net/mlx4
###
#### TODO: turn these into proper patch files and use git to apply them.  sed hacks are just here to get off the ground
####       quickly.
#### This include line is missing for musl in the stock dpdk build
###RUN sed -i '8i#include <fcntl.h>' /tmp/build/dpdk/dpdk-${DPDK_VERSION}/lib/eal/unix/eal_file.c
###RUN sed -i 's/^typedef cpu_set_t/typedef struct cpu_set_t/' /tmp/build/dpdk/dpdk-${DPDK_VERSION}/lib/eal/linux/include/rte_os.h;
###RUN sed -i 's/^#define RTE_BACKTRACE.*/#undef RTE_BACKTRACE/' /tmp/build/dpdk/dpdk-${DPDK_VERSION}/config/rte_config.h
###
###RUN \
###--security=insecure \
###set -eux; \
###nice --adjustment="${build_niceness}" \
###emerge \
###  --verbose \
###  --newuse \
###  dev-python/pyelftools \
###  sys-libs/queue-standalone \
###; \
###:;
###
###RUN \
###set -eux; \
###cd /tmp/build; \
###git clone --depth 1 --branch "v20180201" "https://github.com/resslinux/libexecinfo.git"; \
###cd libexecinfo; \
###PATH="/usr/lib/llvm/13/bin/:${PATH}" \
###CC="clang" \
###CXX="clang++" \
###AR="llvm-ar" \
###NM="llvm-nm" \
###RANLIB="llvm-ranlib" \
###LD="ld.lld" \
###CFLAGS="-O3 -march=native -pipe -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -flto=thin" \
###LDFLAGS="-Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -fuse-ld=lld" \
###make --jobs="$(nproc)"; \
###make install; \
###:;
##
###ARG LINK_TIME_OPTIMIZATION=true
###RUN \
####--mount=type=bind,source=./dpdk,target=/tmp/build/dpdk/dpdk-21.11,readwrite \
###cd /tmp/build/dpdk/dpdk-${DPDK_VERSION} \
### && for p in /usr/lib/llvm/13/bin/*; do ln -s $p /usr/local/bin; done \
### && \
###DPDK_DISABLED_DRIVERS="net/ark,net/atlantic,net/avp,net/axgbe,net/bnx2x,net/bnxt,net/cxgbe,net/dpaa,net/dpaa2,net/enetc,net/enic,net/fm10k,net/hinic,net/hns3,net/iavf,net/igc,net/liquidio,net/netvsc,net/nfp,net/octeontx,net/octeontx2,net/pfe,net/qede,net/sfc,net/softnic,net/thunderx,net/txgbe,net/vmxnet3,common/dpaax,common/octeontx,common/octeontx2,common/sfc_efx,event/dlb,event/dlb2,baseband/*,net/mlx4" \
###LINK_TIME_OPTIMIZATION="true" \
###PATH="/usr/lib/llvm/13/bin/:${PATH}" \
###CC="clang" \
###CXX="clang++" \
###AR="llvm-ar" \
###NM="llvm-nm" \
###RANLIB="llvm-ranlib" \
###LD="ld.lld" \
###CFLAGS="-O3 -march=native -pipe -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -flto=thin" \
###LDFLAGS="-Wl,-O2 -Wl,--as-needed -Wl,-z,relro,-z,now -fuse-ld=lld -Wl,--thinlto-jobs=6" \
### meson \
###  --buildtype=release \
###  -Ddefault_library=static \
###  -Db_lto="${LINK_TIME_OPTIMIZATION}" \
###  -Ddisable_drivers="${DPDK_DISABLED_DRIVERS}" \
###  -Denable_docs=false \
###  -Denable_trace_fp=false \
###  -Dmax_lcores=64 \
###  -Dmax_numa_nodes=2 \
###  build \
###&& \
###cd /tmp/build/dpdk/dpdk-${DPDK_VERSION}/build \
###&& ninja \
###&& ninja install
##
###RUN cd /tmp/build/dpdk/dpdk-${DPDK_VERSION}/build \
### && ninja install
