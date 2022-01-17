# syntax=docker/dockerfile:1.3-labs
ARG bootstrap_step1=gentoo/stage3:musl-20220114
FROM $bootstrap_step1 as bootstrap_step1

RUN emerge-webrsync

RUN rm --force --recursive /etc/portage/package.use

COPY assets/bootstrap/1/ /

# Compile llvm/clang with gcc
RUN \
set -eux; \
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

# Compile llvm-libunwind again because its static lib was missing in the previous build
# (the "static" USE flag was not set because it messes with the bootstrapping process)
RUN \
set -eux; \
emerge \
  llvm-libunwind \
; \
:;

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
; \
:;

FROM bootstrap_step3 as bootstrap_step4

COPY assets/bootstrap/4/ /

# Re-compile all system packages with optimized llvm/clang.
# We do this twice to facilitate LTO / static linking.
# Perviously satisfied bootstrap dep libs are available statically after the first rebuild.
# Those libs are then candidates for static linking (and better LTO) in the second build.
RUN \
--security=insecure \
set -eux; \
for _ in 1 2; do \
  emerge \
    --deep \
    --emptytree \
    --newuse \
    --update \
    @world \
  ; \
done; \
:;
