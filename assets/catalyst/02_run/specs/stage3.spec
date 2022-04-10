subarch: amd64
target: stage3
version_stamp: musl-clang-lto
rel_type: musl-clang-lto
profile: default/linux/amd64/17.0/clang-musl/optimize
snapshot_treeish: latest
source_subpath: musl-clang-lto/stage2-amd64-musl-clang-lto.tar.gz
compression_mode: gzip
cflags: -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -O3 -march=native -pipe -flto=thin
cxxflags: -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -O3 -march=native -pipe -flto=thin
hostuse: -X -accessibility -bash-completion -bluetooth -branding -doc -examples -man -ncurses -sqlite -systemd -test
