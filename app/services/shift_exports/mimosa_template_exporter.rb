require "rubyXL"
require "rubyXL/convenience_methods"

module ShiftExports
  class MimosaTemplateExporter
    TEMPLATE_PATH = Rails.root.join("app/templates/shift_export/template.xlsx")

    # 月曜開始の1週 = 7日、1日あたり3列（C..E, F..H ...）
    MON_LEFT_COL = 3 # C列（1-based）
    DAY_STRIDE   = 3 # 3列ずつ進む（C->F->I...）

    # テンプレの行位置（あなたの指定）
    DATE_ROW_FIRST = 3     # 1週目の日付行
    WEEK_ROW_STEP  = 36    # 1週ごとのブロック差分（3->39 が 36）

    SHEET_NAME = "原本１か月"

    # 職員ブロック（1週目の開始）
    STAFF_BLOCK_FIRST = 19

    # 1週ブロック内の開始行オフセット
    ROW_OFFSETS = {
      nurse:    0,   # 19
      care_mgr: 5,   # 24
      care:     6,   # 25
      cook:     18,  # 37
      clerk:    19   # 38
    }.freeze

    # 各職種の縦枠上限（あなたの指定）
    MAX_ROWS = {
      nurse: 5,
      care_mgr: 1,
      care: 12,
      cook: 1,
      clerk: 1
    }.freeze

    # 早番/遅番の表示（showに合わせて固定）
    EARLY_TIME_TEXT = "730-1630"
    LATE_TIME_TEXT  = "11-20"

    def initialize(shift_month:)
      @shift_month = shift_month
    end

    # 返り値: xlsxのバイナリ文字列（controllerで send_data する）
    def call
      raise "template not found: #{TEMPLATE_PATH}" unless File.exist?(TEMPLATE_PATH)

      book  = RubyXL::Parser.parse(TEMPLATE_PATH.to_s)
      sheet = book[SHEET_NAME] || book.worksheets.first

      month_begin = Date.new(@shift_month.year, @shift_month.month, 1)
      month_end   = month_begin.end_of_month

      cal_begin = month_begin.beginning_of_week(:monday)
      cal_end   = month_end.end_of_week(:monday)
      dates     = (cal_begin..cal_end).to_a

      # ---- data preload（show相当）----
      staff_by_id = preload_staffs
      sorted_staffs_by_row_key = build_sorted_staffs_by_row_key(staff_by_id)
      assignments_hash = build_confirmed_assignments_hash(month_begin, month_end)

      unassigned_by_date =
        ShiftDrafts::UnassignedDisplayStaffsBuilder.new(
          dates: dates,
          staff_by_id: staff_by_id,
          assignments_hash: assignments_hash
        ).call

      # ---- style indexes ----
      red_style_index = read_cell(sheet, 2, col_index("U"))&.style_index # U2
      base_date_style_index = read_cell(sheet, DATE_ROW_FIRST, MON_LEFT_COL)&.style_index

      # ※日付セルは「元の背景/罫線/中央揃え」を維持し、赤はフォントだけ差し替える
      # （職員セルも同じ戦略で赤字にする）
      @__font_only_cache = {}

      # 日付セル
      dates.each do |date|
        week_idx = ((date - cal_begin).to_i / 7)
        wday_idx = (date.cwday - 1) # 月0..日6

        row = DATE_ROW_FIRST + (WEEK_ROW_STEP * week_idx)
        col = MON_LEFT_COL + (DAY_STRIDE * wday_idx) # 日付セルの左端（結合セルの左端）

        cell = ensure_cell(sheet, row, col)
        next unless cell

        # 月外は空欄
        if date < month_begin || date > month_end
          cell&.change_contents("")
          next
        end

        # 日祝は赤（祝日は HolidayJp で判定）
        holiday = HolidayJp.between(date, date).first
        holiday_name = holiday&.name
        is_sun = (wday_idx == 6)
        is_holiday = holiday_name && !holiday_name.empty?

        text =
          if is_holiday
            "#{date.day} #{holiday_name}"
          else
            date.day.to_s
          end

        cell&.change_contents(text)

        if (is_sun || is_holiday) && red_style_index
          base_idx = cell.style_index
          red_font_only_idx = build_font_only_style_index(
            book: book,
            base_style_index: base_idx,
            red_style_index: red_style_index
          )
          cell.style_index = red_font_only_idx if red_font_only_idx
        end
      end

      # ---- 2) 職員ブロック ----
      dates.each do |date|
        next if date < month_begin || date > month_end
        week_idx = ((date - cal_begin).to_i / 7)
        wday_idx = (date.cwday - 1)

        day_col   = MON_LEFT_COL + (DAY_STRIDE * wday_idx)     # C/F/I...
        night_col = day_col + 1                                # D/G/J...
        # stay_col  = day_col + 2                              # E/H/K...（当面触らない）

        ctx = build_day_context(assignments_hash, date)

        ROW_OFFSETS.each_key do |row_key|
          start_row = STAFF_BLOCK_FIRST + (WEEK_ROW_STEP * week_idx) + ROW_OFFSETS.fetch(row_key)
          limit     = MAX_ROWS.fetch(row_key)

          # 日勤列の表示行（文字＋赤フラグ）
          day_lines = build_day_lines(
            row_key: row_key,
            date: date,
            ctx: ctx,
            staff_by_id: staff_by_id,
            sorted_staffs_by_row_key: sorted_staffs_by_row_key,
            unassigned_by_date: unassigned_by_date
          )

          # 夜勤列の表示行（文字＋赤フラグ）
          night_lines = build_night_lines(
            row_key: row_key,
            ctx: ctx,
            staff_by_id: staff_by_id
          )

          write_lines_to_column(
            book: book,
            sheet: sheet,
            start_row: start_row,
            col: day_col,
            lines: day_lines,
            max_rows: limit,
            red_style_index: red_style_index
          )

          write_lines_to_column(
            book: book,
            sheet: sheet,
            start_row: start_row,
            col: night_col,
            lines: night_lines,
            max_rows: limit,
            red_style_index: red_style_index
          )
        end
      end

      book.stream.read
    end

    private

    # RubyXLは row/col が 1-based
    def read_cell(sheet, row, col)
      r = row - 1
      c = col - 1
      return nil unless sheet.sheet_data && sheet.sheet_data[r]
      sheet.sheet_data[r][c]
    end

    def ensure_cell(sheet, row, col)
      # まず既存セルを読む（テンプレのstyleを保持するため）
      cell = read_cell(sheet, row, col)
      return cell if cell

      # 無ければ初めて作る（0-based）
      sheet.add_cell(row - 1, col - 1)
    rescue StandardError
      nil
    end

    # "U" -> 21（1-based）
    def col_index(letter)
      letter = letter.to_s.upcase
      sum = 0
      letter.each_byte { |b| sum = sum * 26 + (b - "A".ord + 1) }
      sum
    end

    # -----------------------------
    # staff / assignments 準備
    # -----------------------------
    def preload_staffs
      @shift_month.user.staffs
                 .includes(:occupation, :staff_workable_wdays, :staff_day_time_options)
                 .where(active: true)
                 .index_by(&:id)
    end

    def row_key_for(staff)
      return nil if staff.nil?
      name = staff.occupation&.name.to_s
      return :nurse    if name.include?("看護")
      return :care_mgr if name.include?("ケアマネ")
      return :care     if name.include?("介護")
      return :cook     if name.include?("管理栄養士")
      return :clerk    if name.include?("事務")
      nil
    end

    def build_sorted_staffs_by_row_key(staff_by_id)
      staff_by_id.values
                 .group_by { |s| row_key_for(s) }
                 .transform_values do |list|
                   list.sort_by do |s|
                     [
                       s.workday_constraint == "free" ? 0 : 1,
                       s.last_name_kana.to_s,
                       s.first_name_kana.to_s,
                       s.id.to_i
                     ]
                   end
                 end
    end

    def build_confirmed_assignments_hash(month_begin, month_end)
      scope =
        @shift_month.shift_day_assignments.confirmed
                   .where(date: month_begin..month_end)
                   .select(:id, :date, :shift_kind, :staff_id, :slot, :staff_day_time_option_id)

      h = Hash.new { |hh, dkey| hh[dkey] = Hash.new { |hhh, kind| hhh[kind] = [] } }

      scope.find_each do |a|
        dkey = a.date.iso8601
        kind = a.shift_kind.to_s
        h[dkey][kind] << {
          "slot" => a.slot,
          "staff_id" => a.staff_id,
          "staff_day_time_option_id" => a.staff_day_time_option_id
        }
      end

      h.each_value do |kinds_hash|
        kinds_hash.each_value do |rows|
          rows.sort_by! { |r| r["slot"].to_i }
        end
      end

      h
    end

    # -----------------------------
    # show同等の “日ごとの文脈”
    # -----------------------------
    def build_day_context(assignments_hash, date)
      day_hash = (assignments_hash || {})[date.iso8601] || {}

      day_rows   = day_hash["day"]   || day_hash[:day]   || []
      early_rows = day_hash["early"] || day_hash[:early] || []
      late_rows  = day_hash["late"]  || day_hash[:late]  || []
      night_rows = day_hash["night"] || day_hash[:night] || []

      night_sid = first_staff_id(night_rows)

      prev_hash = (assignments_hash || {})[(date - 1).iso8601] || {}
      prev_night_rows = prev_hash["night"] || prev_hash[:night] || []
      night_off_sid = first_staff_id(prev_night_rows)

      night_related_ids = [night_sid, night_off_sid].compact.map(&:to_i)

      {
        day_rows: day_rows,
        early_rows: early_rows,
        late_rows: late_rows,
        night_rows: night_rows,
        night_sid: night_sid.to_i,
        night_off_sid: night_off_sid.to_i,
        night_related_ids: night_related_ids
      }
    end

    def first_staff_id(rows)
      first = Array(rows).first
      return nil if first.nil?
      sid = first.is_a?(Hash) ? (first["staff_id"] || first[:staff_id]) : nil
      sid.present? ? sid.to_i : nil
    end

    # -----------------------------
    # 表示行（文字＋赤フラグ）を作る
    # -----------------------------
    # 返り値: [{text:"...", red:true/false}, ...]
    def build_day_lines(row_key:, date:, ctx:, staff_by_id:, sorted_staffs_by_row_key:, unassigned_by_date:)
      day_rows   = ctx[:day_rows]
      early_rows = ctx[:early_rows]
      late_rows  = ctx[:late_rows]
      night_related_ids = ctx[:night_related_ids] || []

      # 介護は「全員名簿で勤務/休み」
      if row_key == :care
        staffs = Array(sorted_staffs_by_row_key[:care])
        assigned_kind_by_id = {}
        assigned_day_opt_by_id = {}

        { day: day_rows, early: early_rows, late: late_rows }.each do |kind_sym, rows|
          Array(rows).each do |r|
            sid = (r["staff_id"] || r[:staff_id]).to_i
            next unless sid > 0
            assigned_kind_by_id[sid] = kind_sym
            if kind_sym == :day
              opt_id = (r["staff_day_time_option_id"] || r[:staff_day_time_option_id]).to_i
              assigned_day_opt_by_id[sid] = (opt_id > 0 ? opt_id : nil)
            end
          end
        end

        return staffs.map do |s|
          kind = assigned_kind_by_id[s.id]
          if kind == :early
            { text: "#{s.last_name} #{EARLY_TIME_TEXT}", red: false }
          elsif kind == :late
            { text: "#{s.last_name} #{LATE_TIME_TEXT}", red: false }
          elsif kind == :day
            t = day_time_text_for(staff: s, picked_opt_id: assigned_day_opt_by_id[s.id], date: date)
            if t.present?
              { text: "#{s.last_name} #{t}", red: false }
            else
              { text: s.last_name.to_s, red: false }
            end
          else
            # 休み（night_relatedは(休)を付けず赤字名前のみ）
            if night_related_ids.include?(s.id.to_i)
              { text: s.last_name.to_s, red: true }
            else
              { text: "#{s.last_name}（休み）", red: true }
            end
          end
        end
      end

      # 介護以外：割当表示 → 夜勤関連の赤名前 → 未割当(休)
      lines = []
      displayed_ids = []

      # day割当（その職種だけ）
      Array(day_rows).each do |r|
        sid = (r["staff_id"] || r[:staff_id]).to_i
        staff = staff_by_id[sid]
        next if staff.nil?
        next unless row_key_for(staff) == row_key

        opt_id = (r["staff_day_time_option_id"] || r[:staff_day_time_option_id]).to_i
        t = day_time_text_for(staff: staff, picked_opt_id: (opt_id > 0 ? opt_id : nil), date: date)

        if t.present?
          lines << { text: "#{staff.last_name} #{t}", red: false }
        else
          lines << { text: staff.last_name.to_s, red: false }
        end
        displayed_ids << sid
      end

      # early/late割当（その職種だけ）
      Array(early_rows).each do |r|
        sid = (r["staff_id"] || r[:staff_id]).to_i
        staff = staff_by_id[sid]
        next if staff.nil?
        next unless row_key_for(staff) == row_key
        lines << { text: "#{staff.last_name} #{EARLY_TIME_TEXT}", red: false }
        displayed_ids << sid
      end

      Array(late_rows).each do |r|
        sid = (r["staff_id"] || r[:staff_id]).to_i
        staff = staff_by_id[sid]
        next if staff.nil?
        next unless row_key_for(staff) == row_key
        lines << { text: "#{staff.last_name} #{LATE_TIME_TEXT}", red: false }
        displayed_ids << sid
      end

      # 夜勤関連（赤字で名前だけ）※すでに表示済みは除外
      Array(night_related_ids).each do |sid|
        sid = sid.to_i
        next if sid <= 0
        next if displayed_ids.include?(sid)
        staff = staff_by_id[sid]
        next if staff.nil?
        next unless row_key_for(staff) == row_key
        lines << { text: staff.last_name.to_s, red: true }
        displayed_ids << sid
      end

      # 未割当(休)（赤字）※night_relatedは(休)なし
      list = unassigned_by_date && unassigned_by_date[date]
      Array(list).each do |staff|
        next if staff.nil?
        next unless row_key_for(staff) == row_key

        if night_related_ids.include?(staff.id.to_i)
          lines << { text: staff.last_name.to_s, red: true }
        else
          lines << { text: "#{staff.last_name}（休み）", red: true }
        end
      end

      lines
    end

    def build_night_lines(row_key:, ctx:, staff_by_id:)
      night_rows = ctx[:night_rows]
      night_sid = ctx[:night_sid].to_i
      night_off_sid = ctx[:night_off_sid].to_i

      lines = []

      # 夜勤入り（当日）
      Array(night_rows).each do |r|
        sid = (r["staff_id"] || r[:staff_id]).to_i
        staff = staff_by_id[sid]
        next if staff.nil?
        next unless row_key_for(staff) == row_key
        lines << { text: staff.last_name.to_s, red: false }
      end

      # 明け（前日夜勤者）※当日夜勤者と別なら表示
      if night_off_sid > 0 && night_off_sid != night_sid
        staff = staff_by_id[night_off_sid]
        if staff && row_key_for(staff) == row_key
          lines << { text: "#{staff.last_name}(明け)", red: false }
        end
      end

      lines
    end

    def day_time_text_for(staff:, picked_opt_id:, date:)
      ui_wday = ShiftMonth.ui_wday(date)

      day_opts =
        Array(staff.staff_day_time_options)
          .select { |o| o.active? }
          .sort_by { |o| [o.position.to_i, o.id.to_i] }

      # show/preview と同じ優先順：
      # 1) 曜日一致(apply_wdaysに含む)
      # 2) is_default
      # 3) 先頭
      day_default =
        day_opts.find { |o| Array(o.apply_wdays).map(&:to_i).include?(ui_wday) } ||
        day_opts.find { |o| o.is_default? } ||
        day_opts.first

      id = picked_opt_id || day_default&.id
      picked = id.present? ? day_opts.find { |o| o.id.to_i == id.to_i } : nil

      picked&.time_text.to_s
    end

    # -----------------------------
    # Excel書き込み（style保持 + 赤はフォントのみ）
    # -----------------------------
    def write_lines_to_column(book:, sheet:, start_row:, col:, lines:, max_rows:, red_style_index:)
      # まず、テンプレの枠（max_rows）に対して“空欄クリア”しておく
      max_rows.times do |i|
        cell = ensure_cell(sheet, start_row + i, col)
        next unless cell
        cell.change_contents("")
        # styleはいじらない（テンプレ維持）
      end

      Array(lines).first(max_rows).each_with_index do |item, i|
        text = item[:text].to_s
        red  = item[:red] == true

        cell = ensure_cell(sheet, start_row + i, col)
        next unless cell

        cell.change_contents(text)

        if red && red_style_index
          base_idx = cell.style_index
          red_font_only_idx = build_font_only_style_index(
            book: book,
            base_style_index: base_idx,
            red_style_index: red_style_index
          )
          cell.style_index = red_font_only_idx if red_font_only_idx
        end
      end

      # 枠あふれは「アラートだけ」：ここではログに残す（UIアラートは次ステップで）
      if Array(lines).size > max_rows
        Rails.logger.warn("[export_excel] overflow: row=#{start_row} col=#{col} lines=#{lines.size} max=#{max_rows}")
      end
    end

    def build_font_only_style_index(book:, base_style_index:, red_style_index:)
      return nil if base_style_index.nil? || red_style_index.nil?

      key = [base_style_index.to_i, red_style_index.to_i]
      return @__font_only_cache[key] if @__font_only_cache.key?(key)

      stylesheet = book.stylesheet
      return nil unless stylesheet

      base_xf = stylesheet.cell_xfs[base_style_index]
      red_xf  = stylesheet.cell_xfs[red_style_index]
      return nil if base_xf.nil? || red_xf.nil?

      # 「赤」に使われているフォントIDだけ取る（背景は取らない）
      red_font_id = red_xf.font_id
      return nil if red_font_id.nil?

      # base_xf をコピーして font_id だけ差し替え
      new_xf = base_xf.dup
      new_xf.font_id = red_font_id
      new_xf.apply_font = 1 if new_xf.respond_to?(:apply_font=)

      stylesheet.cell_xfs << new_xf
      idx = stylesheet.cell_xfs.size - 1

      @__font_only_cache[key] = idx
    end
  end
end
