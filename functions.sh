function run_dounmounts() 
{
    [[ -d "${1}" ]] || return
    ( pgrep dirmngr || true ) | xargs -r -I "%" bash -c '[[ "$(sudo -E realpath "/proc/%/root")" == "$(realpath '"${1}"')" ]] && sudo -E kill "%" || true'
    for f in dev/pts proc dev sys run usr/src lib/modules var/cache/distfiles
    do
        if mountpoint -q "${1}/${f}"
    then
            sudo -E umount --lazy "${1}/${f}"
        fi
    done
    if mountpoint -q "${1}"
    then
        sudo -E umount "${1}"
    fi
}
 
function run_domounts() 
{
    [[ -d "${1}" ]] || return
    run_dounmounts "${1}"
    [[ "$(stat -f -c %T "${PWD}")" == "nfs" ]] && export NFS_WORKAROUND="${NFS_WORKAROUND:-1}" || export NFS_WORKAROUND="${NFS_WORKAROUND:-0}"
    if [[ "${NFS_WORKAROUND}" == "1" ]]
    then
        sudo -E mount "$(basename "$(realpath "${1}")").img" "${1}"
    fi
    if ! mountpoint -q "${1}/proc"
    then
        sudo -E mount -t proc /proc "${1}/proc"
    fi
    for f in dev dev/pts sys run
    do
        if ! mountpoint -q "${1}/${f}"
        then
            sudo -E mount --rbind "/${f}" "${1}/${f}"
            sudo -E mount --make-rslave "${1}/${f}"
        fi
    done
    if [[ -z "${NOSRC:-}" ]]
    then
        for f in lib/modules usr/src # var/cache/distfiles
        do
            [[ -d "${1}/${f}" ]] || sudo -E mkdir -vp "${1}/${f}"
            [[ -d "${1}/tmp/overlayfs_$(basename "${f}")_workdir" ]] || sudo -E mkdir -vp "${1}/tmp/overlayfs_$(basename "${f}")_workdir"
            if [[ -e "/${f}" ]] && ! mountpoint -q "${1}/${f}"
            then
                sudo -E mount -t overlay overlay -o "lowerdir=/${f},upperdir=${1}/${f},workdir=${1}/tmp/overlayfs_$(basename "${f}")_workdir" "${1}/${f}"
            fi
        done
    fi
    [[ -e "${1}/usr/lib/modules" ]] || sudo -E ln -svf "../../lib/modules" "${1}/usr/lib/modules"
}

function run_urlencode() {
    perl -MURI::Escape -e 'print uri_escape shift, , q{^A-Za-z0-9\-._~/:}' "${1}" && echo
}
 
function run_urldecode() {
    perl -MURI::Escape -e 'print uri_unescape shift' "${1}" && echo
}

function run_defsettings()
{
    [[ -f "settings.sh" ]] && source "settings.sh"
    ARCH="${ARCH:-"$(portageq envvar ARCH)"}"
    RELARCH="${RELARCH:-"${ARCH}"}"
    DEFAULT_FLAVOR="${DEFAULT_FLAVOR:-"$(run_getdefaultflavor "${ARCH}")"}"
}

function run_dokw() 
{ 
    [[ -z "${1}" ]] && return
    [[ -f "settings.sh" ]] && source "settings.sh"
    git -C "${REPO_DIR:-${HOME}/gentoo}" checkout master
    git -C "${REPO_DIR:-${HOME}/gentoo}" pull --ff-only
    git -C "${REPO_DIR:-${HOME}/gentoo}" checkout keywording
    git -C "${REPO_DIR:-${HOME}/gentoo}" fetch
    git -C "${REPO_DIR:-${HOME}/gentoo}" reset --hard fork/keywording
    git -C "${REPO_DIR:-${HOME}/gentoo}" rebase master
    nattka --repo "${REPO_DIR:-${HOME}/gentoo}" apply -a "${ARCH:-$(portageq envvar ARCH)}" ${NATTKA_ARGUMENTS} "${1}"
    nattka --repo "${REPO_DIR:-${HOME}/gentoo}" commit -a "${ARCH:-$(portageq envvar ARCH)}" "${1}"
    git -C "${REPO_DIR:-${HOME}/gentoo}" push --force
}
 
function run_testlogs() 
{ 
    run_defsettings
    run_domounts "latest-stage3-${1:-${DEFAULT_FLAVOR}}"
    awk '/>>> Test phase/{f=1} /(>>> Completed testing|disabled because of RESTRICT=test)/{f=0;print} f' latest-stage3-${1:-${DEFAULT_FLAVOR}}/var/tmp/portage/*/*/temp/build.log
    run_dounmounts "latest-stage3-${1:-${DEFAULT_FLAVOR}}"
}

