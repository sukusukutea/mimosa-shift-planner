module ShiftDrafts
  class RandomGenerator
    def initialize(shift_month:, carry_over_state: {})
      @shift_month = shift_month
      @active_scope = @shift_month.user.staffs.where(active: true)
      @carry_over_state = carry_over_state || {}
    end

    def call
      month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
      month_end   = month_begin.end_of_month
      @month_end  = month_end
      @dates = (month_begin..month_end).to_a
      @staff_by_id = @active_scope.includes(:staff_workable_wdays, :occupation).index_by(&:id)

      @worked_days_by_staff, @last_worked_by_staff = build_worked_indexes(
        month_begin: month_begin,
        month_end: month_end
      )

      designations = @shift_month.shift_day_designations.where(date: month_begin..month_end)
      designations_by_date = Hash.new { |h, k| h[k] = {} }
      designations.each do |d|
        kind = d.shift_kind.to_s

        if kind == "late" || kind == "day"
          (designations_by_date[d.date][kind] ||= []) << d.staff_id
        else
          designations_by_date[d.date][kind] = d.staff_id
        end
      end # 返り値 designations_by_date[date]["day"] => staff_id　みたいに引ける形

      @designations_by_date = designations_by_date

      holiday_ids_by_date =
        @shift_month.staff_holiday_requests
                    .where(date: month_begin..month_end)
                    .group_by(&:date)
                    .transform_values { |rows| rows.map(&:staff_id) }

      draft = {}
      @timeline =
        ShiftDrafts::AssignmentTimeline.new(
          dates: (month_begin..month_end).to_a,
          staff_by_id: @staff_by_id,
          assignments_hash: draft
        )

      # staff_id => Ser[Date, Date, ...]この日の割当を禁止する
      @forced_off_dates_by_staff_id = Hash.new { |h, k| h[k] = Set.new }
      apply_carry_over_forced_offs!(month_begin: month_begin)

      occ_name_by_staff_id = @active_scope
                             .joins(:occupation)
                             .pluck(:id, "occupations.name")
                             .to_h
 
      (month_begin..month_end).each do |date|
        # 前日までのdraftをtimelineに反映（連続勤務判定のため）
        @timeline.call

        enabled_map = @shift_month.enabled_map_for(date) # その日の勤務のON/OFFを取得 返り値例{ day: true, early: true, late: false, night: true }        
        scope = @active_scope
        holiday_ids = holiday_ids_by_date[date] || []
        assigned_today = Set.new  # SetはRuby標準ライブラリのSetクラス「同じ値を二度入れられない」。同じidが重複できない
        day_hash = {} # その日の最終結果

        forced_off_ids = forced_off_staff_ids_on(date)

        ShiftMonth::SHIFT_KINDS.each do |kind|
          sid = designations_by_date.dig(date, kind.to_s)
          next if sid.blank?

          rows = (day_hash[kind] ||= [])

          staff_ids =
            if kind == :late || kind == :day
              Array(sid)
            else
              [sid]
            end

          staff_ids.each do |staff_id|
            add_row_and_track!(
              rows: rows,
              staff_id: staff_id,
              assigned_today: assigned_today,
              date: date,
              kind: kind
            )
          end
        end

        fill_order = [:early, :late, :day, :night]
        fill_order.each do |kind|
          next unless enabled_map[kind] # OFFなら割当しない

          if kind == :day
            counts = @shift_month.required_counts_for(date, shift_kind: :day)
            skill_counts = @shift_month.required_skill_counts_for(date)

            fixed_staffs = scope
              .where(can_day: true)
              .where(workday_constraint: :fixed)
              .left_joins(:staff_workable_wdays)
              .where(staff_workable_wdays: { wday: ShiftMonth.ui_wday(date) })
              .where.not(id: holiday_ids + forced_off_ids)
              .where.not(id: assigned_today.to_a)
              .includes(:occupation)

            day_rows = Array(day_hash[:day])

            fixed_staffs.each do |staff|
              add_row_and_track!(
                rows: day_rows,
                staff_id: staff.id,
                assigned_today: assigned_today,
                date: date,
                kind: :day
              )
            end

            slot = day_rows.size

            slot = fill_day_skills!(
              day_rows: day_rows,
              date: date,
              skill_counts: skill_counts,
              assigned_today: assigned_today,
              holiday_ids: holiday_ids,
              scope: scope,
              slot: slot
            )

            uncounted_fixed_ids =
              fixed_staffs.reject(&:counts_toward_requirements?).map(&:id)
            current_counted_staff_ids =
              day_rows.map { |r| r[:staff_id] }.compact.map(&:to_i) - uncounted_fixed_ids

            have_nurse = current_counted_staff_ids.count { |sid| occ_name_by_staff_id[sid].to_s.include?("看護") }
            have_care  = current_counted_staff_ids.count { |sid| occ_name_by_staff_id[sid].to_s.include?("介護") }

            need_nurse = [counts[:nurse] - have_nurse, 0].max
            need_care  = [counts[:care]  - have_care,  0].max

            slot = fill_day_roles!(
              day_rows: day_rows,
              date: date,
              need_nurse: need_nurse,
              need_care: need_care,
              assigned_today: assigned_today,
              holiday_ids: holiday_ids,
              slot: slot
            )

            day_hash[:day] = day_rows
            next
          end

          # --- 日勤以外（early / late / night）---
          limit = (kind == :late) ? @shift_month.late_slots_for(date) : 1

          while Array(day_hash[kind]).size < limit
            forced_off_ids_now = forced_off_staff_ids_on(date)
            exclude_for_normal = assigned_today.to_a + holiday_ids + forced_off_ids_now

            staff = pick_staff_for(kind, exclude_ids: exclude_for_normal, date: date)

            # 夜勤候補が0なら「夜勤2連続」を例外で許可
            if staff.nil? && kind == :night
              staff = pick_staff_for_double_night(date: date, exclude_ids: assigned_today.to_a + holiday_ids)
            end

            break if staff.nil?

            rows = (day_hash[kind] ||= [])

            add_row_and_track!(
              rows: rows,
              staff_id: staff.id,
              assigned_today: assigned_today,
              date: date,
              kind: kind
            )
          end
        end

        draft[date.iso8601] = day_hash # １日のドラフトを格納
      end

      draft
    end
    
    private

    def apply_workday_constraint(scope, date:)
      wday = ShiftMonth.ui_wday(date)

      free  = Staff.workday_constraints[:free]
      weekly = Staff.workday_constraints[:weekly]
      fixed = Staff.workday_constraints[:fixed]

      scope
        .left_joins(:staff_workable_wdays)
        .joins(<<~SQL.squish)
          LEFT OUTER JOIN staff_unworkable_wdays
            ON staff_unworkable_wdays.staff_id = staffs.id
          AND staff_unworkable_wdays.wday = #{ActiveRecord::Base.connection.quote(wday)}
        SQL
        .where(
          "((staffs.workday_constraint IN (:free, :weekly)
              AND staff_unworkable_wdays.wday IS NULL)
            OR
            (staffs.workday_constraint = :fixed
              AND staff_workable_wdays.wday = :wday))",
          wday: wday,
          free: free,
          weekly: weekly,
          fixed: fixed
        )
        .distinct
    end

    # そのstaffがその日に「日勤系」で手動指定されているか？
    def designated_dayish?(staff_id, date)
      h = @designations_by_date&.[](date)
      return false if h.blank?

      sid = staff_id.to_i

      day = h["day"]
      return true if Array(day).any? { |x| x.to_i == sid }
      return true if h["early"].to_i == sid

      late = h["late"]
      Array(late).any? { |x| x.to_i == sid }
    end

    def consecutive_designation_days_after(staff_id, date)
      return 0 if date.nil?
      return 0 if @dates.blank? || @designations_by_date.blank?

      idx = @dates.index(date)
      return 0 unless idx

      count = 0
      @dates[(idx + 1)..].each do |d|
        if designated_dayish?(staff_id, d)
          count += 1
        else
          break
        end
      end
      count
    end

    # ここでのexclude_ids：すでに選ばれた職員のID配列（同じ人を重複させないため）
    def pick_staff_for(kind, exclude_ids:, role: nil, date: nil, skill: nil) 
      scope = @active_scope

      scope =                          # case kindで条件を足している。kindに応じて対応できる職員だけに絞る
        case kind
        when :day    then scope.where(can_day: true)
        when :early  then scope.where(can_early: true)
        when :late   then scope.where(can_late: true)
        when :night  then scope.where(can_night: true)
        else
          scope.none # 想定外のkindが来たら誰も返さない
        end

      if kind == :day && skill.present?
        case skill.to_sym
        when :drive
          scope = scope.where(can_drive: true)
        when :cook
          scope = scope.where(can_cook: true)
        else
          scope = scope.none
        end
      end

      if kind == :day && role.present?
        scope = scope.joins(:occupation)
        case role
        when :nurse
          scope = scope.where("occupations.name LIKE ?", "%看護%")
        when :care
          scope = scope.where("occupations.name LIKE ?", "%介護%")
        end
      end

      if date.present? && [:day, :early, :late].include?(kind)
        scope = apply_workday_constraint(scope, date: date)
      end

      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?  # any?で配列に一つでも要素があればture. exclude_idsは含めない
      # ここまでで、kindがtrue かつ すでに使用したIDではない、の条件で満たされたscopeができる。

      # 候補IDを取ってRuby側で「直近で働いていない順」→「勤務日数が少ない順」に並べて選ぶ
      candidate_ids = scope.pluck(:id)

      if date.present? && kind == :early
        candidate_ids =
          candidate_ids.reject do |sid|
            previous_day_late_assigned?(sid, date)
          end
      end

      candidate_ids = filter_ids_by_weekly_cap(candidate_ids, date) if date.present? && [:day, :early, :late].include?(kind)

      # 連続勤務5日→２休を強制（Timelineで判定）
      if date.present? && [:day, :early, :late].include?(kind)
        candidate_ids =
          candidate_ids.reject do |sid|
            before = @timeline.consecutive_day_count_before(sid, date)
            after  = consecutive_designation_days_after(sid, date)
            max_days = max_consecutive_work_days_for(sid)

            (before + 1 + after) > max_days
          end
      end

      priority_mode =
        case kind
        when :early, :late
          :worked_only # 勤務日数を確認。勤務日数が少ない人を優先させるため。
        else
          :full # 最近働いていない人＋勤務日数を確認 優先順位①最近働いていない人②勤務日数が少ない人
        end

      pick_by_priority(candidate_ids, date: date, priority_mode: priority_mode, kind: kind)
    end

    # 日勤スキルを未選定から追加で埋める。候補をDBから一括取得してshuffleし、Ruby側でpopしていく
    def fill_day_skills!(day_rows:, date:, skill_counts:, assigned_today:, holiday_ids:, scope:, slot:)
      day_staff_ids = day_rows.map { |row| row[:staff_id] }.compact.map(&:to_i)

      counted_day_staffs =
        if day_staff_ids.any?
          scope
            .where(id: day_staff_ids)
            .includes(:occupation)
            .reject { |staff| !staff.counts_toward_requirements? }
        else
          []
        end

      drive_have = counted_day_staffs.count { |staff| staff.respond_to?(:can_drive) && staff.can_drive }
      cook_have  = counted_day_staffs.count { |staff| staff.respond_to?(:can_cook)  && staff.can_cook }

      need_drive = [skill_counts[:drive].to_i - drive_have, 0].max
      need_cook  = [skill_counts[:cook].to_i  - cook_have,  0].max

      base_exclude = assigned_today.to_a + holiday_ids + forced_off_staff_ids_on(date)

      drive_ids = day_skill_candidate_ids(date: date, exclude_ids: base_exclude, skill: :drive)
      while need_drive > 0 && drive_ids.any?
        sid = drive_ids.pop

        add_row_and_track!(
          rows: day_rows,
          staff_id: sid,
          assigned_today: assigned_today,
          date: date,
          kind: :day
        )

        slot += 1
        need_drive -= 1
      end

      base_exclude = assigned_today.to_a + holiday_ids + forced_off_staff_ids_on(date)

      cook_ids = day_skill_candidate_ids(date: date, exclude_ids: base_exclude, skill: :cook)
      while need_cook > 0 && cook_ids.any?
        sid = cook_ids.pop

        add_row_and_track!(
          rows: day_rows,
          staff_id: sid,
          assigned_today: assigned_today,
          date: date,
          kind: :day
        )

        slot += 1
        need_cook -= 1
      end

      slot
    end

    # 日勤スキル候補のstaff.idを一括取得してシャッフルして返す。返り値：[staff_id, staff_id, ...]
    def day_skill_candidate_ids(date:, exclude_ids:, skill:)
      scope = @active_scope.where(can_day: true)
      scope = apply_workday_constraint(scope, date: date)

      case skill.to_sym
      when :drive
        scope = scope.where(can_drive: true)
      when :cook
        scope = scope.where(can_cook: true)
      else
        return []
      end

      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?
      ids = scope.pluck(:id)
      ids = filter_ids_by_weekly_cap(ids, date)
      sort_ids_by_priority(ids, date: date)
    end

    def fill_day_roles!(day_rows:, date:, need_nurse:, need_care:, assigned_today:, holiday_ids:, slot:)
      base_exclude = assigned_today.to_a + holiday_ids + forced_off_staff_ids_on(date)

      nurse_ids = day_role_candidate_ids(date: date, exclude_ids: base_exclude, role: :nurse)
      while need_nurse > 0 && nurse_ids.any?
        sid = nurse_ids.pop

        add_row_and_track!(
          rows: day_rows,
          staff_id: sid,
          assigned_today: assigned_today,
          date: date,
          kind: :day
        )

        slot += 1
        need_nurse -= 1
      end
      
      base_exclude = assigned_today.to_a + holiday_ids + forced_off_staff_ids_on(date)

      care_ids = day_role_candidate_ids(date: date, exclude_ids: base_exclude, role: :care)
      while need_care > 0 && care_ids.any?
        sid = care_ids.pop

        add_row_and_track!(
          rows: day_rows,
          staff_id: sid,
          assigned_today: assigned_today,
          date: date,
          kind: :day
        )

        slot += 1
        need_care -= 1
      end

      slot
    end

    def day_role_candidate_ids(date:, exclude_ids:, role:)
      scope = @active_scope.where(can_day: true)
      scope = apply_workday_constraint(scope, date: date)

      # 職種で絞る
      scope = scope.joins(:occupation)
      case role
      when :nurse
        scope = scope.where("occupations.name LIKE ?", "%看護%")
      when :care
        scope = scope.where("occupations.name LIKE ?", "%介護%")
      else
        return []
      end

      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?
      ids = scope.pluck(:id)
      ids = filter_ids_by_weekly_cap(ids, date)
      sort_ids_by_priority(ids, date: date)
    end

    # 日単位で「勤務日数」と「最終勤務日」を作る worked_days_by_staff => { staff_id => 12, ... }, last_worked_by_staff => { staff_id => Date, ... }
    def build_worked_indexes(month_begin:, month_end:) 
      worked = Hash.new(0)
      last  = {}

      [worked, last]
    end

    def pick_by_priority(candidate_ids, date:, priority_mode: :full, kind: nil)
      return nil if candidate_ids.blank?

      ids = sort_ids_by_priority(candidate_ids, date: date, priority_mode: priority_mode, kind: kind)

      @active_scope.find_by(id: ids.last)
    end

    def sort_ids_by_priority(ids, date:, priority_mode: :full, kind: nil)
      care_exists  = false
      nurse_exists = false

      if date.present? && [:early, :late].include?(kind)
        Array(ids).each do |id|
          name = @staff_by_id[id.to_i]&.occupation&.name.to_s
          care_exists  ||= name.include?("介護")
          nurse_exists ||= name.include?("看護")
        end
      end

      Array(ids).sort_by do |sid|
        worked = @worked_days_by_staff[sid].to_i

        role_bias = 0
        if date.present? && [:early, :late].include?(kind) && care_exists && nurse_exists
          name = @staff_by_id[sid.to_i]&.occupation&.name.to_s
          role_bias = name.include?("介護") ? 1 : 0
        end

        week_kind = 0
        week_day  = 0
        if date.present? && [:early, :late].include?(kind)
          week_kind = -assigned_kind_count_in_week(sid, date, kind)
          week_day  = -assigned_kind_count_in_week(sid, date, :day)
        end

        wday_kind_bias = 0
        if date.present? && [:early, :late].include?(kind)
          wday_kind_bias = -assigned_kind_count_on_wday_in_month(sid, date.wday, kind)
        end

        case priority_mode
        when :worked_only # 純粋に勤務日数だけチェック
          [
            role_bias,
            wday_kind_bias,
            week_kind,
            -worked, # 末尾が「勤務日数少ない人」にしたいので -worked(小→大で末尾が小さくなる)
            rand
          ]
        else # :full
          days_since = days_since_last_work(sid, date: date)
          [
            role_bias,
            wday_kind_bias,
            week_kind,
            week_day,
            days_since,
            -worked,
            rand                                # 同点揺らぎ
          ]
        end
      end
    end

    def days_since_last_work(staff_id, date:)
      last = @last_worked_by_staff[staff_id]
      return 10_000 if last.nil?
      (date - last).to_i
    end

    def track_work!(staff_id, date:) #生成中の割り当てを評価用indexに反映
      return if staff_id.blank? || date.nil?
      sid = staff_id.to_i

      @worked_days_by_staff[sid] = @worked_days_by_staff[sid].to_i + 1
      prev = @last_worked_by_staff[sid]
      @last_worked_by_staff[sid] = prev.nil? ? date : [prev, date].max
    end

    def forced_off_staff_ids_on(date)
      @forced_off_dates_by_staff_id
        .select { |_sid, set| set.include?(date) }
        .keys
    end

    def apply_carry_over_forced_offs!(month_begin:)
      return if @carry_over_state.blank?

      day1 = month_begin
      day2 = month_begin + 1

      @carry_over_state.each do |staff_id, state|
        sid = staff_id.to_i
        next if sid <= 0
        next if state.blank?

        carry_in_kind = state[:carry_in_kind]&.to_sym

        if carry_in_kind == :night_off
          @forced_off_dates_by_staff_id[sid] << day1
        end

        rest_days = state[:remaining_required_rest_days].to_i

        if rest_days >= 1
          rest_start = carry_in_kind == :night_off ? day2 : day1
          @forced_off_dates_by_staff_id[sid] << rest_start
        end

        if rest_days >= 2
          rest_second = carry_in_kind == :night_off ? (day2 + 1) : day2
          @forced_off_dates_by_staff_id[sid] << rest_second
        end
      end
    end

    def after_assigned!(staff_id, date:, kind:, month_end:)
      return if staff_id.blank? || date.nil?
      kind = kind.to_sym

      # 夜勤が入ったら明け＋休みを強制OFFにする
      if kind == :night
        if night_assigned_on?(staff_id.to_i, date - 2)
          lock_after_double_night!(staff_id.to_i, date: date, month_end: month_end) # 明け + 2休
        else
          lock_night_flow!(staff_id.to_i, date: date, month_end: month_end) # 明け + 休
        end
        return
      end

      return unless [:day, :early, :late].include?(kind)

      #今日割当する直前までの連続日勤系数
      before = @timeline.consecutive_day_count_before(staff_id.to_i, date)

      if before >= 4
        lock_two_off_days!(staff_id.to_i, date: date, month_end: month_end)
      end
    end

    def lock_two_off_days!(staff_id, date:, month_end:)
      d1 = date + 1
      d2 = date + 2
      @forced_off_dates_by_staff_id[staff_id] << d1 if d1 <= month_end
      @forced_off_dates_by_staff_id[staff_id] << d2 if d2 <= month_end
    end

    def lock_night_flow!(staff_id, date:, month_end:)
      # 1日目夜勤入り、2日目明け、3日目休
      d1 = date + 1
      d2 = date + 2
      @forced_off_dates_by_staff_id[staff_id] << d1 if d1 <= month_end
      @forced_off_dates_by_staff_id[staff_id] << d2 if d2 <= month_end
    end

    # 夜勤候補0の時に2連続夜勤をピックアップ。条件：2日前に夜勤には一致える。4日前に夜勤に入っている場合はNG。
    def pick_staff_for_double_night(date:, exclude_ids:)
      return nil if date.nil?

      base_ids =
        @active_scope
          .where(can_night: true)
          .pluck(:id)
          .reject { |sid| exclude_ids.include?(sid.to_i) }
          .select { |sid| night_assigned_on?(sid, date - 2) }
          .reject { |sid| night_assigned_on?(sid, date - 4) }

      return nil if base_ids.blank?

      ids = sort_ids_by_priority(base_ids, date: date, priority_mode: :full)
      @active_scope.find_by(id: ids.last)
    end

    def night_assigned_on?(staff_id, date)
      return false if staff_id.blank? || date.nil?
      return false if @timeline.nil?

      daily = @timeline.instance_variable_get(:@timeline)&.[](staff_id.to_i)
      return false if daily.blank?
      daily[date] == :night
    end

    def previous_day_late_assigned?(staff_id, date)
      return false if staff_id.blank? || date.nil?
      return false if @timeline.nil?

      previous_day = date -1
      daily = @timeline.instance_variable_get(:@timeline)&.[](staff_id.to_i)
      return false if daily.blank?

      daily[previous_day] == :late
    end

    def lock_after_double_night!(staff_id, date:, month_end:)
      d1 = date + 1
      d2 = date + 2
      d3 = date + 3
      @forced_off_dates_by_staff_id[staff_id] << d1 if d1 <= month_end
      @forced_off_dates_by_staff_id[staff_id] << d2 if d2 <= month_end
      @forced_off_dates_by_staff_id[staff_id] << d3 if d3 <= month_end
    end

    def assigned_dayish_count_in_week(staff_id, date)
      tl = @timeline.instance_variable_get(:@timeline)&.[](staff_id.to_i)
      return 0 if tl.blank?

      week_begin = date.beginning_of_week(:monday)
      week_end   = week_begin + 6

      (week_begin..week_end).count do |d|
        kind = tl[d]
        [:day, :early, :late].include?(kind)
      end
    end

    def filter_ids_by_weekly_cap(ids, date)
      Array(ids).reject do |sid|
        staff = @staff_by_id[sid.to_i]
        next false if staff.nil?
        next false unless staff.workday_constraint == "weekly"

        limit = staff.weekly_workdays.to_i
        next false if limit <= 0

        assigned_dayish_count_in_week(sid, date) >= limit
      end
    end

    def max_consecutive_work_days_for(staff_id)
      staff = @staff_by_id[staff_id.to_i]
      return 5 if staff.nil?
      return 5 unless staff.workday_constraint.to_s == "free"

      days = staff.max_consecutive_work_days.to_i
      days.clamp(1, 5)
    end

    def assigned_kind_count_in_week(staff_id, date, kind)
      tl = @timeline.instance_variable_get(:@timeline)&.[](staff_id.to_i)
      return 0 if tl.blank?

      week_begin = date.beginning_of_week(:monday)
      week_end   = week_begin + 6

      (week_begin..week_end).count do |d|
        tl[d] == kind
      end
    end

    def add_row_and_track!(rows:, staff_id:, assigned_today:, date:, kind:)
      sid = staff_id.to_i
      rows << { slot: rows.size, staff_id: sid }
      assigned_today.add(sid)
      track_work!(sid, date: date)
      after_assigned!(sid, date: date, kind: kind, month_end: @month_end)
    end

    def assigned_kind_count_on_wday_in_month(staff_id, target_wday, kind)
      tl = @timeline.instance_variable_get(:@timeline)&.[](staff_id.to_i)
      return 0 if tl.blank?

      tl.count do |d, k|
        d.respond_to?(:wday) && d.wday == target_wday && k == kind
      end
    end
  end
end
