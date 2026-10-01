---
last_review_date: "2026-07-18"
---

# External Commands

Homebrew supports executable extensions that can be invoked as `brew <command>` without modifying Homebrew/brew.
An external command can be installed on `PATH` or distributed in a tap.

External commands run with the user's privileges.
Review their source and use [tap trust](Tap-Trust.md) to trust only the required command or tap.

## Command types

An external command named `example` can use one of these executable filenames:

- `brew-example` for a shell script or another directly executable program
- `example.rb` in a tap's `cmd` directory for an `AbstractCommand` subclass
- `brew-example.rb` for a legacy Ruby command that runs when Homebrew requires the file

A directly executable command can use any suitable shebang and receives its remaining command-line arguments unchanged.
Its filename must be exactly `brew-example`, without a language extension such as `.sh`.
Homebrew sets variables including `HOMEBREW_PREFIX`, `HOMEBREW_CELLAR`, `HOMEBREW_REPOSITORY`, `HOMEBREW_LIBRARY_PATH` and `HOMEBREW_CACHE`.

A Ruby external command runs inside Homebrew and can access Homebrew internals.
Those internals can change without compatibility guarantees, so prefer public APIs and keep the extension tested against current Homebrew.

## Distribution in a tap

Place commands in the tap's `cmd` directory:

```text
homebrew-example/
└── cmd/
    ├── example.rb
    └── brew-other-example
```

Make each command executable before committing it.
See [How to Create and Maintain a Tap](How-to-Create-and-Maintain-a-Tap.md) for repository setup.

After tapping the repository, trust only the required command when whole-tap trust is unnecessary:

```sh
brew trust --command user/example/example
```

## Ruby command structure

A Ruby external command in a tap can use Homebrew's argument parser and `AbstractCommand` lifecycle.
Save this example as `cmd/example.rb` without a `brew-` prefix:

```ruby
# typed: strict
# frozen_string_literal: true

module Homebrew
  module Cmd
    class Example < AbstractCommand
      cmd_args do
        description "Describe what the command does."
        switch "--force", description: "Perform the operation without prompting."
        named_args :formula, min: 1
      end

      sig { override.void }
      def run
        args.named.to_formulae.each do |formula|
          puts formula.full_name
        end
      end
    end
  end
end
```

The class name is the command name converted to CamelCase.
Declare accepted positional arguments with `named_args` and access parsed options through `args`.
Use internal [commands](https://github.com/Homebrew/brew/tree/HEAD/Library/Homebrew/cmd) and [developer commands](https://github.com/Homebrew/brew/tree/HEAD/Library/Homebrew/dev-cmd) as current parser examples.

A legacy `brew-example.rb` command is only required and executed as a file.
Homebrew does not instantiate an `AbstractCommand` subclass or call its `run` method for that filename.

## Help output

Ruby commands using `cmd_args` receive consistent generated help.
A shell or Ruby script can alternatively provide comment-based help with lines beginning `#:`.
When a non-Ruby executable provides neither form, Homebrew may execute it with `--help` to obtain its own help output.
A legacy Ruby command without comment-based help receives generic help instead.

See the [argument parser API](/rubydoc/Homebrew/CLI/Parser.html) for the supported DSL.
