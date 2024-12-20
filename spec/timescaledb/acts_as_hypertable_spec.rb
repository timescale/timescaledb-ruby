RSpec.describe Timescaledb::ActsAsHypertable do


  describe ".acts_as_hypertable?" do
    context "when the model has not been declared as a hypertable" do
      it "returns false" do
        expect(NonHypertable.acts_as_hypertable?).to eq(false)
      end
    end

    context "when the model has been declared as a hypertable" do
      it "returns true" do
        expect(HypertableWithOptions.acts_as_hypertable?).to eq(true)
      end
    end
  end

  describe "#define_association_scopes" do
    context "when the model is a hypertable" do
      it "defines the association scopes" do
        expect(Event).to respond_to(:chunks)
        expect(Event).to respond_to(:hypertable)
        expect(Event).to respond_to(:jobs)
        expect(Event).to respond_to(:job_stats)
        expect(Event).to respond_to(:compression_settings)
        expect(Event).to respond_to(:caggs)
      end
    end
    context "when model skips association scopes" do
      it "does not define the association scopes" do
        expect(HypertableSkipAllScopes).not_to respond_to(:chunks)
        expect(HypertableSkipAllScopes).not_to respond_to(:hypertable)
        expect(HypertableSkipAllScopes).not_to respond_to(:jobs)
        expect(HypertableSkipAllScopes).not_to respond_to(:job_stats)
        expect(HypertableSkipAllScopes).not_to respond_to(:compression_settings)
        expect(HypertableSkipAllScopes).not_to respond_to(:continuous_aggregates)
      end
    end
  end

  describe 'when model skips default scopes' do
    context "when the model is a hypertable" do
      it "defines the association scopes" do
        expect(Event).to respond_to(:previous_month)
        expect(Event).to respond_to(:previous_week)
      end
    end

    it 'does not define the default scopes' do
      expect(HypertableSkipAllScopes).not_to respond_to(:previous_month)
      expect(HypertableSkipAllScopes).not_to respond_to(:previous_week)
      expect(HypertableSkipAllScopes).not_to respond_to(:this_month)
      expect(HypertableSkipAllScopes).not_to respond_to(:this_week)
      expect(HypertableSkipAllScopes).not_to respond_to(:yesterday)
      expect(HypertableSkipAllScopes).not_to respond_to(:today)
      expect(HypertableSkipAllScopes).not_to respond_to(:last_hour)
    end
  end

  describe ".hypertable_options" do
    context "when non-default options are set" do
      let(:model) { HypertableWithCustomTimeColumn }

      it "uses the non-default options" do
        expect(model.hypertable_options).not_to eq(Timescaledb.default_hypertable_options)
        expect(model.hypertable_options[:time_column]).to eq(:timestamp)
      end
    end

    context "when no options are set" do
      let(:model) { HypertableWithNoOptions }

      it "uses the default options" do
        expect(model.hypertable_options).to eq(Timescaledb.default_hypertable_options)
      end
    end
  end

  describe ".hypertable" do
    subject { Event.hypertable }

    it "has compression enabled by default" do
      is_expected.to be_compression_enabled
    end

    its(:num_dimensions) { is_expected.to eq(1) }
    its(:tablespaces) { is_expected.to be_nil }
    its(:hypertable_name) { is_expected.to eq(Event.table_name) }
  end
end
