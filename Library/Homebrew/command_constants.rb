# typed: strict
# frozen_string_literal: true

# Paths and aliases for built-in commands.
module Commands
  HOMEBREW_CMD_PATH = T.let((HOMEBREW_LIBRARY_PATH/"cmd").freeze, Pathname)
  HOMEBREW_DEV_CMD_PATH = T.let((HOMEBREW_LIBRARY_PATH/"dev-cmd").freeze, Pathname)
  # If you are going to change anything in below hash,
  # be sure to also update appropriate case statement in brew.sh
  HOMEBREW_INTERNAL_COMMAND_ALIASES = T.let({
    "ls"           => "list",
    "homepage"     => "home",
    "-S"           => "search",
    "up"           => "update",
    "ln"           => "link",
    "instal"       => "install", # gem does the same
    "uninstal"     => "uninstall",
    "post_install" => "postinstall",
    "rm"           => "uninstall",
    "remove"       => "uninstall",
    "abv"          => "info",
    "dr"           => "doctor",
    "--repo"       => "--repository",
    "environment"  => "--env",
    "--config"     => "config",
    "-v"           => "--version",
    "lc"           => "livecheck",
    "tc"           => "typecheck",
    "x"            => "exec",
  }.freeze, T::Hash[String, String])
end
