#!/bin/bash
#shellcheck disable=SC2206,SC2001,SC2046,SC2164
# pre-configure.sh
# cdebian pre-configure script for wslu
# <https://github.com/wslutilities/wslu>
# Copyright (C) 2019 Patrick Wu
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# This script should be run with "./build.sh [--ci] <version> <distribution> <codename> <changelog>"
# Available distributions:
#   - Ubuntu: ubuntu (amd64 arm64)
#   - Debian: debian (all) - buster, bullseye
#   - Kali Linux: kali (amd64)
#   - Pengwin: pengwin (all)
# Available versions:
#   - latest
#   - <version>
#   - dev
CI="false"

if [ "${1}" = "--ci" ]; then
    CI="true"
    shift
fi

POSTFIX="${2}1"
DISTRO="${2}"

cleanup() {
  rm -rvf ./wslu*/
  rm -rvf ./wslu-*.tar.gz
  rm -rvf ./debian
}

trap cleanup EXIT

case "$DISTRO" in
  ubuntu)
    curl -s https://api.wedotstud.io/ubuntu/release/wslu.csv > ubuntu_version_definition
    CODENAME="$3"
    declare -A uvd 
    OIFS=$IFS
    IFS=','
    while read -r value key
    do
        uvd+=( ["$value"]="$key" )
    done < "./ubuntu_version_definition"
     [ -v 'uvd[$CODENAME]' ] || exit 1
    IFS=$OIFS
    ARCHITECTURE="amd64 arm64"
    POSTFIX="$POSTFIX${uvd[$CODENAME]}"
    rm -f ./ubuntu_version_definition
    ;;
  debian)
    [[ "$3" == "buster" || "$3" == "bullseye" || "$3" == "stable" || "$3" == "unstable" ]] || exit 1
    CODENAME="$3"
    ARCHITECTURE="all"
    ;;
  kali)
    [[ "$3" == "kali-rolling" || "$3" == "kali-dev" ]] || exit 1
    CODENAME="$3"
    ARCHITECTURE="amd64"
    ;;
  pengwin)
    CODENAME="bullseye"
    ARCHITECTURE="all"
    ;;
  *)
    exit 1
    ;;
esac

if [[ "${CI}" == "true" ]]; then
    VERSION="$(sed s/-/.d$(date +%s)-/g ../VERSION)"
    CHANGELOG="This is a dev build in CI; Please check the dev/master branch to see the latest changes"
else
    case $1 in
        dev)
            VERSION="$(curl -s https://raw.githubusercontent.com/wslutilities/wslu/dev/master/VERSION | sed s/-/.d$(date +%s)-/g)"
            tmp_version="$(echo "$VERSION" | sed s/-.*$//g)"
            wget "https://github.com/wslutilities/wslu/archive/dev/master.tar.gz" -O "wslu-${tmp_version}.tar.gz"
            CHANGELOG="This is a dev build; Please check the dev/master branch to see the latest changes"
            ;;
        latest)
            tmp_info="$(curl -s https://api.github.com/repos/wslutilities/wslu/releases/latest)"
            tmp_version="$(echo "$tmp_info" | grep -oP '"tag_name": "v\K(.*)(?=")')"
            CHANGELOG="$(echo "$tmp_info" | grep -oP '"body": "\K(.*)(?=")')"
            CHANGELOG="$(echo -e "$CHANGELOG" | sed -e "s/\r//g" -e "s/^\s*##.*$//g" -e "/^$/d" -e "s/^-/  -/g" -e "s/$/|/g")"
            wget "https://github.com/wslutilities/wslu/archive/refs/tags/v${tmp_version}.tar.gz" -O "wslu-${tmp_version}.tar.gz"
            VERSION="$(curl -s https://raw.githubusercontent.com/wslutilities/wslu/v"${tmp_version}"/VERSION)"
            ;;
        *)
            tmp_info="$(curl -s https://api.github.com/repos/wslutilities/wslu/releases/tags/v${1})"
            CHANGELOG="$(echo "$tmp_info" | grep -oP '"body": "\K(.*)(?=")')"
            CHANGELOG="$(echo -e "$CHANGELOG" | sed -e "s/\r//g" -e "s/^\s*##.*$//g" -e "/^$/d" -e "s/^-/  -/g" -e "s/$/|/g")"
            wget "https://github.com/wslutilities/wslu/archive/refs/tags/v${1}.tar.gz" -O "wslu-${1}.tar.gz"
            VERSION="$(curl -s https://raw.githubusercontent.com/wslutilities/wslu/v${1}/VERSION)"
            ;;
    esac
fi
cp -r ./debian-template/ ./debian
chmod +x ./debian/rules
DEBFULLNAME="Patrick Wu"
DEBEMAIL="patrick@wslutiliti.es"
if [ "$DISTRO" = "ubuntu" ]; then
    DEBFULLNAME="Jinming Wu, Patrick"
    DEBEMAIL="me@patrickwu.space"
fi
sed -i s/DEBNAMEPLACHOLDER/"$DEBFULLNAME"/g ./debian/changelog
sed -i s/DEBEMAILPLACEHOLDER/"$DEBEMAIL"/g ./debian/changelog
sed -i s/DISTROPLACEHOLDER/"$CODENAME"/g ./debian/changelog
sed -i s/VERSIONPLACEHOLDER/"$VERSION"/g ./debian/changelog
sed -i s/POSTFIXPLACEHOLDER/"$POSTFIX"/g ./debian/changelog
sed -i s/DATETIMEPLACEHOLDER/"$(date +'%a, %d %b %Y %T %z')"/g ./debian/changelog
sed -i s/ARCHPLACEHOLDER/"$ARCHITECTURE"/g ./debian/control

OIFS=$IFS; IFS=$'|'; cl_arr=($CHANGELOG); IFS=$OIFS;
for q in "${cl_arr[@]}"; do
    tmp="$(echo "$q" | sed -e 's/|$//g' -e 's/^  - //g')"
    if [ "$DISTRO" = "ubuntu" ]; then
        DEBFULLNAME="Jinming Wu, Patrick" DEBEMAIL="me@patrickwu.space" dch -a "$tmp"
    else
        DEBFULLNAME="Patrick Wu" DEBEMAIL="patrick@wslutiliti.es" dch -a "$tmp"
    fi
    unset tmp
done

case $DISTRO in
    debian|pengwin|kali)
        if [ "$CI" = "true" ]; then
            cd ../
            mv ./builder/debian ./debian
        else
            tar xvzf wslu-*.tar.gz
            rm ./*.tar.gz
            cd wslu*
            mv ../debian .
        fi
        # not all distribution definitions exist in one distro
        debuild -i -us -uc -b --lintian-opts --suppress-tags bad-distribution-in-changes-file
        if [ "$CI" != "true" ]; then
            cd ../
            mkdir -p ./pkgs
            mv ./wsl*.* ./pkgs/
        fi
        ;;
    # ubuntu do not have ci mainly due to password protected keys used in the build process
    ubuntu)
        cp wslu-*.tar.gz "wslu_${VERSION/-*/}.orig.tar.gz"
        tar xvzf wslu-*.tar.gz
        cd "wslu-${VERSION/-*/}"
        mv ../debian .
        GPG_TTY=$(tty) debuild -S -sa
        cd ../
        ;;
    *);;
esac


