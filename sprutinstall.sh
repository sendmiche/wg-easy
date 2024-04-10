#!/bin/sh

# Startup checks

firmware_upgrade_running() {
  if [ -f "/var/run/iqupdate.lock" ]; then echo "Firmware upgrade is in progress!"; return 1; else return 0; fi
}

script_running() {
  if ps -ef | grep "/[i]nstall.sh" | grep -cv $$ >/dev/null; then echo "Script $0 is already running!"; return 1; else return 0; fi
}

while ! firmware_upgrade_running || ! script_running; do sleep 3; done

# Variables

METHOD="update"
BRANCH="release"

if [ -n "$sh_path" ]; then BRANCH=$sh_path; fi
if [ -n "$1" ]; then METHOD=$1; fi
if [ -n "$2" ]; then BRANCH=$2; fi

PlatformName="Unsupported platform"

Raspberry=false
SpruthubCE=false
Spruthub2=false

USER="makesimple"
GROUP="makesimple"
RIGHTS=0755
DOMAIN="https://makesimple.org"
SCRIPTS_URL="${DOMAIN}/scripts"
USERDIR="/home/makesimple"
UPDATE_SCRIPT="/sbin/update"
CREATE_USER=true

if pidof systemd; then USE_SYSTEMD=true; else USE_SYSTEMD=false; fi
if [ -f "/etc/debian_version" ]; then INSTALL_PACKAGES=true; else INSTALL_PACKAGES=false; fi

if [ -f "/proc/device-tree/compatible" ]; then compatible="$(tr -d '\0' </proc/device-tree/compatible)"; fi

case $compatible in
raspberrypi*)
  PlatformName="Raspberry"
  Raspberry=true
  GROUP="pi"
  RIGHTS=0775
  ;;
jethome*)
  PlatformName="JetHome"
  ;;
*wirenboard6*)
  PlatformName="Wiren Board 6"
  USERDIR="/mnt/data/makesimple"
  ;;
*wirenboard-7*)
  PlatformName="Wiren Board 7"
  USERDIR="/mnt/data/makesimple"
  ;;
"amlogic, Gxbb" | "amlogic, g12a")
  PlatformName="Sprut.hub CE"
  SpruthubCE=true
  USER="spruthub"
  GROUP="spruthub"
  SCRIPTS_URL="${DOMAIN}/scripts/spruthub/ce"
  USERDIR="/usr/local/home/spruthub"
  UPDATE_SCRIPT="${USERDIR}/service"
  CREATE_USER=false
  ;;
*imaqliq,spruthub2din*)
  PlatformName="Sprut.hub 2 din"
  Spruthub2=true
  USERDIR="/usr/local/makesimple"
  FIRMWARE_URL="${DOMAIN}/firmwares/spruthub/2din"
  CREATE_USER=false
  ;;
*imaqliq,spruthub2*)
  PlatformName="Sprut.hub 2"
  Spruthub2=true
  USERDIR="/usr/local/makesimple"
  FIRMWARE_URL="${DOMAIN}/firmwares/spruthub/2"
  CREATE_USER=false
  ;;
*"x84" | "x64")
  PlatformName="PC"
  USERDIR="/mnt/data/makesimple"
  ;;
esac

echo "${PlatformName} detected"

DL_DIR="${USERDIR}/dl"
CHECKSUM_DIR="${USERDIR}/checksum"

