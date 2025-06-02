require 'test/unit/util/backtracefilter'

module Test
  module Unit
    class Notification
      include Util::BacktraceFilter
      attr_reader :test_name, :location, :message
      attr_reader :method_name

      SINGLE_CHARACTER = 'N'
      LABEL = "Notification"

      # Creates a new Notification with the given location and
      # message.
      def initialize(test_name, location, message, options={})
        @test_name = test_name
        @location = location
        @message = message
        @method_name = options[:method_name]
      end

      # Returns a single character representation of a notification.
      def single_character_display
        SINGLE_CHARACTER
      end

      def label
        LABEL
      end

      # Returns a brief version of the error description.
      def short_display
        "#{@test_name}: #{@message.split("\n")[0]}"
      end

      # Returns a verbose version of the error description.
      def long_display
        backtrace = filter_backtrace(location).join("\n")
        "#{label}: #{@message}\n#{@test_name}\n#{backtrace}"
      end

      # Overridden to return long_display.
      def to_s
        long_display
      end

      def critical?
        false
      end
    end

    class NotifiedError < StandardError
    end


    module TestCaseNotificationSupport
      class << self
        def included(base)
          base.class_eval do
            include NotificationHandler
          end
        end
      end

      # Notify some information.
      #
      # Example:
      #
      #     def test_notification
      #       notify("I'm here!")
      #       # Reached here
      #       notify("Special!") if special_case?
      #       # Reached here too
      #     end
      #
      # options:
      #
      #     :backtrace override backtrace.
      def notify(message, options={}, &block)
        backtrace = filter_backtrace(options[:backtrace] || caller)
        notification = Notification.new(name, backtrace, message,
                                        :method_name => @method_name)
        add_notification(notification)
      end

      private
      def add_notification(notification)
        current_result.add_notification(notification)
      end
    end

    module NotificationHandler
      class << self
        def included(base)
          base.exception_handler(:handle_notified_error)
        end
      end

      private
      def handle_notified_error(exception)
        return false unless exception.is_a?(NotifiedError)
        notification = Notification.new(name,
                                        filter_backtrace(exception.backtrace),
                                        exception.message)
        add_notification(notification)
        true
      end
    end

    module TestResultNotificationSupport
      attr_reader :notifications

      # Records a Test::Unit::Notification.
      def add_notification(notification)
        @notifications << notification
        notify_fault(notification)
        notify_changed
      end

      # Returns the number of notifications this TestResult has
      # recorded.
      def notification_count
        @notifications.size
      end

      private
      def initialize_containers
        super
        @notifications = []
        @summary_generators << :notification_summary
      end

      def notification_summary
        "#{notification_count} notifications"
      end
    end
  end
end
