# frozen_string_literal: true
#--
# ERB::Escape
#
# A subset of ERB::Util. Unlike ERB::Util#html_escape, we expect/hope
# Rails will not monkey-patch ERB::Escape#html_escape.
begin
  # We don't build the C extension for JRuby, TruffleRuby, and WASM
  if $LOAD_PATH.resolve_feature_path('erb/escape')
    require 'erb/escape'
  end
rescue LoadError # resolve_feature_path raises LoadError on TruffleRuby 22.3.0
end
unless defined?(ERB::Escape)
  module ERB::Escape
    def html_escape(s)
      CGI.escapeHTML(s.to_s)
    end
    module_function :html_escape
  end
end

#--
# ERB::Util
#
# A utility module for conversion routines, often handy in HTML generation.
module ERB::Util
  #
  # A utility method for escaping HTML tag characters in _s_.
  #
  #   require "erb"
  #   include ERB::Util
  #
  #   puts html_escape("is a > 0 & a < 10?")
  #
  # _Generates_
  #
  #   is a &gt; 0 &amp; a &lt; 10?
  #
  include ERB::Escape # html_escape
  module_function :html_escape
  alias h html_escape
  module_function :h

  #
  # A utility method for encoding the String _s_ as a URL.
  #
  #   require "erb"
  #   include ERB::Util
  #
  #   puts url_encode("Programming Ruby:  The Pragmatic Programmer's Guide")
  #
  # _Generates_
  #
  #   Programming%20Ruby%3A%20%20The%20Pragmatic%20Programmer%27s%20Guide
  #
  def url_encode(s)
    CGI.escapeURIComponent(s.to_s)
  end
  alias u url_encode
  module_function :u
  module_function :url_encode
end
