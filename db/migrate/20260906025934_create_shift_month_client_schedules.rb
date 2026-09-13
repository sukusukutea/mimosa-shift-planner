class CreateShiftMonthClientSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :shift_month_client_schedules do |t|
      t.references :shift_month, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :service_kind, null: false
      t.integer :source, null: false, default: 0
      t.string :client_display_name, null: false

      t.timestamps
    end

    add_index :shift_month_client_schedules,
              [:shift_month_id, :date, :service_kind],
              name: "index_shift_month_client_schedules_on_date_and_kind"

    add_index :shift_month_client_schedules,
              [:shift_month_id, :client_id, :date, :service_kind],
              unique: true,
              name: "index_shift_month_client_schedules_on_unique_client_service"
  end
end
