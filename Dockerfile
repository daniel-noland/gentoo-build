# syntax=docker/dockerfile:1.3.0-labs
ARG upstream_snapshot="20220401"
ARG bootstrap_step0="gentoo/stage3:musl-${upstream_snapshot}"
ARG build_niceness="15"
FROM $bootstrap_step0 as bootstrap_step1
ARG upstream_snapshot
ARG build_niceness

SHELL ["/bin/bash", "-euxETo", "pipefail", "-c"]

# Sync with timestamped "master" gentoo repo (we can't emerge anything without this)
# we use our upstream_snapshot arg to make sure we are getting exactly the same packages every time.
# NOTE: gentoo only seems to hold these snapshots for about a month.  If you might need to go back farther than that
# then we should most likely push the container after the emerge-webrsync to hold it in docker (or set up our own
# rsync mirror).
RUN \
emerge-webrsync --revert="${upstream_snapshot}"; \
:;

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
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
mv /usr/share/portage/config/repos.conf{,.orig}; \
touch /usr/share/portage/config/repos.conf; \
:;

# Make it fairly difficult to accidentally re-enable the official gentoo repo.
# (in case a dispatch-conf wants to overwrite it I expect it to fail here)
RUN \
--security=insecure \
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
emerge --depclean; \
:;

RUN \
--mount=type=tmpfs,target=/run \
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
emerge --depclean; \
:;

FROM bootstrap_step1 as bootstrap_step2
ARG build_niceness
SHELL ["/bin/bash", "-euxETo", "pipefail", "-c"]

COPY assets/bootstrap/2/ /

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
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
emerge --depclean; \
:;

# Compile llvm/clang with llvm/clang
RUN \
--mount=type=tmpfs,target=/run \
nice --adjustment="${build_niceness}" \
emerge \
  --jobs="$(nproc)" \
  --load-average="$(($(nproc) * 2))" \
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
emerge --depclean; \
:;

FROM bootstrap_step2 as bootstrap_step3
ARG build_niceness
SHELL ["/bin/bash", "-euxETo", "pipefail", "-c"]

COPY assets/bootstrap/3/ /

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
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
emerge --depclean; \
:;

FROM bootstrap_step3 as catalyst_install
SHELL ["/bin/bash", "-euxETo", "pipefail", "-c"]
COPY ./assets/catalyst/01_install/ /

# Sanity rebuild.  If this fails then something way downstream of it is basically sure to fail.
# It takes time here but it saves time overall in the end.
RUN \
--mount=type=tmpfs,target=/run \
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
emerge --depclean; \
:;

RUN \
--mount=type=tmpfs,target=/run \
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
emerge --depclean; \
:;

FROM catalyst_install as catalyst
SHELL ["/bin/bash", "-euxETo", "pipefail", "-c"]

COPY --from=bootstrap_step3 / /run/stage3

RUN \
mkdir --parent /var/tmp/catalyst/builds/musl; \
truncate --size=0 /run/stage3/usr/share/portage/config/repos.conf; \
mkdir --parent /run/stage3/etc/portage/repos.conf/; \
cp --archive /etc/portage/repos.conf/gentoo.conf /run/stage3/etc/portage/repos.conf/gentoo.conf; \
:;

RUN \
for binary in /run/stage3/usr/lib/llvm/13/bin/*; do \
  ln --symbolic --relative "${binary}" "/run/stage3/usr/bin/$(basename "${binary}")"; \
done; \
:;

RUN \
for library in /run/stage3/usr/lib/llvm/13/lib/*.so; do \
  if [[ ! -e "/run/stage3/usr/lib/$(basename "${library}")" ]]; then \
    ln --symbolic --relative "${library}" "/run/stage3/usr/lib/$(basename "${library}")"; \
  fi; \
done; \
:;

RUN \
rm /run/stage3/etc/portage/make.profile; \
cd /run/stage3/etc/portage/; \
ln -r -s ../../var/db/repos/gentoo/profiles/default/linux/amd64/17.0/musl/clang/ make.profile; \
:;

#COPY ./assets/catalyst/03_scratch/etc/portage/package.use/bootstrap /run/stage3/etc/portage/package.use
#COPY ./assets/catalyst/03_scratch/etc/portage/make.conf /run/stage3/etc/portage/make.conf

RUN \
mkdir --parent /var/tmp/catalyst/builds/musl/clang; \
tar \
  --create \
  --file /var/tmp/catalyst/builds/musl/clang/stage3-amd64-musl-clang.tar \
  --directory=/run/stage3 \
  . \
; \
:;

ARG _nothing_=48.0
ARG gentoo_branch="llvm{musl/clang}-rebase"

RUN \
rm --force --recursive /run/stage3/var/db/repos/gentoo; \
git clone \
  --depth 1 \
  --branch "${gentoo_branch}" \
  "https://github.com/daniel-noland/gentoo" \
  /run/stage3/var/db/repos/gentoo \
; \
:;

RUN \
mkdir --parent /var/tmp/catalyst/snapshots; \
cd /run/stage3/var/db/repos/; \
mksquashfs gentoo /var/tmp/catalyst/snapshots/gentoo-latest.sqfs; \
:;

#COPY assets/catalyst/02_run/etc/ /etc/

COPY assets/catalyst/02_run/specs/stage1.spec /specs/
COPY ./assets/catalyst/02_run/etc/catalyst/ /etc/catalyst/

RUN \
--security=insecure \
nice --adjustment="${build_niceness}" \
catalyst --file /specs/stage1.spec; \
:;

COPY assets/catalyst/02_run/specs/stage2.spec /specs/

RUN \
--security=insecure \
nice --adjustment="${build_niceness}" \
catalyst --file /specs/stage2.spec; \
:;

COPY assets/catalyst/02_run/specs/stage3.spec /specs/

RUN \
--security=insecure \
nice --adjustment="${build_niceness}" \
catalyst --file /specs/stage3.spec; \
:;

#RUN \
#mkdir /out; \
#tar --extract --file /var/tmp/catalyst/builds/musl-clang/stage3-amd64-musl-clang-latest.tar.gz --directory=/out; \
#:;
#
#FROM scratch as re_emerge_world
#ARG build_niceness
#SHELL ["/bin/bash", "-euxETo", "pipefail", "-c"]
#
#COPY --from=catalyst /out /
#COPY --from=catalyst /run/stage3/var/db/repos/gentoo /var/db/repos/gentoo
#
#RUN \
#--mount=type=tmpfs,target=/run \
#nice --adjustment="${build_niceness}" \
#emerge \
#  --complete-graph \
#  --deep \
#  --jobs="$(nproc)" \
#  --load-average="$(($(nproc) * 2))" \
#  --newuse \
#  --update \
#  --verbose \
#  --with-bdeps=y \
#  @system \
#; \
#:;
#
#RUN \
#--mount=type=tmpfs,target=/run \
#nice --adjustment="${build_niceness}" \
#emerge \
#  --complete-graph \
#  --deep \
#  --jobs="$(nproc)" \
#  --load-average="$(($(nproc) * 2))" \
#  --newuse \
#  --update \
#  --verbose \
#  --with-bdeps=y \
#  @world \
#; \
#:;
#
#RUN \
#--mount=type=tmpfs,target=/run \
#nice --adjustment="${build_niceness}" \
#emerge \
#  --complete-graph \
#  --deep \
#  --emptytree \
#  --jobs="$(nproc)" \
#  --load-average="$(($(nproc) * 2))" \
#  --newuse \
#  --update \
#  --verbose \
#  --with-bdeps=y \
#  @world \
#; \
#:;
