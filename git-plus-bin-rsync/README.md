Git is great, but it sucks if you want to store large
binaryies, and don't really need the history of everything
forever for those binaries.

We only really care about what is current with firmware, so
this manages syncing that within a git repo.  The script really
has nothing to do with git, it's just a sub directory that's
put inside the repo which isn't part of it.
