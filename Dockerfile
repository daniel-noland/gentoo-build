# syntax=docker/dockerfile:1.3-labs
ARG bootstrap_step1=gentoo/stage3:musl-20220114
FROM $bootstrap_step1 as bootstrap_step1

RUN emerge-webrsync

COPY assets/bootstrap-step1/ /

# TODO: remove --newuse --emptytree --verbose from this emerge
# Compile llvm/clang with gcc
RUN \
set -eux; \
emerge --newuse --emptytree --verbose \
  clang \
  compiler-rt \
  lld \
  llvm \
  llvm-libunwind \
  ; \
:;

FROM bootstrap_step1 as bootstrap_step2

COPY assets/bootstrap-step2/ /

# Compile llvm/clang with llvm/clang
RUN \
set -eux; \
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

COPY assets/bootstrap-step3/ /

# Re-compile optimized llvm/clang with llvm/clang
RUN \
set -eux; \
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

FROM bootstrap_step3 as bootstrap_step4

RUN rm --force --recursive /etc/portage/package.use

COPY assets/bootstrap-step4/ /

# Compile llvm-libunwind again because its static lib was missing in the previous build
RUN \
set -eux; \
emerge \
  llvm-libunwind \
  ; \
:;

# Re-compile all system packages with optimized llvm/clang
RUN \
--security=insecure \
set -eux; \
emerge \
  --deep \
  --emptytree \
  --newuse \
  --update \
  @world \
; \
:;
#
# Re-compile again (x2) to facilitate static linking.
# (perviously satisfied deps are now available statically which is important for lto)
#RUN \
#--security=insecure \
#set -eux; \
#emerge \
#  --deep \
#  --emptytree \
#  --newuse \
#  --update \
#  @world \
#  ; \
#:;
#
#RUN \
#--security=insecure \
#set -eux; \
#emerge \
#  --deep \
#  --emptytree \
#  --newuse \
#  --update \
#  @world \
#  ; \
#:;
