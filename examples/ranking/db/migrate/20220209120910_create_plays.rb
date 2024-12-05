class CreatePlays < ActiveRecord::Migration[7.0]
  def change
    enable_extension("timescaledb") unless extensions.include? "timescaledb"
    hypertable_options = {
        time_column: 'created_at',
        chunk_time_interval: '1 day',
        compress_segmentby: 'game_id',
        compress_orderby: 'created_at',
        compress_after: '7 days'
    }
    create_table :plays, hypertable: hypertable_options, id: false do |t|
      t.references :game, null: false, foreign_key: false
      t.integer :score
      t.decimal :total_time

      t.timestamps
    end
  end
end
