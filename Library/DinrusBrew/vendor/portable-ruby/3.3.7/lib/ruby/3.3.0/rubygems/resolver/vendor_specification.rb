# frozen_string_literal: true

##
# A VendorSpecification represents a gem that has been unpacked into a project
# and is being loaded through a gem dependencies file through the +path:+
# option.

class Gem::Resolver::VendorSpecification < Gem::Resolver::SpecSpecification
  def ==(other) # :nodoc:
    self.class === other &&
      @set  == other.set &&
      @spec == other.spec &&
      @source == other.source
  end

  ##
  # This is a null install as this gem was unpacked into a directory.
  # +options+ are ignored.

  def install(options = {})
    yield nil
  end
end
