Use `fatrace` to record all file access during an `sbuild` run and find those
build dependencies which have their files never needed. You need superuser
privileges to run this script because of `fatrace`.

Run it like follows. In one terminal execute:

	$ ./findunusedbd.sh

In another run sbuild like this:

	$ sbuild \
		--chroot-setup-commands='/home/user/path/to/findunusedbd.sh chroot-setup' \
		--pre-realbuild-commands='/home/user/path/to/findunusedbd.sh pre-realbuild' \
		--post-realbuild-commands='/home/user/path/to/findunusedbd.sh post-realbuild'

This needs the --pre-realbuild-commands and --post-realbuild-commands to exist
which can be added to sbuild by applying
`0001-add-pre-realbuild-commands-and-post-realbuild-comman.patch` to it.

Any unused dependencies can then be found by investigating the file
`unneededdepends.list`.

The process can be automated for multiple packages by passing `dsc` files to
`run.sh`:

	$ ./run.sh ../mysources/*.dsc

This script will put the successful builds in `buildsuccess.list` and the found
unused build dependencies as `*.unusedbd` for each `dsc` file in the current
directory. A second pass on the successfully built `dsc` files will then check
each of the found unused build dependencies for their validity by replacing
them by an empty equivs package one after another. The results of that run are
stored in `*.unusedbd.real` files for each `dsc` file in the current directory.
The `run.sh` script expects to find `findunusedbd.sh` directly under `/home`.
Best try this out in a chroot to not mess with the host system.

Customize the schroot:

	$ sbuild-shell source:sid-amd64-sbuild
	$ echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/80-nocheckvaliduntil
	$ apt-get install equivs --no-install-recommends


Bugs:
 - when investigating which build dependencies are unused, virtual packages are not taken into account
 - maybe the fake equivs package can be built outside the schroot to avoid the additional dependencies for installing equivs
 - maybe equivs can be avoided altogether by finding a way to edit debian/control on the fly
