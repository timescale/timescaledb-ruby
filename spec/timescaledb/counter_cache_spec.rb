require 'spec_helper'
require 'timescaledb/counter_cache'

RSpec.describe Timescaledb::CounterCache do
  before(:all) do
    ActiveRecord::Base.connection.drop_table(:comments, if_exists: true, force: :cascade)
    ActiveRecord::Base.connection.drop_table(:posts, if_exists: true, force: :cascade)

    ActiveRecord::Schema.define(version: 1) do
      create_table(:posts) do |t|
        t.string :title
        t.datetime :created_at, null: false
      end

      hypertable_options = {
        time_column: :created_at,
        chunk_time_interval: 1.week
      }

      create_table(:comments, id: false, hypertable: hypertable_options) do |t|
        t.string :content
        t.bigint :post_id
        t.datetime :created_at, null: false
        t.foreign_key :posts, column: :post_id
      end
      add_index :comments, [:post_id, :created_at, :content], unique: true
    end

    # Define the models
    class Post < ActiveRecord::Base
      include Timescaledb::ContinuousAggregatesHelper
      has_many :comments
    end

    class Comment < ActiveRecord::Base
      include Timescaledb::ContinuousAggregatesHelper
      include Timescaledb::CounterCache

      acts_as_hypertable segment_by: :post_id

      self.primary_key = :post_id # Use post_id as the primary key for ActiveRecord operations

      belongs_to_with_counter_cache :post, counter_cache: :timescaledb
    end

    Comment.create_continuous_aggregates(materialized_only: false)
  end

  after(:all) do
    # Clean up any existing tables and views
    if defined?(Comment)
      Comment.drop_continuous_aggregates
    end
    
    ActiveRecord::Base.connection.drop_table(:comments, if_exists: true, force: :cascade)
    ActiveRecord::Base.connection.drop_table(:posts, if_exists: true, force: :cascade)

    # Remove the model classes
    Object.send(:remove_const, :Comment) if defined?(Comment)
    Object.send(:remove_const, :Post) if defined?(Post)
  end

  describe 'counter cache setup' do
    before(:each) do
      Comment.setup_counter_aggregate(:post)
    end

    it 'sets up counter cache options' do
      expect(Comment.counter_cache_options[:post]).to include(
        timeframes: [:hour, :day],
        foreign_key: 'post_id'
      )
    end

    it 'creates continuous aggregates for counting' do
      aggregates = Timescaledb::ContinuousAggregate.where(
        view_name: ['count_by_comment_post_per_hour', 'count_by_comment_post_per_day']
      )
      expect(aggregates.count).to eq(2)
    end

    it 'sets up associations on the target class' do
      expect(Post.instance_methods).to include(
        :post_comment_count_per_hour_total,
        :post_comment_count_per_day_total
      )
    end
  end

  describe 'counter cache functionality' do
    around(:each) do |example|
      DatabaseCleaner.strategy = :truncation
      DatabaseCleaner.start
      Comment.setup_counter_aggregate(:post)
      example.run
      DatabaseCleaner.clean
    end

    let!(:post) { Post.create!(title: 'Test Post', created_at: Time.current) }
    
    it 'counts comments correctly' do
      # Create some comments
      3.times do
        Comment.create!(content: 'Test comment', post: post, created_at: Time.current)
      end

      # With materialized_only: false, we don't need to refresh the aggregates
      # The counts should be available immediately

      # Check the counts
      expect(post.post_comment_count_per_hour_total).to eq(3)
      expect(post.post_comment_count_per_day_total).to eq(3)
    end

    it 'updates counts when comments are deleted' do
      comment = Comment.create!(content: 'Test comment', post: post, created_at: Time.current)
      
      # With materialized_only: false, we don't need to refresh the aggregates
      # The counts should be available immediately
      
      expect(post.post_comment_count_per_hour_total).to eq(1)
      
      comment.destroy

      expect(post.post_comment_count_per_hour_total).to eq(0)
    end
  end
end 