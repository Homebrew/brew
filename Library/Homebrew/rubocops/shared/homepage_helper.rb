# typed: strict
# frozen_string_literal: true

require "rubocops/shared/helper_functions"

module RuboCop
  module Cop
    # This module performs common checks the `homepage` field in both formulae and casks.
    module HomepageHelper
      include HelperFunctions

      sig {
        params(
          type: Symbol, content: String,
          homepage_node: RuboCop::AST::Node,
          homepage_parameter_node: RuboCop::AST::Node
        ).void
      }
      def audit_homepage(type, content, homepage_node, homepage_parameter_node)
        @offensive_node = T.let(homepage_node, T.nilable(RuboCop::AST::Node))

        problem "#{type.to_s.capitalize} should have a homepage." if content.empty?

        @offensive_node = homepage_parameter_node
        problem "The homepage should start with http or https." unless content.match?(%r{^https?://})

        case content
          # Freedesktop is complicated to handle - It has SSL/TLS, but only on certain subdomains.
          # To enable https Freedesktop change the URL from http://project.freedesktop.org/wiki to
          # https://wiki.freedesktop.org/project_name.
          # "Software" is redirected to https://wiki.freedesktop.org/www/Software/project_name
        when %r{^http://((?:www|nice|libopenraw|liboil|telepathy|xorg)\.)?freedesktop\.org/(?:wiki/)?}
          if content.include?("Software")
            problem "Freedesktop homepages should be styled " \
                    "`https://wiki.freedesktop.org/www/Software/project_name`"
          else
            problem "Freedesktop homepages should be styled `https://wiki.freedesktop.org/project_name`"
          end

          # Google Code homepages should end in a slash
        when %r{^https?://code\.google\.com/p/[^/]+[^/]$}
          problem "Google Code homepages should end with a slash" do |corrector|
            corrector.replace(homepage_parameter_node.source_range, "\"#{content}/\"")
          end

        when %r{^http://([^/]*)\.(sf|sourceforge)\.net(/|$)}
          fixed = "https://#{Regexp.last_match(1)}.sourceforge.io/"
          problem "Sourceforge homepages should be `#{fixed}`" do |corrector|
            corrector.replace(homepage_parameter_node.source_range, "\"#{fixed}\"")
          end

        when /readthedocs\.org/
          fixed = content.sub("readthedocs.org", "readthedocs.io")
          problem "Readthedocs homepages should be `#{fixed}`" do |corrector|
            corrector.replace(homepage_parameter_node.source_range, "\"#{fixed}\"")
          end

        when %r{^https://github.com.*\.git$}
          problem "GitHub homepages should not end with .git" do |corrector|
            corrector.replace(homepage_parameter_node.source_range, "\"#{content.delete_suffix(".git")}\"")
          end

          # People will run into mixed content sometimes, but we should enforce and then add
          # exemptions as they are discovered. Treat mixed content on homepages as a bug.
          # Justify each exemptions with a code comment so we can keep track here.
          #
          # Compact the above into this list as we're able to remove detailed notations, etc over time.
        when
               # Check for `http://` GitHub homepage URLs, `https://` is preferred.
               # NOTE: Only check homepages that are repository pages, not `*.github.com` hosts.
               %r{^http://github\.com/},
               %r{^http://[^/]*\.github\.io/},

               # Savannah has full SSL/TLS support but no auto-redirect.
               # Doesn't apply to the download URLs, only the homepage.
               %r{^http://savannah\.nongnu\.org/},

               %r{^http://[^/]*\.sourceforge\.io/},
               # There's an auto-redirect here, but this mistake is incredibly common too.
               # Only applies to the homepage and subdomains for now, not the FTP URLs.
               %r{^http://((?:build|cloud|developer|download|extensions|git|
                               glade|help|library|live|nagios|news|people|
                               projects|rt|static|wiki|www)\.)?gnome\.org}x,
               %r{^http://[^/]*\.apache\.org},
               %r{^http://packages\.debian\.org},
               %r{^http://wiki\.freedesktop\.org/},
               %r{^http://((?:www)\.)?gnupg\.org/},
               %r{^http://ietf\.org},
               %r{^http://[^/.]+\.ietf\.org},
               %r{^http://[^/.]+\.tools\.ietf\.org},
               %r{^http://www\.gnu\.org/},
               %r{^http://code\.google\.com/},
               %r{^http://bitbucket\.org/},
               %r{^http://(?:[^/]*\.)?archive\.org}
          problem "Please use https:// for #{content}" do |corrector|
            corrector.replace(homepage_parameter_node.source_range, "\"#{content.sub("http", "https")}\"")
          end
        end
      end
    end
  end
end
