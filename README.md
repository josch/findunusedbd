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

Bugs: when investigating which build dependencies are unused, virtual packages
are not taken into account.
