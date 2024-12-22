# typed: strict

module Cask
  class Cask
    def appdir; end

    def artifacts; end

    def auto_updates; end

    def caveats; end

    def conflicts_with; end

    def container; end

    def depends_on; end

    def desc; end

    def discontinued?; end

    def deprecated?; end

    def deprecation_date; end

    def deprecation_reason; end

    def deprecation_replacement; end

    def disabled?; end

    def disable_date; end

    def disable_reason; end

    def disable_replacement; end

    def homepage; end

    def language; end

    def languages; end

    def livecheck; end

    def livecheck_defined?; end

    def livecheckable?; end

    def name; end

    def on_system_blocks_exist?; end

    sig { returns(T.nilable(MacOSVersion)) }
    def on_system_block_min_os; end

    def sha256; end

    def staged_path; end

    sig { returns(T.nilable(::Cask::URL)) }
    def url; end

    def version; end
  end
end
