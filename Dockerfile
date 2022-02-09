# syntax=docker/dockerfile:1.3.0-labs
ARG upstream_snapshot="20220207"
ARG bootstrap_step0="gentoo/stage3:musl-${upstream_snapshot}"
ARG build_niceness="15"
FROM $bootstrap_step0 as bootstrap_step1
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

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
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

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
:;

COPY assets/bootstrap/1/ /

RUN rm --force --recursive /var/db/repos/gentoo

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
chattr +i /etc/portage/repos.conf/gentoo.conf; \
:;

# Remove any trace of the original gentoo repo from our cache (it is just wasting space at this point)
RUN rm --force --recursive /var/db/repos/gentoo

# Sync with the snapshot repo
RUN emaint sync --allrepos

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
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
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
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

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
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
--mount=type=tmpfs,target=/var/tmp/portage \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  clang \
  compiler-rt \
  libcxx \
  libcxxabi \
  lld \
  llvm \
  llvm-libunwind \
; \
:;

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
:;

RUN \
set -eux; \
emerge --depclean; \
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
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
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

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
:;

RUN \
set -eux; \
emerge --depclean; \
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
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
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

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
--mount=type=tmpfs,target=/var/tmp/portage \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
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
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
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

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
--mount=type=tmpfs,target=/var/tmp/portage \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
:;

RUN \
set -eux; \
emerge --depclean; \
:;

FROM bootstrap_step4_1 as catalyst_install
COPY ./assets/catalyst/01_install/ /

RUN \
--mount=type=tmpfs,target=/run \
--mount=type=tmpfs,target=/var/tmp/portage \
set -eux; \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  app-arch/pixz \
  dev-util/catalyst \
  sys-fs/squashfs-tools \
; \
:;

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
--mount=type=tmpfs,target=/var/tmp/portage \
set -eux; \
nice --adjustment="${build_niceness}" \
emerge \
  --complete-graph \
  --deep \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
  --newuse \
  --update \
  --verbose \
  --with-bdeps=y \
  @world \
; \
:;

RUN \
--mount=type=tmpfs,target=/run \
set -eux; \
emerge --depclean; \
:;

FROM catalyst_install as catalyst_stage1

COPY --from=bootstrap_step4_1 / /run/stage3

RUN \
set -eux; \
mkdir --parent /var/tmp/catalyst/builds/musl; \
truncate --size=0 /run/stage3/usr/share/portage/config/repos.conf; \
mkdir --parent /run/stage3/etc/portage/repos.conf/; \
cp --archive /etc/portage/repos.conf/gentoo.conf /run/stage3/etc/portage/repos.conf/gentoo.conf; \
:;

ARG gentoo_branch="llvm{musl}"

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
for library in /run/stage3/usr/lib/llvm/13/lib/*.so; do \
  if [[ ! -e "/run/stage3/usr/lib/$(basename $(readlink "${library}"))" ]]; then \
    ln --symbolic --relative "${library}" "/run/stage3/usr/lib/$(basename $(readlink "${library}"))"; \
  fi; \
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

COPY assets/catalyst/02_run/etc/ /etc/

COPY assets/catalyst/02_run/specs/stage1.spec /specs/

RUN \
--security=insecure \
--mount=type=tmpfs,target=/run \
set -eux; \
nice --adjustment="${build_niceness}" \
catalyst --file /specs/stage1.spec; \
:;

COPY assets/catalyst/02_run/specs/stage2.spec /specs/

RUN \
--security=insecure \
set -eux; \
nice --adjustment="${build_niceness}" \
catalyst --file /specs/stage2.spec; \
:;

COPY assets/catalyst/02_run/specs/stage3.spec /specs/

RUN \
--security=insecure \
set -eux; \
nice --adjustment="${build_niceness}" \
catalyst --file /specs/stage3.spec; \
:;