mkdir -p ${DL_DIR}
mkdir -p ${CHECKSUM_DIR}
rm -rf ${DL_DIR:?}/*

if [ -f "${USERDIR}/branch" ]; then BRANCH="$(cat "${USERDIR}"/branch)"; fi
echo "Branch: $BRANCH"

UPDATE_DIR="${USERDIR}/update"
UPDATE_URL="${DOMAIN}/${BRANCH}"
SPRUTHUB_HOME=$USERDIR/SprutHub
SPRUTHUB_LOCAL=$USERDIR/.SprutHub
SPRUTHUB_DATA="${USERDIR}/.SprutHub/data"
SPRUTHUB_JAR="${SPRUTHUB_HOME}/lib/SprutHub.jar"
VERSION_JSON="${SPRUTHUB_DATA}/Version.json"
JDK_HOME="${USERDIR}/jdk"

WGET="wget -q --prefer-family=IPv4 --no-check-certificate --timeout=15"

# Update script

echo "#!/bin/sh
WGET=\"wget -nv --prefer-family=IPv4 --no-check-certificate --timeout=15 -O\"
url=\"${DOMAIN}/scripts/install.sh\"
script=\"/tmp/install.sh\"
wget_script() {
  rm -f \"\${script}\" \"\${script}\".md5
  if ! \$WGET \"\${script}.md5\" \"\${url}.md5\" || [ ! -s \"\${script}.md5\" ]; then return 1; fi
  if ! \$WGET \"\${script}\" \"\${url}\" || [ ! -s \"\${script}\" ]; then return 1; fi
  cd \"/tmp\" || return 1
  sleep 1
  if ! md5sum -c \"\${script}.md5\" > /dev/null; then
  rm -f \"\${script}\" \"\${script}.md5\"
  return 1
  fi
  rm -f \"\${script}.md5\"
  return 0
}
while ! wget_script; do sleep 1; done
chmod ${RIGHTS} \"\${script}\"
\"\${script}\" \"\${1}\"" >"${UPDATE_SCRIPT}" && chmod ${RIGHTS} "${UPDATE_SCRIPT}"

# FUNCTIONS

# $1 - file to calculate
calculateSum() {
  md5sum "${1}" | awk '{ print $1 }'
}

# $1 - file with checksum
getCheckSum() {
  awk <"${1}" '{print $1}'
}

# $1 - file to check
# $2 - file with checksum
checkSum() {
  if [ "$(calculateSum "${1}")" = "$(getCheckSum "${2}")" ]; then return 0; else return 1; fi
}

# $1 - path to save with file name
# $2 - url with file name
wget5() {
  if $WGET -O "$1" "$2" && [ -s "${1}" ]; then return 0; else rm -f "$1"; fi
  if $WGET -O "$1" "$2" && [ -s "${1}" ]; then return 0; else rm -f "$1"; fi
  if $WGET -O "$1" "$2" && [ -s "${1}" ]; then return 0; else rm -f "$1"; fi
  if $WGET -O "$1" "$2" && [ -s "${1}" ]; then return 0; else rm -f "$1"; fi
  if $WGET -O "$1" "$2" && [ -s "${1}" ]; then return 0; else rm -f "$1"; fi
  return 1
}

# $1 - url
# $2 - file name
wget_with_md5() {
  targetMd5="/tmp/${2}.md5"
  targetWget="${DL_DIR}/${2}"
  rm -f "${targetWget}" "${targetMd5}"
  if ! wget5 "${targetMd5}" "${1}/${2}.md5" || [ ! -s "${targetMd5}" ]; then return 1; fi
  if ! $WGET --show-progress -O "${targetWget}" "${1}/${2}" || [ ! -s "${targetWget}" ]; then return 1; fi
  if ! checkSum "${targetWget}" "${targetMd5}"; then
    rm -f "${targetMd5}" "${targetWget}" "${targetWget}".md5
    sync
    return 1
  fi
  cp "${targetMd5}" "${targetWget}.md5"
  sync
  return 0
}

# $1 - url
# $2 - file name
wget_retry() {
  echo "Retrying in 3 seconds..." && sleep 3
  wget_with_md5 "$1" "$2"
  return $?
}

# $1 - url
# $2 - file name
wget_silent() {
  if wget_with_md5 "$1" "$2"; then return 0; fi
  if wget_retry "$1" "$2"; then echo "Successfull"; fi
  if wget_retry "$1" "$2"; then echo "Successfull"; fi
  echo "Failed to download '${1}/${2}' please check internet connection!"
  return 1
}

# $1 - source dir
# $2 - file name
# $3 - target dir
unpack() {
  gunzip -c "${1}/${2}" | tar -xf - -C "${3}"
  rm -f "${1}"/"${2}"
  chown -R ${USER}:${GROUP} "${3}"
  sync
}

# $1 - source dir
# $2 - file name
# $3 - target dir
move() {
  if [ ! -f "${1}/${2}" ]; then return 1; fi
  mkdir -p "${3}"
  mv "${1}/${2}" "${3}/${2}"
  chown -R ${USER}:${GROUP} "${3}"
  sync
}

# $1 - update url
# $2 - file name
# $3 - target dir
download() {
  if wget_silent "${1}" "${2}"; then
    move "${DL_DIR}" "${2}" "${3}"
    move "${DL_DIR}" "${2}.md5" "${3}"
    return 0
  fi
  return 1
}

# $1 - update url
# $2 - file name
prepare_update() {
  download "${1}" "${2}" "${UPDATE_DIR}"
}

# $1 - file name
# $2 - target dir
update_unpack() {
  unpack "${UPDATE_DIR}" "${1}" "${2}"
  mv "${UPDATE_DIR}/${1}.md5" "${CHECKSUM_DIR}/${1}.md5"
  # clean, TODO remove
  rm -f "${2}"/"${1}".md5
  sync
}

# $1 - file name
# $2 - target dir
update_move() {
  move "${UPDATE_DIR}" "${1}" "${2}"
  move "${UPDATE_DIR}" "${1}.md5" "${CHECKSUM_DIR}"
  # clean, TODO remove
  rm -f "${2}/${1}.md5"
  sync
}

get_json_value() {
  if [ -f "$1" ]; then grep -o "\"$2\": \"[^\"]*" "$1" | grep -o "[^\"]*$"; else echo ""; fi
}

get_version() {
  if [ -f "${VERSION_JSON}" ]; then get_json_value "$VERSION_JSON" version; fi
}

get_revision() {
  if [ -f "${VERSION_JSON}" ]; then get_json_value "$VERSION_JSON" revision; fi
}

store_status() {
  status='/usr/bin/msgbusclient store plugins.spruthublaunch.status'
  case $# in
  1) ${status} value="$1" ;;
  2) ${status} value="$1" msg="$2" ;;
  3) ${status} value="$1" msg="$2" version="$3" ;;
  4) ${status} value="$1" msg="$2" version="$3" revision="$4" ;;
  esac
}

upgradeFirmware() {
  if ! $Spruthub2; then return 0; fi
  if [ "$BRANCH" = "test" ]; then FIRMWARE_URL="${FIRMWARE_URL}/test"; fi
  if ! wget_silent "${FIRMWARE_URL}" "firmware_version"; then echo "Failed to check firmware version!" && return 1; fi

  currFirmware="$(cat /etc/firmware_version)"
  newFirmware="$(cat ${DL_DIR}/firmware_version)"
  rm -f ${DL_DIR}/firmware_version ${DL_DIR}/firmware_version.md5

  if [ "$currFirmware" = "$newFirmware" ]; then echo "No firmware upgrade: ${currFirmware}" && return 0; fi
  if ! wget_silent "${FIRMWARE_URL}" "update.raucb"; then echo "Failed to download firmware!" && return 1; fi
  if ! rauc install "${DL_DIR}/update.raucb"; then echo "Failed to upgrade firmware!" && return 1; fi

  echo "Firmware upgraded to: ${newFirmware}" && sleep 1
  rm -f ${DL_DIR}/update.raucb
  sync
  reboot
  exit 0
}

install_package() {
  I=$(dpkg-query -l | grep "$1")
  if [ -n "$I" ]; then return 0; fi
  apt-get update && apt-get -y install "$1"
  I=$(dpkg-query -l | grep "$1")
  if [ -n "$I" ]; then return 0; fi
  return 1
}

group_check() {
  if [ "$(getent group "$1")" ]; then usermod -a -G "$1" ${USER}; fi
}

# Init at system start

if [ "$METHOD" = "init" ]; then
  if [ ! -d "${UPDATE_DIR}" ] && [ -d "${SPRUTHUB_HOME}" ] && [ -f "${SPRUTHUB_HOME}/bin/SprutHub" ] && [ -d "${SPRUTHUB_LOCAL}" ] && [ -f "${VERSION_JSON}" ]; then
    echo "Already installed"
    exit 0
  fi
  upgradeFirmware
fi

if [ "$METHOD" = "firmware" ]; then
  upgradeFirmware
  exit $?
fi

if [ "$METHOD" = "force" ]; then UPDATE_FORCE=true; else UPDATE_FORCE=false; fi

# User

if $CREATE_USER; then
  if [ ! -d $USERDIR ] || ! getent passwd ${USER} >/dev/null; then
    if $USE_SYSTEMD && [ -f /etc/systemd/system/spruthub.service ]; then systemctl stop spruthub; fi
    echo "Creating User ..."
    if [ ! "$(getent group "$1")" ]; then groupadd ${GROUP}; fi
    useradd --system -m -u 666 -g ${GROUP} -d $USERDIR -s /usr/sbin/nologin ${USER}
  fi
  if getent passwd ${USER} | grep bash >/dev/null; then usermod -p "*" -s /usr/sbin/nologin ${USER}; fi
  if $Raspberry; then
    usermod -g ${GROUP} ${USER}
    set -- "ssh" "input" "gpio" "i2c" "spi" "adm" "dialout" "cdrom" "sudo" "audio" "video" "plugdev" "games" "users" "netdev"
    for ITEM in "$@"; do group_check ${ITEM}; done
  fi
fi

# Packages

if $INSTALL_PACKAGES; then # packages already exist in Sprut.hub
  if $USE_SYSTEMD && [ -f /etc/systemd/system/bonjour.service ]; then
    systemctl disable bonjour
    rm -f /etc/systemd/system/bonjour.service
  fi
  install_package "avahi-daemon"
  install_package "libnss-mdns"
  install_package "libavahi-compat-libdnssd-dev"
  install_package "bluez"
fi

# Arch

if $Raspberry; then genericArch=$(dpkg --print-architecture); else genericArch=$(uname -m); fi

arch=""
case $genericArch in
i?86) arch="x86" ;;
x86_64 | amd64) arch="x86_64" ;;
aarch32) arch="armv8_32" ;;
aarch64 | arm64) arch="armv8_64" ;;
arm*) if [ "$(getconf LONG_BIT)" = "64" ]; then arch="armv8_64"; else arch="armv7-hf"; fi ;;
mips*) echo "Unsupported arch: ${genericArch}" && return 1 ;;
esac
echo "Detected arch: ${arch}"

# JDK

JDK="zulu8.76.0.17-ca-jdk8.0.402-linux_aarch32hf.tar.gz"
case $arch in
x86) JDK="zulu8.76.0.17-ca-jdk8.0.402-linux_i686.tar.gz" ;;
x86_64) JDK="zulu8.76.0.17-ca-jdk8.0.402-linux_x64.tar.gz" ;;
armv7) JDK="zulu8.76.0.17-ca-jdk8.0.402-linux_aarch32sf.tar.gz" ;;
armv7-hf | armv8_32) JDK="zulu8.76.0.17-ca-jdk8.0.402-linux_aarch32hf.tar.gz" ;;
armv8_64) JDK="zulu8.76.0.17-ca-jdk8.0.402-linux_aarch64.tar.gz" ;;
esac

# Download

# $1 - update url
# $2 - target dir
# $3 - target file
# $4 - check installed sum
check_installed() {
  if [ ! -d "${2}" ]; then return 1; fi
  localSumFile="${CHECKSUM_DIR}/${3}.md5"
  if [ ! -f "${localSumFile}" ]; then return 1; fi
  localSum=$(getCheckSum "${localSumFile}")
  if [ -n "$4" ] && [ "$4" = true ]; then
    if [ ! -f "${2}/${3}" ]; then return 1; fi
    installedSum=$(calculateSum "${2}/${3}")
    if [ "$localSum" != "$installedSum" ]; then return 1; fi
  fi
  remoteSumFile="/tmp/${3}.md5"
  if ! wget5 "${remoteSumFile}" "${1}/${3}.md5" || [ ! -s "${remoteSumFile}" ]; then return 1; fi
  remoteSum=$(getCheckSum "${remoteSumFile}")
  rm -f "${remoteSumFile}"
  if [ "$localSum" != "$remoteSum" ]; then return 1; fi
  return 0
}

# $1 - update url
# $2 - target dir
# $3 - target file
# $4 - check installed sum
check_and_prepare_update() {
  if $UPDATE_FORCE || ! check_installed "${1}" "${2}" "${3}" "${4}"; then prepare_update "${1}" "${3}"; fi
}

echo "Preparing files ..."

if [ -d "${UPDATE_DIR}" ] || [ ! -s "${SPRUTHUB_JAR}" ] || [ ! -s "${SPRUTHUB_HOME}/bin/SprutHub" ] || [ ! -d "${SPRUTHUB_HOME}/jni/Target" ] || [ ! -s "${VERSION_JSON}" ] || [ ! -d "${SPRUTHUB_LOCAL}/web2" ] || [ ! -s "${SPRUTHUB_LOCAL}/web2/index.html" ] ; then UPDATE_FORCE=true; fi

rm -rf ${UPDATE_DIR}
mkdir -p ${UPDATE_DIR}

check_and_prepare_update "${DOMAIN}/jdk" "${JDK_HOME}" "${JDK}"
check_and_prepare_update "${UPDATE_URL}" "${SPRUTHUB_DATA}" Version.json true
check_and_prepare_update "${UPDATE_URL}" "${USERDIR}" spruthub.tar.gz
check_and_prepare_update "${UPDATE_URL}" "${SPRUTHUB_LOCAL}" web2.tar.gz
check_and_prepare_update "${UPDATE_URL}" "${SPRUTHUB_HOME}" jni.tar.gz
check_and_prepare_update "${UPDATE_URL}" "${SPRUTHUB_DATA}" firmware.tar.gz true
check_and_prepare_update "${UPDATE_URL}" "${SPRUTHUB_DATA}" main.tar.gz true
check_and_prepare_update "${UPDATE_URL}" "${SPRUTHUB_DATA}" early.tar.gz true

if $SpruthubCE; then
  check_and_prepare_update "${SCRIPTS_URL}" "${USERDIR}" backup.sh true
  check_and_prepare_update "${SCRIPTS_URL}" "${USERDIR}" run.sh true
  check_and_prepare_update "${SCRIPTS_URL}" "${USERDIR}" service
  check_and_prepare_update "${SCRIPTS_URL}" "${USERDIR}" start.sh true
else
  check_and_prepare_update "${SCRIPTS_URL}" "${USERDIR}/scripts" backup.sh true
  check_and_prepare_update "${SCRIPTS_URL}" "${USERDIR}/scripts" start.sh true
fi

if $USE_SYSTEMD; then
  check_and_prepare_update "${SCRIPTS_URL}" "/etc/systemd/system" spruthub.service true
  check_and_prepare_update "${SCRIPTS_URL}" "/etc/systemd/system" spruthub-update.service true
fi

# Sync

sync

# Install / Upgrade

if $USE_SYSTEMD; then
  if [ -f /etc/systemd/system/spruthub.service ]; then systemctl stop spruthub; fi
else
  killall -2 java
  sleep 3
fi

IsUpgrade=false
previous_version=""
previous_revision=""
if [ -d "${SPRUTHUB_LOCAL}" ]; then
  previous_version=$(get_version)
  previous_revision=$(get_revision)
  IsUpgrade=true
fi

update_move Version.json "${SPRUTHUB_DATA}"

install_version=$(get_version)
install_revision=$(get_revision)

if $IsUpgrade; then
  echo "Upgrading Sprut.hub ${previous_version} (${previous_revision}) to version ${install_version} (${install_revision}) ..."
  if $SpruthubCE; then store_status 8 "Upgrading Sprut.hub ..." "${previous_version}" "${previous_revision}"; fi
else
  echo "Installing Sprut.hub ${install_version} (${install_revision}) ..."
  if $SpruthubCE; then store_status 9 "Installing Sprut.hub ..."; fi
fi

if [ -f "${UPDATE_DIR}/${JDK}" ]; then
  rm -rf ${JDK_HOME:?}/*
  mkdir -p ${JDK_HOME}
  targetJDK="${UPDATE_DIR}/${JDK}"
  gunzip -c "${targetJDK}" | tar --strip-components=1 --exclude="**/src.zip" -xf - -C "${JDK_HOME}"
  chown -R ${USER}:${GROUP} "${JDK_HOME}"
  chmod -R ${RIGHTS} "${JDK_HOME}/bin"
  chmod -R ${RIGHTS} "${JDK_HOME}/jre/bin"
  rm -f "${targetJDK}"
  mv "${UPDATE_DIR}/${JDK}.md5" "${CHECKSUM_DIR}/${JDK}.md5"
  sync
