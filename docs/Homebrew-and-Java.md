---
last_review_date: "1970-01-01"
---

# Homebrew and Java

This page describes how Java is handled in Homebrew for users. Prospective formula authors may refer to existing Java-based formulae for examples of how to install packages written in Java via Homebrew, or visit the [Homebrew discussion forum](https://github.com/orgs/Homebrew/discussions) to seek guidance for their specific situation.

Most Java-based packages in Homebrew use the default Homebrew-provided `openjdk` package for their JDK dependency, although some packages with specific version requirements may use a versioned package such as `openjdk@8`.

## Executing commands using a different JDK

In situations where the user wants to override the use of the Homebrew-provided JDK, setting the `JAVA_HOME` environment variable will cause the specified location to be used as the Java home directory instead of the version of `openjdk` specified as a dependency.
