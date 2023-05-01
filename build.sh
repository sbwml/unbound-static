#!/bin/bash

# Check Version
CURRENT_VERSION=$1
# LATEST_VERSION=$(curl -s https://nlnetlabs.nl/projects/unbound/download/ | grep "Current version" | awk '{print $2}')
LATEST_VERSION=$(curl -s -m 10 "https://api.github.com/repos/NLnetLabs/unbound/tags" | grep "name" | head -1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g;s/release-//g')
[ -z $LATEST_VERSION ] && echo -e "\e[1;31mFailed to get UNBOUND latest version.\e[0m" && exit 1

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
	echo -e " \n\e[1;32munbound - $CURRENT_VERSION is already the latest version! \e[0m\n"
	exit 0
else
	UNBOUND_VERSION=$LATEST_VERSION
	echo $LATEST_VERSION > new_version
fi

# Set ENV
[ ! -f ./env.rc ] && echo "Cannot find \`env.rc\` file." && exit 1 || source ./env.rc
WORK_PATH=$(pwd)
mkdir -p ~/static_build/extra && cd ~/static_build
TOP=$(pwd)

# download source code
unbound_source() {
	wget https://nlnetlabs.nl/downloads/unbound/unbound-$UNBOUND_VERSION.tar.gz
	tar -zxf unbound-$UNBOUND_VERSION.tar.gz && rm -f unbound-$UNBOUND_VERSION.tar.gz
}

openssl_source() {
	wget https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz
	tar -zxf openssl-$OPENSSL_VERSION.tar.gz && rm -f openssl-$OPENSSL_VERSION.tar.gz
}

libsodium_source() {
	wget https://download.libsodium.org/libsodium/releases/libsodium-$LIBSODIUM_VERSION.tar.gz
	tar -zxf libsodium-$LIBSODIUM_VERSION.tar.gz && rm -f libsodium-$LIBSODIUM_VERSION.tar.gz
}

libmnl_source() {
	git clone git://git.netfilter.org/libmnl --depth=1 -b libmnl-$LIBMNL_VERSION libmnl-$LIBMNL_VERSION
}

libhiredis_source() {
	wget https://github.com/redis/hiredis/archive/refs/tags/v$LIBHIREDIS_VERSION.tar.gz -O hiredis-$LIBHIREDIS_VERSION.tar.gz
	tar -zxf hiredis-$LIBHIREDIS_VERSION.tar.gz && rm -f hiredis-$LIBHIREDIS_VERSION.tar.gz
}

libevent_source() {
	wget https://github.com/libevent/libevent/releases/download/release-$LIBEVENT_VERSION/libevent-$LIBEVENT_VERSION.tar.gz
	tar -zxf libevent-$LIBEVENT_VERSION.tar.gz && rm -f libevent-$LIBEVENT_VERSION.tar.gz
}

nghttp2_source() {
	wget https://github.com/nghttp2/nghttp2/releases/download/v$NGHTTP2_VERSION/nghttp2-$NGHTTP2_VERSION.tar.gz
	tar -zxf nghttp2-$NGHTTP2_VERSION.tar.gz && rm -f nghttp2-$NGHTTP2_VERSION.tar.gz
}

expat_source() {
	wget https://github.com/libexpat/libexpat/releases/download/R_$(echo $EXPAT_SOURCE | sed "s/\./_/g")/expat-$EXPAT_SOURCE.tar.gz
	tar -zxf expat-$EXPAT_SOURCE.tar.gz && rm -f expat-$EXPAT_SOURCE.tar.gz
}

cd $TOP/extra
openssl_source || ( echo -e "\e[1;31mdownload openssl failed.\e[0m" ; exit 1 )
libsodium_source || ( echo -e "\e[1;31mdownload libsodium failed.\e[0m" ; exit 1 )
libmnl_source || ( echo -e "\e[1;31mdownload libmnl failed.\e[0m" ; exit 1 )
libhiredis_source || ( echo -e "\e[1;31mdownload libhiredis failed.\e[0m" ; exit 1 )
libevent_source || ( echo -e "\e[1;31mdownload libevent failed.\e[0m" ; exit 1 )
nghttp2_source || ( echo -e "\e[1;31mdownload nghttp2 failed.\e[0m" ; exit 1 )
expat_source || ( echo -e "\e[1;31mdownload expat failed.\e[0m" ; exit 1 )
cd $TOP
unbound_source || ( echo -e "\e[1;31mdownload unbound failed.\e[0m" ; exit 1 )

# build openssl
cd $TOP/extra/openssl-*
./config --prefix=$TOP/extra/openssl no-shared CC=clang CXX=clang++
make -j$(($(nproc --all)+1))
if [ $? -ne 0 ]; then
	echo -e "\n\e[1;31mOpenSSL compilation failed.\e[0m\n"
	exit 1
else
	make install_sw
	export PKG_CONFIG_PATH=$TOP/extra/openssl/lib/pkgconfig:$PKG_CONFIG_PATH
fi

# build libsodium
cd $TOP/extra/libsodium-*
./configure --prefix=$TOP/extra/libsodium --disable-shared --enable-static CC=clang CXX=clang++
make -j$(($(nproc --all)+1))
if [ $? -ne 0 ]; then
	echo -e "\n\e[1;31mlibsodium compilation failed.\e[0m\n"
	exit 1
else
	make install
fi

# build libmnl
cd $TOP/extra/libmnl-*
./autogen.sh && ./configure --prefix=$TOP/extra/libmnl --disable-shared --enable-static CC=clang CXX=clang++
make -j$(($(nproc --all)+1))
if [ $? -ne 0 ]; then
	echo -e "\n\e[1;31mlibmnl compilation failed.\e[0m\n"
	exit 1
else
	make install
fi

# build libhiredis
cd $TOP/extra/hiredis-*
mkdir build && cd build
CC=clang CXX=clang++ cmake \
  -DCMAKE_INSTALL_PREFIX=$TOP/extra/libhiredis \
  -DENABLE_SSL=ON \
  -DENABLE_EXAMPLES=ON \
  -DOPENSSL_ROOT_DIR="$TOP/extra/openssl" \
  ..
make -j$(($(nproc --all)+1))
if [ $? -ne 0 ]; then
	echo -e "\n\e[1;31mlibhiredis compilation failed.\e[0m\n"
	exit 1
else
	make install
	# hack ld
	[ -d $TOP/extra/libhiredis/lib64 ] && ln -s $TOP/extra/libhiredis/lib64 $TOP/extra/libhiredis/lib
fi

# build libevent
cd $TOP/extra/libevent-*
[ -f "/etc/redhat-release" ] && centos_version=`cat /etc/redhat-release|sed -r 's/.* ([0-9]+)\..*/\1/'`
[ $centos_version = 7 ] && DISABLE_SSL="--disable-openssl" # fix build for centos7
./configure --prefix=$TOP/extra/libevent --disable-shared --enable-static $DISABLE_SSL CC=clang CXX=clang++
make -j$(($(nproc --all)+1))
if [ $? -ne 0 ]; then
	echo -e "\n\e[1;31mlibevent compilation failed.\e[0m\n"
	exit 1
else
	make install
fi

# build nghttp2
cd $TOP/extra/nghttp2-*
./configure \
  --prefix=$TOP/extra/libnghttp2 \
  --disable-shared \
  --enable-static \
  CC=clang CXX=clang++
make -j$(($(nproc --all)+1))
if [ $? -ne 0 ]; then
	echo -e "\n\e[1;31mnghttp2 compilation failed.\e[0m\n"
	exit 1
else
	make install
fi

# build expat
cd $TOP/extra/expat-*
./configure --prefix=$TOP/extra/expat --without-docbook CC=clang CXX=clang++
make -j$(($(nproc --all)+1))
if [ $? -ne 0 ]; then
	echo -e "\n\e[1;31mexpat compilation failed.\e[0m\n"
	exit 1
else
	make install
fi

# build unbound
cd $TOP/unbound-*
make clean >/dev/null 2>&1
./configure \
  --prefix=$INSTALL_DIR/unbound \
  --disable-shared \
  --disable-rpath \
  --enable-tfo-client \
  --enable-tfo-server \
  --enable-static-exe \
  --enable-fully-static \
  --enable-static \
  --enable-pie \
  --enable-subnet \
  --enable-dnscrypt \
  --enable-cachedb \
  --enable-ipsecmod \
  --enable-ipset \
  --with-libnghttp2="$TOP/extra/libnghttp2" \
  --with-libevent="$TOP/extra/libevent" \
  --with-libsodium="$TOP/extra/libsodium" \
  --with-libmnl="$TOP/extra/libmnl" \
  --with-ssl="$TOP/extra/openssl" \
  --with-libhiredis="$TOP/extra/libhiredis" \
  CFLAGS="-Ofast -funsafe-math-optimizations -ffinite-math-only -fno-rounding-math -fexcess-precision=fast -funroll-loops -ffunction-sections -fdata-sections -pipe" \
  LDFLAGS="-L$TOP/extra/expat/lib -lexpat" \
  CC=clang CXX=clang++

make -j$(($(nproc --all)+1))
if [ $? -eq 0 ]; then
	rm -rf $INSTALL_DIR/unbound
	sudo make install
	sudo llvm-strip $INSTALL_DIR/unbound/sbin/unbound* >/dev/null 2>&1
	echo -e " \n\e[1;32munbound-static-$UNBOUND_VERSION compilation success\e[0m\n"
	$INSTALL_DIR/unbound/sbin/unbound -V
	pushd $INSTALL_DIR
		mkdir -p $WORK_PATH/build_out
		tar -Jcf $WORK_PATH/build_out/unbound-static-"$UNBOUND_VERSION"-linux-x$(getconf LONG_BIT).tar.xz unbound
		tar -zcf $WORK_PATH/build_out/unbound-static-"$UNBOUND_VERSION"-linux-x$(getconf LONG_BIT).tar.gz unbound
	popd
	cd $WORK_PATH/build_out && sha256sum * > sha256sum.txt
else
	echo -e "\n\e[1;31munbound compilation failed.\e[0m\n"
	exit 1
fi
