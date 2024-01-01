# MD5 and SHA-1 Deprecation

In early 2015 Homebrew started the process of deprecating _SHA1_ for package
integrity verification. Since then formulae under the Homebrew organisation
have been migrated to use _SHA-256_ for verification; this includes both source
packages and our precompiled packages (bottles).

Homebrew has since stopped supporting _SHA1_ and _MD5_ entirely.
_MD5_ checksums were removed from core formulae in 2012 and as of April 2015
installing a formula verified by _MD5_ is actively blocked.

We removed _SHA1_ support in **November 2016**,
21 months after we started warning people to move away from it for verification.
This is enforced in the same way _MD5_ is, by blocking the installation of that
individual formula until the checksum is migrated.

This means custom taps, local custom formulae, etc. need to be migrated to use
_SHA-256_ before you can install them.
