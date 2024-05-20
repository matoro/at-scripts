#!/usr/bin/env bash

set -euo pipefail

sudo -E id

[[ -e "/lib/gentoo/functions.sh" ]] && source "/lib/gentoo/functions.sh" || alias eerror="echo"
[[ "$(basename "$(realpath .)")" != "$(hostname -s)" ]] && set +u && eerror "Must run from inside directory named $(hostname -s)"
[[ -e "settings.sh" ]] && source "settings.sh"
source "../functions.sh"

run_defsettings
FLAVOR="${2:-"${DEFAULT_FLAVOR}"}"
MAKEOPTS="${MAKEOPTS:-"$(portageq envvar MAKEOPTS)"}"
[[ "$(stat -f -c %T "${PWD}")" == "nfs" ]] && export NFS_WORKAROUND="${NFS_WORKAROUND:-1}" || export NFS_WORKAROUND="${NFS_WORKAROUND:-0}"

URLBASE="${GENTOO_MIRROR:-https://gentoo.osuosl.org}/releases/${RELARCH}/autobuilds"

unset GNUPGHOME
[[ -z "${GPGTMP:-}" ]] || return 0
GPGTMP="$(mktemp --suffix=.gpg)"
[[ -e "/usr/share/openpgp-keys/gentoo-release.asc" ]] && gpg --no-default-keyring --keyring "${GPGTMP}" --import "/usr/share/openpgp-keys/gentoo-release.asc" || ( curl -sL "https://qa-reports.gentoo.org/output/service-keys.gpg" | gpg --no-default-keyring --keyring "${GPGTMP}" --import )

function verifycommit()
{
    git -C "${CHROOT_NAME}/var/db/repos/gentoo" cat-file commit HEAD | sed -e'/^gpgsig/d; /^ /d' > "/tmp/${CHROOT_NAME}_commit.txt"
    git -C "${CHROOT_NAME}/var/db/repos/gentoo" cat-file commit HEAD | sed -ne '/^gpgsig/,/---END/s/^[a-z]* //p' > "/tmp/${CHROOT_NAME}_sig.txt"
    gpg --no-default-keyring --keyring "${GPGTMP}" --verify "/tmp/${CHROOT_NAME}_sig.txt"  "/tmp/${CHROOT_NAME}_commit.txt"
}

function trapunmounts()
{
    EXIT_CODE="${?}"
    set +e
    run_dounmounts "${CHROOT_NAME}"
    exit "${EXIT_CODE}"
}

trap trapunmounts EXIT

declare -a pkglist
if [[ "${1}" =~ ^[0-9]+$ ]]
then
    # assume argument is bug number
    git -C "${REPO_DIR:-${HOME}/gentoo}" checkout master
    git -C "${REPO_DIR:-${HOME}/gentoo}" pull --ff-only
    readarray -t pkglist < <(set +u; nattka --repo "${REPO_DIR:-${HOME}/gentoo}" apply -a "${ARCH}" -n ${NATTKA_ARGUMENTS} "${1}" | sed '/^#.*/d' | sed '/^$/d' | cut -d " " -f 1)
else
    # assume argument is package atom(s)
    pkglist=( ${1} )
fi

