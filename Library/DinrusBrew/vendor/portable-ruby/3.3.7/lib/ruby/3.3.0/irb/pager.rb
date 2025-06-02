# frozen_string_literal: true

module IRB
  # The implementation of this class is borrowed from RDoc's lib/rdoc/ri/driver.rb.
  # Please do NOT use this class directly outside of IRB.
  class Pager
    PAGE_COMMANDS = [ENV['RI_PAGER'], ENV['PAGER'], 'less', 'more'].compact.uniq

    class << self
      def page_content(content, **options)
        if content_exceeds_screen_height?(content)
          page(**options) do |io|
            io.puts content
          end
        else
          $stdout.puts content
        end
      end

      def page(retain_content: false)
        if should_page? && pager = setup_pager(retain_content: retain_content)
          begin
            pid = pager.pid
            yield pager
          ensure
            pager.close
          end
        else
          yield $stdout
        end
      # When user presses Ctrl-C, IRB would raise `IRB::Abort`
      # But since Pager is implemented by running paging commands like `less` in another process with `IO.popen`,
      # the `IRB::Abort` exception only interrupts IRB's execution but doesn't affect the pager
      # So to properly terminate the pager with Ctrl-C, we need to catch `IRB::Abort` and kill the pager process
      rescue IRB::Abort
        Process.kill("TERM", pid) if pid
        nil
      rescue Errno::EPIPE
      end

      private

      def should_page?
        IRB.conf[:USE_PAGER] && STDIN.tty? && (ENV.key?("TERM") && ENV["TERM"] != "dumb")
      end

      def content_exceeds_screen_height?(content)
        screen_height, screen_width = begin
          Reline.get_screen_size
        rescue Errno::EINVAL
          [24, 80]
        end

        pageable_height = screen_height - 3 # leave some space for previous and the current prompt

        # If the content has more lines than the pageable height
        content.lines.count > pageable_height ||
          # Or if the content is a few long lines
          pageable_height * screen_width < Reline::Unicode.calculate_width(content, true)
      end

      def setup_pager(retain_content:)
        require 'shellwords'

        PAGE_COMMANDS.each do |pager_cmd|
          cmd = Shellwords.split(pager_cmd)
          next if cmd.empty?

          if cmd.first == 'less'
            cmd << '-R' unless cmd.include?('-R')
            cmd << '-X' if retain_content && !cmd.include?('-X')
          end

          begin
            io = IO.popen(cmd, 'w')
          rescue
            next
          end

          if $? && $?.pid == io.pid && $?.exited? # pager didn't work
            next
          end

          return io
        end

        nil
      end
    end
  end
end
