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
