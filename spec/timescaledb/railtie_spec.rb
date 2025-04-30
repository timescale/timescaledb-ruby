# frozen_string_literal: true

RSpec.describe Timescaledb::Railtie do
  let(:railtie) { described_class.new }

  describe "ActiveRecord integration" do
    it "extends ActiveRecord with ActsAsHypertable" do
      expect(ActiveRecord::Base.singleton_class.included_modules).to include(Timescaledb::ActsAsHypertable)
    end

    it "includes ConnectionHandling in ActiveRecord::Base" do
      expect(ActiveRecord::Base.included_modules).to include(Timescaledb::ConnectionHandling)
    end

    it "makes acts_as_hypertable available to models" do
      expect(Event).to respond_to(:acts_as_hypertable)
    end

    it "makes acts_as_hypertable? available to models" do
      expect(Event).to respond_to(:acts_as_hypertable?)
    end
  end

  describe "Rake tasks" do
    it "loads timescaledb rake tasks" do
      expect(Rake::Task.task_defined?("timescaledb:update_extension")).to be true
      expect(Rake::Task.task_defined?("timescaledb:version")).to be true
    end
  end
end 