function run_addca()
{
    [[ -f "settings.sh" ]] && source "settings.sh"
    run_defsettings
    run_domounts "latest-stage3-${1:-${DEFAULT_FLAVOR}}"
    [[ ! -d "latest-stage3-${1:-${DEFAULT_FLAVOR}}/usr/local" ]] && return
    sudo -E mkdir -vp "latest-stage3-${1:-${DEFAULT_FLAVOR}}/usr/local/share/ca-certificates"
    sudo -E cp -v "/usr/local/share/ca-certificates/ca.crt" "latest-stage3-${1:-${DEFAULT_FLAVOR}}/usr/local/share/ca-certificates/ca.crt"
    sudo -E chroot "latest-stage3-${1:-${DEFAULT_FLAVOR}}" update-ca-certificates --fresh
    run_dounmounts "latest-stage3-${1:-${DEFAULT_FLAVOR}}"
}

function run_notest()
{
    FEATURES="-test" USE="-test" "${@}"
}

function run_gendebug()
{
    SKIP_UPDATES=1 NOSRC=1 FEATURES="-test installsources nostrip" USE="-test debug" CFLAGS="-O0 -ggdb3 -pipe" CXXFLAGS="${CFLAGS}" FCFLAGS="${CFLAGS}" FFLAGS="${CFLAGS}" "${@}"
}

function run_addspace()
{
    run_defsettings
    [[ -f "$(readlink -f "latest-stage3-${1:-${DEFAULT_FLAVOR}}").img" ]] || return
    run_dounmounts "latest-stage3-${1:-${DEFAULT_FLAVOR}}"
    dd status=progress if=/dev/zero of="$(readlink -f "latest-stage3-${1:-${DEFAULT_FLAVOR}}").img" bs=100M count="$(( 10 * "${2%%G}" ))" oflag=append,dsync conv=notrunc
    e2fsck -f "$(readlink -f "latest-stage3-${1:-${DEFAULT_FLAVOR}}").img"
    resize2fs "$(readlink -f "latest-stage3-${1:-${DEFAULT_FLAVOR}}").img"
}

function run_remanifest()
{
    run_defsettings
    run_domounts "latest-stage3-${1:-${DEFAULT_FLAVOR}}"
    (sudo -E git -C "latest-stage3-${1:-${DEFAULT_FLAVOR}}/var/db/repos/gentoo" ls-files --others --exclude-standard && sudo -E git -C "latest-stage3-${1:-${DEFAULT_FLAVOR}}/var/db/repos/gentoo" diff --name-only) | sort -u | grep -E ".*\.ebuild$" | while read line
    do
        sudo -E chroot "latest-stage3-${1:-${DEFAULT_FLAVOR}}" /bin/bash -c "cd /var/db/repos/gentoo/$(dirname "${line}") && GENTOO_MIRRORS=\"\" ebuild "$(basename "${line}")" manifest"
    done
    run_dounmounts "latest-stage3-${1:-${DEFAULT_FLAVOR}}"
}

function run_resetgit()
{
    run_defsettings
    run_domounts "latest-stage3-${1:-${DEFAULT_FLAVOR}}"
    sudo -E git -C "latest-stage3-${1:-${DEFAULT_FLAVOR}}/var/db/repos/gentoo" reset --hard
    sudo -E git -C "latest-stage3-${1:-${DEFAULT_FLAVOR}}/var/db/repos/gentoo" clean -fdx
    run_dounmounts "latest-stage3-${1:-${DEFAULT_FLAVOR}}"
}

function run_killprocs()
{
    sudo -E find /proc -mindepth 2 -maxdepth 2 -name root -type l | while read line
    do
        if [[ -L "${line}" && "$(sudo -E readlink "${line}")" =~ ^"$(realpath .)" ]]
        then
            sudo -E kill "${line//[^0-9]/}"
        fi
    done
}

function run_getpersonality()
{
    [[ -z "${ARCH}" ]] && unset ARCH
    ARCH="${1:-${ARCH:-$(portageq envvar ARCH)}}"
    case "${ARCH}" in
        arm)    echo "armv7l";;
        ppc)    echo "ppc32";;
        x86)    echo "i686";;
        *)      uname -m;;
    esac
}

function run_getdefaultflavor()
{
    [[ -z "${ARCH}" ]] && unset ARCH
    ARCH="${1:-${ARCH:-$(portageq envvar ARCH)}}"
    case "${ARCH}" in
        arm)    echo "armv7a_hardfp-openrc";;
        hppa)   echo "hppa2.0-openrc";;
        mips)   echo "mipsel3_n64-openrc";;
        riscv)  echo "rv64_lp64d-openrc";;
        s390)   echo "s390x-openrc";;
        sparc)  echo "sparc64-openrc";;
        x86)    echo "i686-ssemath-openrc";;
        *)    echo "${ARCH}-openrc";;
    esac
}

function run_applypr()
{
    [[ -z "${1}" ]] && return
    run_defsettings
    run_resetgit ${2:-}
    run_domounts "latest-stage3-${2:-${DEFAULT_FLAVOR}}"
    curl -sL "https://github.com/gentoo/gentoo/pull/${1}.patch" | sudo -E git -C "latest-stage3-${2:-${DEFAULT_FLAVOR}}/var/db/repos/gentoo" apply -
    run_remanifest ${2:-}
    run_dounmounts "latest-stage3-${2:-${DEFAULT_FLAVOR}}"
}
