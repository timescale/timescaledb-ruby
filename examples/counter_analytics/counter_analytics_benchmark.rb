require_relative '../../lib/timescaledb'
require 'benchmark'
require 'pp'

# ruby counter_analytics_benchmark.rb postgres://user:pass@host:port/db_name
# Default to a specific database if not provided
db_uri = ARGV.last || 'postgres://jonatasdp@0.0.0.0:5432/timescale' 
puts "Connecting to database: #{db_uri}"
ActiveRecord::Base.establish_connection(db_uri)

# This POC demonstrates the benefits of using TimescaleDB for counter analytics
# as described in the blog post: Counter Analytics in PostgreSQL: Beyond Simple Data Denormalization
# https://www.timescale.com/blog/counter-analytics-in-postgresql-beyond-simple-data-denormalization

# First, let's create our models
class User < ActiveRecord::Base
  has_many :posts
  has_many :comments
end

class Post < ActiveRecord::Base
  belongs_to :user
  has_many :comments
end

class Comment < ActiveRecord::Base
  extend Timescaledb::ActsAsHypertable
  include Timescaledb::CounterCache
  include Timescaledb::ContinuousAggregatesHelper
  
  acts_as_hypertable time_column: 'created_at'

  belongs_to :user
  
  belongs_to_with_counter_cache :post, counter_cache: :timescaledb
end

# Setup database schema
ActiveRecord::Base.connection.instance_exec do
  ActiveRecord::Base.logger = Logger.new(STDOUT)
  
  # Drop existing views and tables if they exist
  execute("DROP MATERIALIZED VIEW IF EXISTS count_by_user_per_hour CASCADE")
  execute("DROP MATERIALIZED VIEW IF EXISTS count_by_user_per_day CASCADE")
  execute("DROP MATERIALIZED VIEW IF EXISTS count_by_post_per_hour CASCADE")
  execute("DROP MATERIALIZED VIEW IF EXISTS count_by_post_per_day CASCADE")
  execute("DROP MATERIALIZED VIEW IF EXISTS count_by_comment_post_per_hour CASCADE")
  execute("DROP MATERIALIZED VIEW IF EXISTS count_by_comment_post_per_day CASCADE")
  execute("DROP MATERIALIZED VIEW IF EXISTS count_by_comment_user_per_hour CASCADE")
  execute("DROP MATERIALIZED VIEW IF EXISTS count_by_comment_user_per_day CASCADE")
  drop_table(:comments, if_exists: true)
  drop_table(:posts, if_exists: true)
  drop_table(:users, if_exists: true)
  
  # Create users table (not a hypertable)
  create_table(:users) do |t|
    t.string :name, null: false
    t.timestamps
  end
  
  # Create posts table (not a hypertable)
  create_table(:posts) do |t|
    t.string :title, null: false
    t.text :content
    t.references :user, null: false, foreign_key: true
    t.timestamps
  end
  
  # Create comments table as a hypertable
  hypertable_options = {
    time_column: 'created_at',
    chunk_time_interval: '1 day',
    compress_after: '7 days',
    compress_orderby: 'created_at',
  }
  
  create_table(:comments, id: false, hypertable: hypertable_options) do |t|
    t.text :content, null: false
    t.references :user, null: false, foreign_key: true
    t.references :post, null: false, foreign_key: true
    t.timestamps
  end
  
  # Add indexes for better performance
  add_index :comments, [:post_id, :created_at]
  add_index :comments, [:user_id, :created_at]
end

# Create continuous aggregates for counter cache
Comment.create_continuous_aggregates(materialized_only: false)

# Helper method to generate random strings
def random_string(length = 10)
  chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a
  Array.new(length) { chars.sample }.join
end

