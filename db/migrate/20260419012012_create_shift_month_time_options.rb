class CreateShiftMonthTimeOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_month_time_options do |t|
      t.references :shift_month, null: false, foreign_key: true
      t.integer :shift_kind, null: false
      t.string :time_text, null: false
      t.integer :position, null: false, default: 0
      t.boolean :is_default, null: false, default: false

      t.timestamps
    end

    add_index :shift_month_time_options,
              [ :shift_month_id, :shift_kind, :position ],
              name: "idx_shift_month_time_options_on_month_kind_position"

    add_index :shift_month_time_options,
              [ :shift_month_id, :shift_kind, :is_default ],
              name: "idx_shift_month_time_options_on_month_kind_default"
  end
end
