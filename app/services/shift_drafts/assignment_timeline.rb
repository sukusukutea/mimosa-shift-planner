module ShiftDrafts
  class AssignmentTimeline
    attr_reader :night_off_conflicts

    def initialize(dates:, staff_by_id:, assignments_hash:)
      @dates = dates
      @staff_by_id = staff_by_id
      @assignments_hash = assignments_hash
      @night_off_conflicts = Hash.new { |h, k| h[k] = [] } # staff_id => [date, ...]
    end

    def call
      @timeline = build_timeline
    end

    def consecutive_day_count_before(staff_id, date) # date: Date(この日に割当てるか判断したい日)
      daily = @timeline[staff_id]
      return 0 unless daily

      count = 0
      idx = @dates.index(date)
      return 0 unless idx

      (@dates[0...idx].reverse).each do |d|
        kind = daily[d]

        if [ :day, :early, :late ].include?(kind)
          count += 1
        else
          break
        end
      end

      count
    end

    def forbidden_to_work_on?(staff_id, date, kind)
      return false unless [ :day, :early, :late ].include?(kind)

      daily = @timeline[staff_id]
      return false unless daily

      idx = @dates.index(date)
      return false unless idx

      # 直前までの連続日勤系数
      consec = 0
      (@dates[0...idx].reverse).each do |d|
        k = daily[d]
        if [ :day, :early, :late ].include?(k)
          consec += 1
        else
          break
        end
      end

      if consec >= 5
        true
      else
        false
      end
    end

    private

    def build_timeline
      timeline = init_empty_timeline

      fill_assignments!(timeline)
      mark_night_off!(timeline)

      timeline
    end

    def init_empty_timeline # ここでstaff_id × 全日付= :off　ができる
      @staff_by_id.keys.index_with do |_staff_id|
        @dates.index_with { :off }
      end
    end

    def fill_assignments!(timeline)
      @assignments_hash.each do |date_str, kinds_hash|
        date = Date.iso8601(date_str)
        next unless @dates.include?(date)

        kinds_hash.each do |kind, rows|
          rows.each do |row|
            staff_id = (row["staff_id"] || row[:staff_id]).to_i
            next if staff_id.zero?
            next unless timeline.key?(staff_id)

            timeline[staff_id][date] = kind.to_sym
          end
        end
      end
    end

    def mark_night_off!(timeline)
      timeline.each do |staff_id, daily|
        @dates.each_with_index do |date, idx|
          next unless daily[date] == :night

          next_date = @dates[idx + 1]
          next unless next_date

          # 夜勤の翌日が未割当なら night_off
          if daily[next_date] == :off
            daily[next_date] = :night_off
          else
            # 夜勤明け日に別勤務が入っている
            @night_off_conflicts[staff_id] << next_date
          end
        end
      end
    end
  end
end
