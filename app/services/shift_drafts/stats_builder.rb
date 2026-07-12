module ShiftDrafts
  class StatsBuilder
    def initialize(shift_month:, staff_by_id:, draft:, carry_over_state: {})
      @shift_month = shift_month
      @staff_by_id = staff_by_id
      @draft = draft
      @carry_over_state = carry_over_state || {}

      @first_week_dayish_counts_by_staff_id =
        @carry_over_state.each_with_object(Hash.new(0)) do |(staff_id, state), hash|
          hash[staff_id.to_i] = state[:first_week_dayish_count].to_i
        end

      @first_week_paid_leave_counts_by_staff_id =
        @carry_over_state.each_with_object(Hash.new(0)) do |(staff_id, state), hash|
          hash[staff_id.to_i] = state[:first_week_paid_leave_count].to_i
        end
    end

    def call
      month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
      month_end   = month_begin.end_of_month
      dates = (month_begin..month_end).to_a
      date_keys = dates.map(&:iso8601)
      staff_ids = @staff_by_id.keys

      counts = Hash.new { |h, k| h[k] = Hash.new(0) } # counts[staff_id][:day] += 1 など kindの回数

      dayish_by_staff_and_date = Hash.new { |h, k| h[k] = {} } # [staff_id][Date] = true

      date_keys.each do |dkey|
        date = Date.iso8601(dkey)
        kinds = @draft[dkey] || {}

        kinds.each do |kind_sym_or_str, rows|
          kind = kind_sym_or_str.to_sym
          next unless ShiftMonth::SHIFT_KINDS.include?(kind)

          Array(rows).each do |row|
            staff_id = extract_staff_id(row)
            next if staff_id.nil?

            sid = staff_id.to_i
            counts[sid][kind] += 1

            if [ :day, :early, :late ].include?(kind)
              dayish_by_staff_and_date[sid][date] = true
            end
          end
        end
      end

      total_days = date_keys.length
      worked_days = Hash.new(0)
      paid_leave_counts = Hash.new(0)
      paid_leave_by_staff_and_date = Hash.new { |h, k| h[k] = {} }

      date_keys.each do |dkey|
        kinds = @draft[dkey] || {}
        assigned_ids =
          kinds.values
               .flat_map { |rows| Array(rows).map { |row| extract_staff_id(row) } }
               .compact
               .uniq

        prev_key = (Date.iso8601(dkey) - 1).iso8601
        prev = @draft[prev_key] || {}
        prev_night_first = Array(prev["night"] || []).first
        night_off_id = extract_staff_id(prev_night_first)

        assigned_ids << night_off_id if night_off_id.to_i > 0

        assigned_ids = assigned_ids.compact.uniq

        assigned_ids.each do |sid|
          worked_days[sid] += 1
        end
      end


      @shift_month.staff_holiday_requests
                  .where(date: month_begin..month_end, holiday_type: :paid_leave)
                  .find_each do |request|
          sid = request.staff_id.to_i

          paid_leave_counts[sid] += 1
          paid_leave_by_staff_and_date[sid][request.date] = true
        end

      required_holidays = @shift_month.holiday_days.to_i

      staff_ids.sort_by { |sid|
        s = @staff_by_id[sid]
        [ s.last_name_kana, s.first_name_kana ]
      }
      .map { |sid|
        staff = @staff_by_id[sid]
        holiday_count = total_days - worked_days[sid] - paid_leave_counts[sid]
        is_free = staff.respond_to?(:workday_constraint) && staff.workday_constraint == "free"
        holiday_shortage = is_free && required_holidays > 0 && holiday_count.to_i < required_holidays
        weekly_shortage_weeks = weekly_shortage_weeks_for(
          staff,
          dates,
          dayish_by_staff_and_date,
          paid_leave_by_staff_and_date
        )
        weekly_shortage = weekly_shortage_weeks.any?

        {
          staff: staff,
          day:   counts[sid][:day],
          early: counts[sid][:early],
          late:  counts[sid][:late],
          night: counts[sid][:night],
          holiday: holiday_count,
          paid_leave: paid_leave_counts[sid],
          holiday_shortage: holiday_shortage,
          weekly_shortage: weekly_shortage,
          weekly_shortage_weeks: weekly_shortage_weeks
        }
      }
    end

    private

    def extract_staff_id(row)
      return nil if row.nil?

      if row.is_a?(Hash)
        v = row["staff_id"] || row[:staff_id] # v:valueの略
        v.present? ? v.to_i : nil
      else
        row.present? ? row.to_i : nil
      end
    end

    def week_ranges_in_month(dates)
      return [] if dates.blank?

      first = dates.first.beginning_of_week(:monday)
      last  = dates.last.end_of_week(:monday)

      ranges = []
      d = first
      while d <= last
        wb = d
        we = d + 6
        ranges << (wb..we)
        d += 7
      end
      ranges
    end

    def first_week_dates?(dates_in_week, all_dates)
      month_begin = all_dates.first
      return false if month_begin.monday?

      dates_in_week.first == month_begin
    end

    def weekly_shortage_weeks_for(staff, dates, dayish_by_staff_and_date, paid_leave_by_staff_and_date)
      return [] unless staff&.workday_constraint.to_s == "weekly"

      limit = staff.weekly_workdays.to_i
      return [] if limit <= 0

      sid = staff.id.to_i
      weeks = week_ranges_in_month(dates)
      month_end = dates.last

      shortage = []
      weeks.each_with_index do |range, idx|
        # 月外の日は除外（= 月の中の該当日だけ数える）
        in_month_dates = dates.select { |d| range.cover?(d) }
        next if in_month_dates.empty?

        # 月末を含む週で、月内の日付が7日揃わない週は weekly 未達判定から除外
        next if in_month_dates.include?(month_end) && in_month_dates.size < 7

        actual =
          in_month_dates.count do |d|
            dayish_by_staff_and_date.dig(sid, d) == true
          end

        paid_leave_count =
          in_month_dates.count do |d|
            paid_leave_by_staff_and_date.dig(sid, d) == true
          end

        if first_week_dates?(in_month_dates, dates)
          actual += @first_week_dayish_counts_by_staff_id[sid].to_i
          paid_leave_count += @first_week_paid_leave_counts_by_staff_id[sid].to_i
        end

        required_workdays = [ limit - paid_leave_count, 0 ].max

        shortage << (idx + 1) if actual < required_workdays
      end

      shortage
    end
  end
end