fi

if [ -f "${UPDATE_DIR}/spruthub.tar.gz" ]; then
  rm -rf ${SPRUTHUB_HOME:?}/bin
  rm -rf ${SPRUTHUB_HOME:?}/lib
  update_unpack spruthub.tar.gz "${USERDIR}"
  chmod ${RIGHTS} "${SPRUTHUB_HOME}/bin/SprutHub"
  sync
fi

if [ -f "${UPDATE_DIR}/web2.tar.gz" ]; then
  rm -rf ${SPRUTHUB_LOCAL}/web2
  update_unpack web2.tar.gz "${SPRUTHUB_LOCAL}"
fi

if [ -f "${UPDATE_DIR}/jni.tar.gz" ]; then
  rm -rf ${SPRUTHUB_HOME}/jni/*
  update_unpack jni.tar.gz "${SPRUTHUB_HOME}"
fi

if [ -f "${UPDATE_DIR}/firmware.tar.gz" ]; then
  update_move firmware.tar.gz "${SPRUTHUB_DATA}"
fi

if [ -f "${UPDATE_DIR}/main.tar.gz" ]; then
  update_move main.tar.gz "${SPRUTHUB_DATA}"
fi

if [ -f "${UPDATE_DIR}/early.tar.gz" ]; then
  update_move early.tar.gz "${SPRUTHUB_DATA}"
fi

if $SpruthubCE; then
  update_move backup.sh "${USERDIR}" && chmod ${RIGHTS} "${USERDIR}/backup.sh"
  update_move run.sh "${USERDIR}" && chmod ${RIGHTS} "${USERDIR}/run.sh"
  update_move service "${USERDIR}" && chmod ${RIGHTS} "${USERDIR}/service"
  update_move start.sh "${USERDIR}" && chmod ${RIGHTS} "${USERDIR}/start.sh"
  cp "${CHECKSUM_DIR}/start.sh.md5" "${USERDIR}/start.sh.md5"
  sync
else
  update_move backup.sh "${USERDIR}/scripts" && chmod ${RIGHTS} "${USERDIR}/scripts/backup.sh"
  update_move start.sh "${USERDIR}/scripts" && chmod ${RIGHTS} "${USERDIR}/scripts/start.sh"
fi

if $USE_SYSTEMD; then
  update_move spruthub.service "/etc/systemd/system"
  update_move spruthub-update.service "/etc/systemd/system"
fi

# Backup

if $IsUpgrade; then
  if $SpruthubCE; then "${USERDIR}/backup.sh"; else "${USERDIR}/scripts/backup.sh"; fi
fi

# Config

echo "Configuring ..."

if [ ! -d "${SPRUTHUB_HOME}/jni" ]; then mkdir -p "${SPRUTHUB_HOME}/jni"; fi
if [ -d "${SPRUTHUB_HOME}/jni" ] && [ ! -d "${SPRUTHUB_HOME}/jni/Target" ] && [ ! -L "${SPRUTHUB_HOME}/jni/Target" ]; then
  ln -sf "${SPRUTHUB_HOME}/jni/Linux/${arch}" "${SPRUTHUB_HOME}/jni/Target"
  sync
fi

if [ ! -d "/tmp/spruthub" ]; then mkdir -p "/tmp/spruthub"; fi
if [ -d "/tmp/spruthub/spruthub" ]; then rm "/tmp/spruthub/spruthub"; fi
if [ ! -d "${SPRUTHUB_LOCAL}/logs" ] && [ ! -L "${SPRUTHUB_LOCAL}/logs" ]; then
  ln -s "/tmp/spruthub" "${SPRUTHUB_LOCAL}/logs"
  sync
fi

printf "export LC_ALL=ru_RU.UTF-8\n" >"${USERDIR}/.bashrc"
printf "export LANG=ru_RU.UTF-8\n" >>"${USERDIR}/.bashrc"
printf "export JAVA_HOME=%s\n" "${JDK_HOME}" >>"${USERDIR}/.bashrc"

# Permissions

find "${USERDIR}" -type d -exec chmod ${RIGHTS} {} \;
chown -R ${USER}:${GROUP} "$USERDIR"
sync

# Service

if $USE_SYSTEMD; then
  echo "Installing Service ..."
  systemctl daemon-reload
  systemctl enable spruthub
  systemctl enable avahi-daemon --quiet
  sync
fi

# Clean

rm -rf ${SPRUTHUB_LOCAL}/swagger
rm -rf ${SPRUTHUB_LOCAL}/web
rm -f ${SPRUTHUB_LOCAL}/data/SQL/*.trace.db
rm -f ${SPRUTHUB_LOCAL}/Log.xml
rm -f ${SPRUTHUB_LOCAL}/*.log
rm -f ${SPRUTHUB_LOCAL}/*.log.zip
sync

if [ -d "${SPRUTHUB_DATA}/SQL/Install" ]; then
  find "${SPRUTHUB_DATA}/Templates/" -mindepth 2 -maxdepth 2 ! -regex '.*/Custom.*' -exec rm -rf {} \;
  find "${SPRUTHUB_DATA}/Automation/" -mindepth 2 -maxdepth 2 ! -regex '.*/Custom.*' -exec rm -rf {} \;
  rm -rf ${SPRUTHUB_DATA}/Firmwares
  rm -rf ${SPRUTHUB_DATA}/SQL/Install
  rm -rf ${SPRUTHUB_DATA}/SQL/Upgrade
  sync
fi

rm -rf ${DL_DIR:?}/*
rm -rf ${UPDATE_DIR}
sync

# Firmware

upgradeFirmware

# Done

echo "Done"

if $SpruthubCE; then
  if $IsUpgrade; then
    store_status 10 "Upgrade Sprut.hub ${previous_version}(${previous_revision}) to version ${install_version}(${install_revision}) done" "${install_version}" "${install_revision}"
  else
    store_status 11 "Installing done" "${install_version}" "${install_revision}"
  fi
fi

# Restart

if $USE_SYSTEMD; then
  sync
  systemctl restart spruthub
fi
