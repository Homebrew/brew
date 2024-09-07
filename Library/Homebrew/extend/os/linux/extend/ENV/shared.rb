# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SharedEnvExtension
  def effective_arch
    if @build_bottle && @bottle_arch
      @bottle_arch.to_sym
    elsif @build_bottle
      Hardware.oldest_cpu
    else
      :native
    end
  end
end
