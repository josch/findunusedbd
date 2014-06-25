Standalone
----------

Use `fatrace` to record all file access during an `sbuild` run and find those
build dependencies which have their files never needed. You need superuser
privileges to run this script because of `fatrace`. You need to copy
`findunusedbd.sh` into `/home` so best run all of this inside a chroot to
prevent a mess.

Run it like follows:

	$ ./run.sh foo.dsc bar.dsc [...]

This will call sbuild like this for each `dsc` given:

	$ sbuild \
		--chroot-setup-commands='/home/findunusedbd.sh chroot-setup' \
		--pre-realbuild-commands='/home/findunusedbd.sh pre-realbuild' \
		--post-realbuild-commands='/home/findunusedbd.sh post-realbuild'

This needs the --pre-realbuild-commands and --post-realbuild-commands to exist
which can be added to sbuild by applying
`0001-add-pre-realbuild-commands-and-post-realbuild-comman.patch` to it.

The first pass will use `fatrace` to find build dependencies on packages with
files that are never used during the whole build. Since many of these are gonna
be meta packages, a second pass replaces the candidate package with a fake
equivs package of same name and version but without dependencies and tries to
rebuild.

Both passes are done for `--arch-all` and `--no-arch-all`. Any unused
dependencies can then be found by investigating the `*.arch-all.unusedbd.real`
and `*.no-arch-all.unusedbd.real`. The result from the former can permanently
be dropped from the `Build-Depends`. The result from the latter can be added to
`Build-Depends-Indep`.

Schroot setup
-------------

Create the schroot:

	$ sudo sbuild-createchroot --make-sbuild-tarball=/var/lib/sbuild/sid-amd64.tar.gz sid `mktemp -d` http://127.0.0.1:3142/snapshot.debian.org/archive/debian/20140601T000000Z

Enter the schroot:

	$ sbuild-shell source:sid-amd64-sbuild

Make apt ignore the `Valid-Until` header:

	$ echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/80-nocheckvaliduntil

Install `equivs`:

	$ apt-get install equivs --no-install-recommends

Bugs
----

 - maybe add list of packages whose files are never used but modify the build nevertheless (like `hardening-wrapper`)
 - use reproducible builds to check that the output is the same
 - when investigating which build dependencies are unused, virtual packages are not taken into account
 - maybe the fake equivs package can be built outside the schroot to avoid the additional dependencies for installing equivs
 - fatrace suffers from [bug#722901](https://bugs.debian.org/722901) which can be seen when trying to compile `lsof`

Feature Requests
----------------

 - build with `DEB_BUILD_OPTIONS=nocheck` once it is possible to add `<!profile.nocheck>`

License
-------

Consider everything in this repository in the public domain. It is a gross hack
and I do not care what you do with it.
