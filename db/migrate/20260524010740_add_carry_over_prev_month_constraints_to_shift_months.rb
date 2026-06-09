class AddCarryOverPrevMonthConstraintsToShiftMonths < ActiveRecord::Migration[8.1]
  def change
    add_column :shift_months,
               :carry_over_prev_month_constraints,
               :boolean,
               null: false,
               default: false
  end
end