wget -c -O - "${URLBASE}/latest-stage3-${FLAVOR}.txt" | gpg --no-default-keyring --keyring "${GPGTMP}" | tee "latest-stage3-${FLAVOR}.txt"
TARBALL="$(grep -E -m1 "^[^#]" "latest-stage3-${FLAVOR}.txt" | cut -d " " -f 1)"
CHROOT_NAME="$(basename -s .tar.xz "${TARBALL}")"
wget -c -O "$(basename "${TARBALL}")" "${URLBASE}/${TARBALL}"
wget -c -O "$(basename "${TARBALL}.asc")" "${URLBASE}/${TARBALL}.asc"
sync
gpg --no-default-keyring --keyring "${GPGTMP}" --verify "$(basename "${TARBALL}.asc")"
ln -svnf "${CHROOT_NAME}" "latest-stage3-${FLAVOR}"
[[ "${FLAVOR}" == "${DEFAULT_FLAVOR}" ]] && ln -svnf "latest-stage3-${FLAVOR}" "latest-default"
mkdir -vp "${CHROOT_NAME}"
if [[ "${NFS_WORKAROUND}" == "1" ]]
then
    if [[ ! -e "${CHROOT_NAME}.img" ]]
    then
        dd status=progress if=/dev/zero of="${CHROOT_NAME}.img" bs=10M count=1000 oflag=dsync
        mkfs.ext4 "${CHROOT_NAME}.img"
    fi
    if ! mountpoint -q "${CHROOT_NAME}"
    then
        run_dounmounts "${CHROOT_NAME}"
        sudo -E mount "${CHROOT_NAME}.img" "${CHROOT_NAME}"
    fi
fi
if [[ ! -d "${CHROOT_NAME}" ]] || [[ "$(find "${CHROOT_NAME}" -mindepth 1 -maxdepth 1 | wc -l)" == "1" ]] || [[ "$(find "${CHROOT_NAME}" -mindepth 1 -maxdepth 1 | wc -l)" == "0" ]]
then
    sudo -E tar -C "${CHROOT_NAME}" -x -v -J -f "$(basename "${TARBALL}")" --xattrs-include='*.*' --numeric-owner
    run_domounts "${CHROOT_NAME}"
    sudo -E cp -vaL "/etc/resolv.conf" "${CHROOT_NAME}/etc/resolv.conf"
    sudo -E cp -va "/etc/security/limits.conf" "${CHROOT_NAME}/etc/security/limits.conf"
    [[ -d "../releng" ]] || git -C .. clone "https://github.com/gentoo/releng"
    git -C "../releng" pull --ff-only
    sudo -E rsync --verbose --human-readable --recursive --links --times -D --chown=root:root --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r --progress "../releng/releases/portage/stages/" "${CHROOT_NAME}/etc/portage/"
    echo -e 'C.UTF8 UTF-8\nen_US.UTF-8 UTF-8' | sudo -E tee "${CHROOT_NAME}/etc/locale.gen"
    sudo -E git -C "${CHROOT_NAME}/var/db/repos" clone --depth=1 "https://github.com/gentoo-mirror/gentoo"
    verifycommit
    if [[ -e "/usr/local/share/ca-certificates/ca.crt" ]]
    then
        sudo -E mkdir -vp "${CHROOT_NAME}/usr/local/share/ca-certificates"
        sudo -E cp -va "/usr/local/share/ca-certificates/ca.crt" "${CHROOT_NAME}/usr/local/share/ca-certificates/ca.crt"
    fi
    [[ -n "${QEMU_BINARY:-}" ]] && sudo -E cp -v "${QEMU_BINARY}" "${CHROOT_NAME}/${QEMU_BINARY}"
    setarch "$(run_getpersonality)" -- sudo -E chroot "${CHROOT_NAME}" /bin/bash <<EOF
    set -eo pipefail
    source /etc/profile
    type locale-gen && locale-gen
    env-update && source /etc/profile
    type locale-gen && eselect locale set en_US.utf8
    env-update && source /etc/profile
    update-ca-certificates --fresh
    mkdir -vp /etc/portage/env
    eselect news read
    getuto
    echo "PORTAGE_WORKDIR_MODE=\"0750\"" | tee -a /etc/portage/make.conf
    echo "MAKEOPTS=\"${MAKEOPTS}\"" | tee -a /etc/portage/make.conf
    echo "EMERGE_DEFAULT_OPTS=\"--autounmask --autounmask-continue --autounmask-backtrack=y --complete-graph --deep --usepkg --getbinpkg --backtrack=300 --usepkg-exclude dev-perl/Mozilla-CA --usepkg-exclude perl-core/Math-BigInt\"" | tee -a /etc/portage/make.conf
    echo "PORTAGE_NICENESS=\"39\"" | tee -a /etc/portage/make.conf
    echo "FEATURES=\"-parallel-fetch binpkg-request-signature\"" | tee -a /etc/portage/make.conf
    [[ "${CHROOT_NAME}" != *"musl"* ]] && echo "PORTAGE_SCHEDULING_POLICY=\"idle\"" | tee -a /etc/portage/make.conf
    [[ "${CHROOT_NAME}" == *systemd* ]] && systemd-machine-id-setup
    [[ -n "${QEMU_BINARY:-}" ]] && sed -E -i "s/(^FEATURES=.*)\"$/\1 -pid-sandbox -network-sandbox\"/" /etc/portage/make.conf
    echo "TZ=\"UTC\"" | tee -a /etc/portage/make.conf
    mkdir -vp /etc/portage/env
    echo -e "USE=\"test\"\nFEATURES=\"test keeptemp\"" > /etc/portage/env/test
    touch /.ready
    sync
    emerge -vuDN1 --exclude sys-devel/gcc @world
    eselect news read
EOF
fi

run_domounts "${CHROOT_NAME}"
if [[ ! -e "${CHROOT_NAME}/.ready" ]]
then
    echo "Setup failed to complete, removing chroot"
    run_dounmounts "${CHROOT_NAME}"
    sudo -E rm -rf --one-file-system "${CHROOT_NAME}" "${CHROOT_NAME}.img"
    exit 1
fi

[[ -e "../testreqs.package.use" ]] && sudo -E cp -vf "../testreqs.package.use" "${CHROOT_NAME}/etc/portage/package.use/testreqs"
[[ -d "../distfiles" ]] && sudo -E rsync --verbose --human-readable --recursive --links --times -D --chown=portage:portage --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r --progress --update "../distfiles/" "${CHROOT_NAME}/var/cache/distfiles/"
sudo -E git -C "${CHROOT_NAME}/var/db/repos/gentoo" fetch --depth=1
sudo -E git -C "${CHROOT_NAME}/var/db/repos/gentoo" reset --merge origin/stable
verifycommit
setarch "$(run_getpersonality)" -- sudo -E chroot "${CHROOT_NAME}" /bin/bash <<EOF
set -eo pipefail
source /etc/profile
[[ ! -e /.ready ]] && echo "Setup failed to complete, please delete and rerun" && exit 1
eselect news read
rm -rf /etc/portage/package.env /etc/portage/package.accept_keywords /var/tmp/portage/*
[[ -z "${SKIP_UPDATES:-}" ]] && emerge -vuDN1 --exclude sys-devel/gcc @world
for f in ${pkglist[@]@Q} ; do echo "\${f} test" >> /etc/portage/package.env ; done
emerge -ev1 --keep-going ${pkglist[@]@Q} --usepkg-exclude "$(qatom -C -F "%{CATEGORY}/%{PN}" "${pkglist[@]}" | tr "\n" " ")" --autounmask-only
echo emerge -v1 --keep-going ${pkglist[@]@Q} --usepkg-exclude \""$(qatom -C -F "%{CATEGORY}/%{PN}" "${pkglist[@]}" | tr "\n" " ")"\"
emerge -v1 --keep-going ${pkglist[@]@Q} --usepkg-exclude "$(qatom -C -F "%{CATEGORY}/%{PN}" "${pkglist[@]}" | tr "\n" " ")"
EOF

run_dounmounts "${CHROOT_NAME}"
