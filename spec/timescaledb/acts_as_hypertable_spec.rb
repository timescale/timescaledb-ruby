RSpec.describe Timescaledb::ActsAsHypertable do

  before { travel_to Time.utc(2024, 12, 8, 12, 0, 0) }
  after { travel_back }

  {
    'last_month' => 1.month.ago.beginning_of_month,
    'at_edge_of_window' => 1.month.ago.end_of_month.end_of_day,
    'this_month' => 1.second.ago.beginning_of_month,
    'this_week' => 1.second.ago.beginning_of_week,
    'one_day_outside_window' => 2.days.ago.beginning_of_month,
    'last_week' => 1.week.ago.beginning_of_week,
  }.each do |identifier, created_at|
    let!("event_#{identifier}") {
      Event.create!(
        identifier: identifier,
        created_at: created_at
      )
    }
  end

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

  describe ".previous_month" do
    context "when there are database records that were created in the previous month" do
      it "returns all the records that were created in the previous month" do
        last_month = Event.previous_month.pluck(:identifier)
        expect(last_month).to include(*%w[last_month last_week])
      end
    end
  end

  describe ".previous_week" do
    context "when there are database records that were created in the previous week" do
      it "returns all the records that were created in the previous week" do
        last_week = Event.previous_week.pluck(:identifier)
        expect(last_week).to match_array(%w[at_edge_of_window last_week one_day_outside_window this_month])
      end
    end
  end

  describe ".this_month" do
    context "when there are database records that were created this month" do
      it "returns all the records that were created this month" do
        this_month = Event.this_month.pluck(:identifier)
        expect(this_month).to match_array(%w[at_edge_of_window one_day_outside_window this_month this_week])
      end
    end
  end

  describe ".this_week" do
    context "when there are database records that were created this week" do
      it "returns all the records that were created this week" do
        this_week = Event.this_week.pluck(:identifier)
        expect(this_week).to match_array(%w[this_week])
      end
    end
  end

  describe ".yesterday" do
    context "when there are database records that were created yesterday" do
      let!(:event_yesterday) {
        Event.create!(
          identifier: "yesterday",
          created_at: 1.day.ago
        )
      }

      it "returns all the records that were created yesterday" do
        yesterday = Event.yesterday.pluck(:identifier)
        expect(yesterday).to match_array(%w[yesterday])
      end
    end
  end

  describe ".today" do
    context "when there are database records that were created today" do
      it "returns all the records that were created today" do
        expect(Event.today).to be_empty
      end
    end
  end

  describe ".last_hour" do
    context "when there are database records that were created in the last hour" do
      it "returns all the records that were created in the last hour" do
        expect(Event.last_hour).to be_empty
      end
    end
  end
end
