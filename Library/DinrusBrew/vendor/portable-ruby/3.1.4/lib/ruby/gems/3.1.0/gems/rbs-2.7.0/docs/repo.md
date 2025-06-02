# Third-party RBS Repository

This is the spec of the directory structure for RBS files of gems without RBS files. It allows distributing RBS type definitions of gems separately from the `.gemspec` files so that the Ruby developers can type check their Ruby programs even if the dependent gems don't ship with their type definitions.

The spec includes:

* The directory structure, and
* The RBS file lookup rules given _repository root_, gem name, and version.

## Motivating Example

Assume there is a rubygem called `bug-free-doodle` and our application depends on the library. We are trying to type check our application and we need RBS files of `bug-free-doodle`. The problem is that the `bug-free-doodle` gem doesn't ship with RBS files. The type checkers cannot resolve the type of constant `Bug::Free::Doodle` and its methods.

One workaround is to add type definitions of the library in the application signatures.

```
# sig/polyfill/bug-free-doodle.rbs

module Bug
  module Free
    class Doodle
      attr_reader name: Symbol
      attr_reader strokes: Array[Stroke]

      def initialize: (name: Symbol) -> void
    end
  end
end
```

You may want to distribute the RBS file to anyone who needs it. Which version do we support? Testing it? How to load the RBS files? This is the spec you need!

### Third-party RBS repository

Make a directory (or you may want to `git init`) to put your _third party RBSs_.

```sh
$ make my-rbs      # Or you may want a git repository: git init my-rbs
$ cd my-rbs
$ mkdir gems
```

We call the `my-rbs/gems` directory _repository root_. Note that it is different from the root of the git repository. The RBS repository root is the directory that contains directories of gem names.

Make a directory for the gem and the version.

```sh
$ mkdir gems/bug-free-doodle
$ mkdir gems/bug-free-doodle/1.2.3
```

And copy the RBS file in it.

```sh
$ cp your-app/sig/polyfill/bug-free-doodle.rbs gems/bug-free-doodle/1.2.3
```

### Reading Third-party RBS

`rbs` command accepts `--repo` option which points to a _repository root_. You can specify `-r` option to let the command know which gems you want to load.

In this case, the _repository root_ is `./gems` and we are trying to load `bug-free-doodle` gem.

```sh
$ rbs --repo=gems -r bug-free-doodle paths
```

The `-r` option also accepts gem name with version.

```sh
$ rbs --repo=gems -r bug-free-doodle:1.2.3 paths
```

Note that the version resolution is not compatible with semantic versioning. It is optimistic. It resolves to some version unless no version for the gem is available.

## Directory Structure

There are directories for each gem under _repository root_. We also have directories for each version of each gem.

- $REPO_ROOT/bug-free-doodle/0.2.0
- $REPO_ROOT/bug-free-doodle/1.0
- $REPO_ROOT/bug-free-doodle/1.2.3
- $REPO_ROOT/bug-free-doodle/2.0

Note that we assume that we have git repositories for each RBS repository, and we have a directory at the root of the git repository for _repository root_.

So the git repository structure would be something like the following:

- /Gemfile
- /Gemfile.lock
- /README.md
- /LICENSE
- /gems/bug-free-doodle/1.2.3/bug-free-doodle.rbs

You should have `Gemfile` and `Gemfile.lock` to manage dependencies, `README.md` and `LICENSE` to documentation, and `gems` directory as _repository root_.

(We call _repository root_ `gems` in this doc, but the name can be anything you like.)

## Version Resolution

The version resolution in RBS is optimistic. We don't block loading RBS files for _incompatible_ version in terms of semantic versioning.

It tries to resolve version _n_ as follows:

1. It resolves to _m_ such that _m_ is the latest version available and _m_ <= _n_ holds.
2. It resolves to the oldest version when rule 1 cannot find version _m_.

If two versions, `0.4.0`, `1.0.0` are available for a gem:

| Requested version | Resolved version |
|-------------------|------------------|
| `0.3.0`           | `0.4.0` (Rule 2) |
| `0.4.0`           | `0.4.0`          |
| `0.5.0`           | `0.4.0`          |
| `1.0.0`           | `1.0.0`          |
| `2.0.0`           | `1.0.0`          |

This is not compatible with the concept of semantic versioning. We don't want to block users to load RBS even for incompatible versions of gems.

We believe this makes more sense because:

* Using (potentially) incompatible type definitions are better than no type definition.
* Users can stop loading RBS if incompatibility causes an issue and falling back to hand-written polyfills.


