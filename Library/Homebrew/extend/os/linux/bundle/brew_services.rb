# typed: strict
# frozen_string_literal: true

module OS
  module Linux
    module Bundle
      module BrewServices
        module ClassMethods
          sig { returns(T::Array[String]) }
          def started_services_without_daemon_manager
            Homebrew::Bundle::Brew::Services.opoo "Skipping `brew services list` due to missing systemctl"
            []
          end
        end
      end
    end
  end
end

Homebrew::Bundle::Brew::Services.singleton_class.prepend(OS::Linux::Bundle::BrewServices::ClassMethods)
