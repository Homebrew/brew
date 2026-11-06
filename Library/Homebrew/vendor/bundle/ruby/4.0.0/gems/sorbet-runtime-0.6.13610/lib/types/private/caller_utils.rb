# frozen_string_literal: true
# typed: false

module T::Private::CallerUtils
  if Thread.respond_to?(:each_caller_location) # RUBY_VERSION >= "3.2"
    def self.find_caller
      skipped_first = false
      Thread.each_caller_location do |loc|
        unless skipped_first
          skipped_first = true
          next
        end

        next if loc.path&.start_with?("<internal:")

        return loc if yield(loc)
      end
      nil
    end
  else
    def self.find_caller
      caller_locations(2).find do |loc|
        !loc.path&.start_with?("<internal:") && yield(loc)
      end
    end
  end
end
