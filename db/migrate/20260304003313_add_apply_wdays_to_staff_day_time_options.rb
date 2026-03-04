class AddApplyWdaysToStaffDayTimeOptions < ActiveRecord::Migration[8.0]
  def change
    add_column :staff_day_time_options, :apply_wdays, :integer, array: true, default: [], null: false
    add_index  :staff_day_time_options, :apply_wdays, using: :gin
  end
end
