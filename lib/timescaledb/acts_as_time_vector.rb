module Timescaledb
  module ActsAsTimeVector
    def acts_as_time_vector(options = {})
      return if acts_as_time_vector?

      include Timescaledb::Toolkit::TimeVector

      class_attribute :time_vector_options, instance_writer: false
      define_default_scopes
      self.time_vector_options = options
    end

    def acts_as_time_vector?
      included_modules.include?(Timescaledb::ActsAsTimeVector)
    end
  end
end
