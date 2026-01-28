# See https://docs.brew.sh/Command-Not-Found for current setup instructions
# License: MIT
# The license text can be found in Library/Homebrew/command-not-found/LICENSE

function fish_command_not_found
    set -l cmd $argv[1]
    set -l txt

    if not contains -- "$cmd" "-h" "--help" "--usage" "-?"
        set txt (brew which-formula --skip-update --explain $cmd 2> /dev/null)
    end

    if test -z "$txt"
        __fish_default_command_not_found_handler $cmd
    else
        string collect $txt
    end
end

function __fish_command_not_found_handler --on-event fish_command_not_found
    fish_command_not_found $argv
end
