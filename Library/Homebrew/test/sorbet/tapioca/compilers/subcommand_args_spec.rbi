# typed: strict

class TapiocaArgsTestCmd < Homebrew::AbstractCommand
  class InstallSubcommand < Homebrew::AbstractSubcommand; end
  class RemoveSubcommand < Homebrew::AbstractSubcommand; end
end