# Function to generate fake data
def generate_fake_data(num_users: 100, num_posts_per_user: 10, num_comments_per_post: 20)
  puts "Generating fake data..."
  
  # Create users
  users = []
  num_users.times do
    users << User.create!(name: "User #{random_string(5)}")
  end
  
  # Create posts for each user
  posts = []
  users.each do |user|
    num_posts_per_user.times do
      posts << {
        title: "Post #{random_string(8)}",
        content: "Content for post #{random_string(20)}",
        user_id: user.id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
  end
  Post.insert_all(posts, returning: nil)
  
  # Create comments for each post
  comments = []
  Post.find_each do |post|
    num_comments_per_post.times do
      comments << {
        content: "Comment #{random_string(15)}",
        user_id: users.sample.id,
        post_id: post.id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end
  end
  Comment.insert_all(comments, returning: nil)

  puts "Generated #{users.size} users, #{posts.size} posts, and #{comments.size} comments"

  return { users: users, posts: posts, comments: comments }
end

# Function to benchmark counter cache vs. direct count
def benchmark_counter_cache(data)
  puts "\nBenchmarking counter cache vs. direct count..."
  # Get a sample user and post
  user = User.all.sample
  post = Post.all.sample
  
  # Benchmark post's comment count
  puts "\nBenchmarking post's comment count:"
  Benchmark.bm do |x|
    x.report("Direct count:") do
      100.times { post.comments.count }
    end
    
    x.report("Counter cache daily:") do
      100.times { post.post_comment_count_per_day_total }
    end

    x.report("Counter cache hourly:") do
      100.times { post.post_comment_count_per_hour_total }
    end
  end
end

# Function to demonstrate the "dirty tuples" problem
def demonstrate_dirty_tuples(data)
  puts "\nDemonstrating the 'dirty tuples' problem..."
  
  # Get a sample post
  post = Post.all.sample
  
  # Count initial comments
  initial_count = post.comments.count
  puts "Initial comment count: #{initial_count}"
  
  # Add a new comment
  new_comment = Comment.create!(
    content: "New comment #{random_string(10)}",
    user: User.all.sample,
    post: post
  )
  
  # Count comments after adding
  after_add_count = post.comments.count
  puts "Comment count after adding: #{after_add_count}"
  
  Comment.where(post_id: new_comment.post_id,created_at: new_comment.created_at).delete_all
  
  # Count comments after deleting
  after_delete_count = post.comments.count
  puts "Comment count after deleting: #{after_delete_count}"
  
  # Show that the counter cache is still accurate
  puts "Counter cache: #{post.post_comment_count_per_day_total}"
  
  # Explain the dirty tuples problem
  puts "\nThe 'dirty tuples' problem:"
  puts "When using direct counts, PostgreSQL needs to scan the entire table to get an accurate count."
  puts "This becomes increasingly expensive as the table grows."
  puts "With TimescaleDB counter cache, we maintain pre-aggregated counts that are automatically updated."
  puts "This allows for much faster retrieval of counts, especially for large tables."
end

# Function to simulate high concurrency
def simulate_high_concurrency(data)
  puts "\nSimulating high concurrency..."
  
  # Get a sample post
  post = Post.all.sample
  
  # Initial count
  initial_count = post.post_comment_count_per_day_total
  puts "Initial comment count: #{initial_count}"
  
  # Simulate concurrent inserts
  puts "Simulating 100 concurrent inserts..."
  
  threads = []
  100.times do
    threads << Thread.new do
      Comment.create!(
        content: "Concurrent comment #{random_string(10)}",
        user: User.all.sample,
        post: post
      )
    end
  end
  
  # Wait for all threads to complete
  threads.each(&:join)
  
  # Count after concurrent inserts
  after_inserts_count = post.post_comment_count_per_day_total
  puts "Comment count after concurrent inserts: #{after_inserts_count}"
  
  # Simulate concurrent deletes
  puts "Simulating 50 concurrent deletes..."
  
  # Get 50 comments to delete
  comments_to_delete = Comment.where(post: post).limit(50).to_a
  
  threads = []
  comments_to_delete.each do |comment|
    threads << Thread.new do
      Comment.where(post_id: comment.post_id,created_at: comment.created_at).delete_all
    end
  end
  
  # Wait for all threads to complete
  threads.each(&:join)
  
  # Count after concurrent deletes
  after_deletes_count = post.post_comment_count_per_day_total
  puts "Comment count after concurrent deletes: #{after_deletes_count}"
  
  # Explain the benefits of TimescaleDB for high concurrency
  puts "\nBenefits of TimescaleDB for high concurrency:"
  puts "1. Continuous aggregates are updated via background jobs, not blocking operations"
  puts "2. Counter cache values are maintained accurately even under high concurrency"
  puts "3. Queries remain fast regardless of the number of concurrent operations"
end

# Main execution
puts "Counter Analytics Benchmark"
puts "=========================="

ActiveRecord::Base.logger = nil
# Generate fake data
data = generate_fake_data

# Benchmark counter cache vs. direct count
benchmark_counter_cache(data)

# Demonstrate the dirty tuples problem
demonstrate_dirty_tuples(data)

# Simulate high concurrency
simulate_high_concurrency(data)

puts "\nBenchmark completed!"
puts "This POC demonstrates how TimescaleDB's counter cache can significantly improve performance"
puts "for counting operations, especially in high-concurrency environments with large datasets."

ActiveRecord::Base.logger = Logger.new(STDOUT)
# Start a Pry session for interactive exploration
Pry.start 