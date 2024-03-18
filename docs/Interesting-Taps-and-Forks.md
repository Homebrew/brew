# Interesting Taps and Forks

A [tap](Taps.md) is Homebrew-speak for a Git repository containing additional formulae.

Homebrew has the capability to add (and remove) multiple taps to your local installation with the `brew tap` and `brew untap` commands; run `man brew` in your terminal for usage information. The main repository at <https://github.com/Homebrew/homebrew-core>, often called `homebrew/core`, is always built-in.

Your taps are Git repositories located at `$(brew --repository)/Library/Taps`.

## Unsupported interesting taps

* [DomT4/autoupdate](https://github.com/DomT4/homebrew-autoupdate): An external command to automatically run `brew update` (and optionally `brew upgrade` or `brew cleanup`) in the background with `launchd`.

* [homebrew-ffmpeg/ffmpeg](https://github.com/homebrew-ffmpeg/homebrew-ffmpeg): A tap for FFmpeg with additional options, including nonfree additions.

* [denji/nginx](https://github.com/denji/homebrew-nginx): A tap for NGINX modules, intended for its `nginx-full` formula which includes more module options.

* [InstantClientTap/instantclient](https://github.com/InstantClientTap/homebrew-instantclient): A tap for Oracle Instant Client.

* [osx-cross/avr](https://github.com/osx-cross/homebrew-avr): GNU AVR toolchain (Libc, compilers and other tools for Atmel MCUs), useful for Arduino hackers and AVR programmers.

* [petere/postgresql](https://github.com/petere/homebrew-postgresql): Allows installing multiple PostgreSQL versions in parallel.

* [osrf/simulation](https://github.com/osrf/homebrew-simulation): Tools for robotics simulation.

* [brewsci/bio](https://github.com/brewsci/homebrew-bio): Bioinformatics formulae.

* [davidchall/hep](https://github.com/davidchall/homebrew-hep): High energy physics formulae.

* [lifepillar/appleii](https://github.com/lifepillar/homebrew-appleii): Formulae for vintage Apple emulation.

* [gromgit/fuse](https://github.com/gromgit/homebrew-fuse): macOS FUSE formulae that are no longer available in `homebrew/core`.

* [cloudflare/cloudflare](https://github.com/cloudflare/homebrew-cloudflare): Formulae for the applications by Cloudflare, including curl with HTTP/3 support.

* [apple/apple](https://github.com/apple/homebrew-apple): Formulae from Apple, including the Game Porting Toolkit.

## Unsupported interesting forks

* [mistydemeo/tigerbrew](https://github.com/mistydemeo/tigerbrew): Experimental Tiger/Leopard PowerPC version.
