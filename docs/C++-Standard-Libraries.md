---
last_review_date: "1970-01-01"
---

# C++ Standard Libraries

There are two C++ standard libraries supported by Apple compilers.

The default for 10.9 and later is **libc++**, which is also the default for `clang` on older
platforms when building C++11 code.

The default for 10.8 and earlier was **libstdc++**, supported by Apple GCC
compilers, GNU GCC compilers, and `clang`. This was marked deprecated with a
warning during compilation as of Xcode 8.

There are subtle incompatibilities between several of the C++ standard libraries,
so Homebrew will refuse to install software if a dependency was built with an
incompatible C++ library. It's recommended that you install the dependency tree
using a compatible compiler.

**If you've upgraded to 10.9 or later from an earlier version:** Because the default C++
standard library is now libc++, you may not be able to build software using
dependencies that you built on 10.8 or earlier. If you're reading this page because
you were directed here by a build error, you can most likely fix the issue if
you reinstall all the dependencies of the package you're trying to build.

Example install using GCC 9:

```sh
brew install gcc@9
brew install --cc=gcc-9 <formula>
```
