```
$ git clone "https://github.com/matoro/at-scripts"
$ cd at-scripts
$ mkdir "$(hostname -s)"
$ cd "$(hostname -s)"
$
$ # Put all settings you wish to keep permanently in here.  E.x.:
$ echo 'DEFAULT_FLAVOR="amd64-openrc"' >> settings.sh
$
$ # To test package list from bug
$ # Needs REPO_DIR set, defaults to "${HOME}/gentoo"
$ # Needs app-portage/nattka
$ ../dotest.sh 123456
$
$ # To test singular package atom
$ ../dotest.sh sys-apps/coreutils
$ ../dotest.sh dev-lang/python:3.12
$ ../dotest.sh =dev-python/pillow-10.3.0
$ ../dotest.sh '<x11-libs/pango-1.52.1'
$
$ # To test multiple package atoms
$ # Note the quotes, this is all a single argument
$ ../dotest.sh 'sys-apps/coreutils dev-lang/python:3.12 =dev-python/pillow-10.3.0 <x11-libs/pango-1.52.1'
$
$ # To test under a different stage3 flavor
$ ../dotest.sh sys-apps/systemd amd64-systemd
$
$ # To test on 32-bit
$ ARCH=x86 ../dotest.sh sys-devel/llvm i686-openrc
$ ARCH=arm ../dotest.sh sys-devel/llvm armv7a_hardfp-openrc
$ ARCH=ppc ../dotest.sh sys-devel/llvm ppc-openrc
$
$ # To test arbitrary architectures with qemu-user
$ ARCH=arm64 QEMU_BINARY=/usr/bin/qemu-aarch64-static ../dotest.sh dev-python/setuptools arm64-openrc
$
$ # When testing on non-ext4 filesystems
$ # This is autodetected for NFS, but may also be necessary
$ # on zfs or other exotic filesystems
$ NFS_WORKAROUND=1 ../dotest.sh app-editors/emacs
$
$ # Run tests in serial
$ MAKEOPTS="-j1" ../dotest.sh app-misc/tmux
```

To automatically apply package.use settings, put them in `../testreqs.package.use`.

To sync prepopulated distfiles without downloading them at merge time, put them in `../distfiles`.  Make sure permissions are correct.

To manually enter:
```
$ source ../functions.sh
$ run_domounts latest-default
$ sudo chroot latest-default /bin/bash
# source /etc/profile
# emerge ...
# exit
$ run_dounmounts latest-default
```

Non-default flavors (i.e., ones that do not correspond to your chosen `DEFAULT_FLAVOR`) will be e.g. `latest-stage3-amd64-systemd`, `latest-stage3-power9le-openrc`, etc.
