#!/bin/sh
#
# Execute this tool to setup the environment and build binary releases
# for Percona-Server starting from a fresh tree.
#
# Usage: build-binary.sh [target dir]
# The default target directory is the current directory. If it is not
# supplied and the current directory is not empty, it will issue an error in
# order to avoid polluting the current directory after a test run.
#

# Bail out on errors, be strict
set -ue

# Examine parameters
TARGET="$(uname -m)"
TARGET_CFLAGS=''
WITH_SSL='/usr'
TAG=''
#
COMMON_FLAGS=''
#
# Some programs that may be overriden
TAR=${TAR:-tar}

# Check if we have a functional getopt(1)
if ! getopt --test
then
    go_out="$(getopt --options="it" --longoptions=with-ssl:,tag:,i686 \
        --name="$(basename "$0")" -- "$@")"
    test $? -eq 0 || exit 1
    eval set -- $go_out
fi

for arg
do
    case "$arg" in
    -- ) shift; break;;
    -i | --i686 )
        shift
        TARGET="i686"
        TARGET_CFLAGS="-m32 -march=i686"
        ;;
    --with-ssl )
        shift
        WITH_SSL="$1"
        shift
        ;;
    -t | --tag )
        shift
        TAG="$1"
        shift
        ;;
    esac
done

# Working directory
if test "$#" -eq 0
then
    WORKDIR="$(pwd)"
    
    # Check that the current directory is not empty
    if test "x$(echo *)" != "x*"
    then
        echo >&2 \
            "Current directory is not empty. Use $0 . to force build in ."
        exit 1
    fi

    WORKDIR_ABS="$(cd "$WORKDIR"; pwd)"

elif test "$#" -eq 1
then
    WORKDIR="$1"

    # Check that the provided directory exists and is a directory
    if ! test -d "$WORKDIR"
    then
        echo >&2 "$WORKDIR is not a directory"
        exit 1
    fi

    WORKDIR_ABS="$(cd "$WORKDIR"; pwd)"

else
    echo >&2 "Usage: $0 [target dir]"
    exit 1

fi

SOURCEDIR="$(cd $(dirname "$0"); cd ..; pwd)"
test -e "$SOURCEDIR/Makefile" || exit 2

# The number of processors is a good default for -j
if test -e "/proc/cpuinfo"
then
    PROCESSORS="$(grep -c ^processor /proc/cpuinfo)"
else
    PROCESSORS=4
fi

# Extract version from the Makefile
MYSQL_VERSION="$(grep ^MYSQL_VERSION= "$SOURCEDIR/Makefile" \
    | cut -d = -f 2)"
PERCONA_SERVER_VERSION="$(grep ^PERCONA_SERVER_VERSION= \
    "$SOURCEDIR/Makefile" | cut -d = -f 2)"
PERCONA_INNODB_VERSION="$(echo "$PERCONA_SERVER_VERSION" |
    sed s/rel//)"
PRODUCT="Percona-Server-$MYSQL_VERSION"

# Build information
REVISION="$(cd "$SOURCEDIR"; bzr revno)"
PRODUCT_FULL="Percona-Server-$MYSQL_VERSION-$PERCONA_SERVER_VERSION"
PRODUCT_FULL="$PRODUCT_FULL-$REVISION$TAG.$(uname -s).$TARGET"
COMMENT="Percona Server (GPL), Release ${PERCONA_SERVER_VERSION#rel}"
COMMENT="$COMMENT, Revision $REVISION"

# Compilation flags
export CC=${CC:-gcc}
export CXX=${CXX:-g++}

#
if [ -n "$(which rpm)" ]; then
  export COMMON_FLAGS=$(rpm --eval %optflags | sed -e "s|march=i386|march=i686|g")
fi
#
export CFLAGS="${COMMON_FLAGS} -DPERCONA_INNODB_VERSION=$PERCONA_SERVER_VERSION"
export CXXFLAGS="${COMMON_FLAGS} -DPERCONA_INNODB_VERSION=$PERCONA_SERVER_VERSION"
#
export MAKE_JFLAG="${MAKE_JFLAG:--j$PROCESSORS}"
#
# Create a temporary working directory
INSTALLDIR="$(cd "$WORKDIR" && TMPDIR="$WORKDIR_ABS" mktemp -d percona-build.XXXXXX)"
INSTALLDIR="$WORKDIR_ABS/$INSTALLDIR"   # Make it absolute

# Build
(
    cd "$SOURCEDIR"
 
    # Execute clean and download mysql, apply patches
    make clean all

    cd "$PRODUCT"
    ./configure \
        --prefix="/usr/local/$PRODUCT_FULL" \
        --localstatedir="/usr/local/$PRODUCT_FULL/data" \
        --with-plugins=partition,archive,blackhole,csv,example,federated,innodb_plugin \
        --without-embedded-server \
        --with-comment="$COMMENT" \
        --enable-assembler \
        --enable-local-infile \
        --with-mysqld-user=mysql \
        --with-unix-socket-path=/var/lib/mysql/mysql.sock \
        --with-pic \
        --with-extra-charsets=complex \
        --with-ssl="$WITH_SSL" \
        --enable-thread-safe-client \
        --enable-profiling \
        --with-readline 

    make $MAKE_JFLAG VERBOSE=1
    make DESTDIR="$INSTALLDIR" install

    # Build HandlerSocket
    (
        cd "storage/HandlerSocket-Plugin-for-MySQL"
        ./autogen.sh
        CXX=${HS_CXX:-g++} ./configure --with-mysql-source="$SOURCEDIR/$PRODUCT" \
            --with-mysql-bindir="$SOURCEDIR/$PRODUCT/scripts" \
            --with-mysql-plugindir="/usr/local/$PRODUCT_FULL/lib/mysql/plugin" \
            --libdir="/usr/local/$PRODUCT_FULL/lib/mysql/plugin" \
            --prefix="/usr/local/$PRODUCT_FULL"
        make $MAKE_JFLAG
        make DESTDIR="$INSTALLDIR" install

    )

    # Build UDF
    (
        cd "UDF"
        CXX=${UDF_CXX:-g++} ./configure --includedir="$SOURCEDIR/$PRODUCT/include" \
            --libdir="/usr/local/$PRODUCT_FULL/mysql/plugin"
        make $MAKE_JFLAG
        make DESTDIR="$INSTALLDIR" install

    )

)

# Package the archive
(
    cd "$INSTALLDIR/usr/local/"

    $TAR czf "$WORKDIR_ABS/$PRODUCT_FULL.tar.gz" \
        --owner=0 --group=0 "$PRODUCT_FULL/"
    
)

# Clean up
rm -rf "$INSTALLDIR"
