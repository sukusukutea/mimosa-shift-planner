class AddCountFixedInWeekdayRequirementsToStaffs < ActiveRecord::Migration[8.1]
  def change
    add_column :staffs, :count_fixed_in_weekday_requirements, :boolean, null: false, default: true
  end
end
