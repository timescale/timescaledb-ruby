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
        aggregate_failures do
          expect(model.hypertable_options).not_to eq(Timescaledb.default_hypertable_options)
          expect(model.hypertable_options[:time_column]).to eq(:timestamp)
        end
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
      let(:event_last_month) {
        Event.create!(
          identifier: "last_month",
          payload: {name: "bar", value: 2},
          created_at: 1.month.ago
        )
      }
      let(:event_one_day_outside_window) {
        Event.create!(
          identifier: "one_day_outside_window",
          payload: {name: "bax", value: 2},
          created_at: 1.month.ago.beginning_of_month - 1.day
        )
      }
      let(:event_at_edge_of_window) {
        Event.create!(
          identifier: "at_edge_of_window",
          payload: {name: "bax", value: 2},
          created_at: 1.month.ago.end_of_month
        )
      }
      let(:event_this_month) {
        Event.create!(
          identifier: "this_month",
          payload: {name: "bax", value: 2},
          created_at: Time.now
        )
      }
      it "returns all the records that were created in the previous month" do
        aggregate_failures do
          expect(Event.previous_month).to match_array([event_last_month])
          expect(Event.previous_month)
            .not_to include(event_one_day_outside_window, event_this_month, event_at_edge_of_window)
        end
      end
    end

    context "when there are no records created in the previous month" do
      it "returns an empty array" do
        expect(Event.previous_month).to eq([])
      end
    end
  end

  describe ".previous_week" do
    context "when there are database records that were created in the previous week" do
      let(:event_last_week) {
        Event.create!(
          identifier: "last_week",
          payload: {name: "bar", value: 2},
          created_at: 1.week.ago
        )
      }
      let(:event_one_day_outside_window) {
        Event.create!(
          identifier: "one_day_outside_window",
          payload: {name: "bax", value: 2},
          created_at: 1.week.ago.beginning_of_week - 1.day
        )
      }
      let(:event_at_edge_of_window) {
        Event.create!(
          identifier: "at_edge_of_window",
          payload: {name: "bax", value: 2},
          created_at: 1.week.ago.end_of_week
        )
      }
      let(:event_this_week) {
        Event.create!(
          identifier: "this_week",
          payload: {name: "bax", value: 2},
          created_at: Time.now
        )
      }

      it "returns all the records that were created in the previous week" do
        aggregate_failures do
          expect(Event.previous_week).to match_array([event_last_week])
          expect(Event.previous_week)
            .not_to include(event_one_day_outside_window, event_this_week, event_at_edge_of_window)
        end
      end
    end

    context "when there are no records created in the previous week" do
      it "returns an empty array" do
        expect(Event.previous_week).to eq([])
      end
    end
  end

  describe ".this_month" do
    context "when there are database records that were created this month" do
      let(:event_this_month) {
        Event.create!(
          identifier: "this_month",
          payload: {name: "bar", value: 2},
          created_at: Time.now.beginning_of_month
        )
      }
      let(:event_one_day_outside_window) {
        Event.create!(
          identifier: "one_day_outside_window",
          payload: {name: "bax", value: 2},
          created_at: Time.now.beginning_of_month - 1.day
        )
      }
      let(:event_at_edge_of_window) {
        Event.create!(
          identifier: "at_edge_of_window",
          payload: {name: "bax", value: 2},
          created_at: Time.now.end_of_month
        )
      }
      let(:event_last_month) {
        Event.create!(
          identifier: "last_month",
          payload: {name: "bax", value: 2},
          created_at: 1.month.ago
        )
      }
      let(:event_next_month) {
        Event.create!(
          identifier: "next_month",
          payload: {name: "bax", value: 2},
          created_at: 1.month.from_now
        )
      }

      it "returns all the records that were created this month" do
        aggregate_failures do
          expect(Event.this_month).to match_array([event_this_month])
          expect(Event.this_month)
            .not_to include(event_one_day_outside_window, event_last_month, event_next_month, event_at_edge_of_window)
        end
      end
    end

    context "when there are no records created this month" do
      it "returns an empty array" do
        expect(Event.this_month).to eq([])
      end
    end
  end

  describe ".this_week" do
    context "when there are database records that were created this week" do
      let(:event_this_week) {
        Event.create!(
          identifier: "this_week",
          payload: {name: "bar", value: 2},
          created_at: Time.now
        )
      }
      let(:event_one_day_outside_window) {
        Event.create!(
          identifier: "one_day_outside_window",
          payload: {name: "bax", value: 2},
          created_at: 1.week.ago.beginning_of_week - 1.day
        )
      }
      let(:event_at_edge_of_window) {
        Event.create!(
          identifier: "at_edge_of_window",
          payload: {name: "bax", value: 2},
          created_at: 1.week.ago.end_of_week - 1.minute
        )
      }
      let(:event_last_week) {
        Event.create!(
          identifier: "last_week",
          payload: {name: "bax", value: 2},
          created_at: 1.week.ago
        )
      }
      let(:event_next_week) {
        Event.create!(
          identifier: "next_week",
          payload: {name: "bax", value: 2},
          created_at: 1.week.from_now
        )
      }

      it "returns all the records that were created this week" do
        aggregate_failures do
          expect(Event.this_week).to match_array([event_this_week, event_at_edge_of_window])
          expect(Event.this_week)
            .not_to include(event_one_day_outside_window, event_last_week, event_next_week)
        end
      end
    end

    context "when there are no records created this week" do
      it "returns an empty array" do
        expect(Event.this_week).to eq([])
      end
    end
  end

  describe ".yesterday" do
    context "when there are database records that were created yesterday" do
      let(:event_yesterday) {
        Event.create!(
          identifier: "yesterday",
          payload: {name: "bar", value: 2},
          created_at: 1.day.ago
        )
      }
      let(:event_one_day_outside_window) {
        Event.create!(
          identifier: "one_day_outside_window",
          payload: {name: "bax", value: 2},
          created_at: 2.days.ago
        )
      }
      let(:event_at_edge_of_window) {
        Event.create!(
          identifier: "at_edge_of_window",
          payload: {name: "bax", value: 2},
          created_at: 1.day.ago.midnight
        )
      }
      let(:event_today) {
        Event.create!(
          identifier: "today",
          payload: {name: "bax", value: 2},
          created_at: Time.now
        )
      }

      it "returns all the records that were created yesterday" do
        aggregate_failures do
          expect(Event.yesterday).to match_array([event_yesterday, event_at_edge_of_window])
          expect(Event.yesterday)
            .not_to include(event_one_day_outside_window, event_today)
        end
      end
    end

    context "when there are no records created yesterday" do
      it "returns an empty array" do
        expect(Event.yesterday).to eq([])
      end
    end
  end

  describe ".today" do
    context "when there are database records that were created today" do
      let(:event_today) {
        Event.create!(
          identifier: "today",
          payload: {name: "bar", value: 2},
          created_at: 1.minute.ago
        )
      }
      let(:event_one_day_outside_window) {
        Event.create!(
          identifier: "one_day_outside_window",
          payload: {name: "bax", value: 2},
          created_at: 2.days.ago
        )
      }
      let(:event_at_edge_of_window) {
        Event.create!(
          identifier: "at_edge_of_window",
          payload: {name: "bax", value: 2},
          created_at: Time.now.end_of_day - 1.minute
        )
      }

      it "returns all the records that were created today" do
        aggregate_failures do
          expect(Event.today).to match_array([event_today])
          expect(Event.today).not_to include(event_one_day_outside_window, event_at_edge_of_window)
        end
      end
    end

    context "when there are no records created today" do
      it "returns an empty array" do
        expect(Event.today).to eq([])
      end
    end
  end

  describe ".last_hour" do
    context "when there are database records that were created in the last hour" do
      let(:event_last_hour) {
        Event.create!(
          identifier: "last_hour",
          payload: {name: "bar", value: 2},
          created_at: 1.minute.ago
        )
      }
      let(:event_one_minute_outside_window) {
        Event.create!(
          identifier: "one_minute_outside_window",
          payload: {name: "bax", value: 2},
          created_at: 1.hour.ago - 1.minute
        )
      }
      let(:event_at_edge_of_window) {
        Event.create!(
          identifier: "at_edge_of_window",
          payload: {name: "bax", value: 2},
          created_at: Time.now.end_of_hour
        )
      }

      it "returns all the records that were created today" do
        aggregate_failures do
          expect(Event.last_hour).to match_array([event_last_hour, event_at_edge_of_window])
          expect(Event.last_hour).not_to include(event_one_minute_outside_window)
        end
      end
    end

    context "when there are no records created in the last hour" do
      it "returns an empty array" do
        expect(Event.last_hour).to eq([])
      end
    end
  end
end
