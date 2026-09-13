class AddActiveToShiftMonthClientSchedules < ActiveRecord::Migration[8.1]
  def change
    add_column :shift_month_client_schedules, :active, :boolean, null: false, default: true
  end
end
