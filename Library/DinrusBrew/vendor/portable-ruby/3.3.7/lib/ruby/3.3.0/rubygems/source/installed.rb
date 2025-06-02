# frozen_string_literal: true

##
# Represents an installed gem.  This is used for dependency resolution.

class Gem::Source::Installed < Gem::Source
  def initialize # :nodoc:
    @uri = nil
  end

  ##
  # Installed sources sort before all other sources

  def <=>(other)
    case other
    when Gem::Source::Git,
         Gem::Source::Lock,
         Gem::Source::Vendor then
      -1
    when Gem::Source::Installed then
      0
    when Gem::Source then
      1
    end
  end

  ##
  # We don't need to download an installed gem

  def download(spec, path)
    nil
  end

  def pretty_print(q) # :nodoc:
    q.object_group(self) do
      q.text "[Installed]"
    end
  end
end
