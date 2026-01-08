# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_03_04_094036) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "timescaledb"
  enable_extension "timescaledb_toolkit"

  create_table "games", force: :cascade do |t|
    t.string "name"
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "plays", id: false, force: :cascade do |t|
    t.bigint "game_id", null: false
    t.integer "score"
    t.decimal "total_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "plays_created_at_idx", order: :desc
    t.index ["game_id"], name: "index_plays_on_game_id"
  end
  create_hypertable "plays", time_column: "created_at", chunk_time_interval: "1 day", compress_segmentby: "game_id", compress_orderby: "created_at ASC", compress_after: "P7D"
  create_continuous_aggregate("score_per_hours", <<-SQL, materialized_only: true, finalized: true)
    SELECT game_id,
      time_bucket('PT1H'::interval, created_at) AS bucket,
      avg(score) AS avg,
      max(score) AS max,
      min(score) AS min
     FROM plays
    GROUP BY game_id, (time_bucket('PT1H'::interval, created_at))
  SQL

end
