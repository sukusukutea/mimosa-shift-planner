class BackfillCalendarDisplayOrderOnStaffs < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      WITH ranked_staffs AS (
        SELECT
          staffs.id,
          (
            ROW_NUMBER() OVER (
              PARTITION BY
                staffs.user_id,
                CASE
                  WHEN occupations.name LIKE '%看護%' THEN 'nurse'
                  WHEN occupations.name LIKE '%介護%' THEN 'care'
                END
              ORDER BY
                CASE
                  WHEN staffs.workday_constraint = 0 THEN 0
                  ELSE 1
                END,
                staffs.last_name_kana,
                staffs.first_name_kana,
                staffs.id
            )
          )::integer AS display_order
        FROM staffs
        INNER JOIN occupations
          ON occupations.id = staffs.occupation_id
        WHERE
          occupations.name LIKE '%看護%'
          OR occupations.name LIKE '%介護%'
      )
      UPDATE staffs
      SET calendar_display_order = ranked_staffs.display_order
      FROM ranked_staffs
      WHERE staffs.id = ranked_staffs.id;
    SQL
  end

  def down
    execute <<~SQL
      UPDATE staffs
      SET calendar_display_order = NULL
      FROM occupations
      WHERE staffs.occupation_id = occupations.id
        AND (
          occupations.name LIKE '%看護%'
          OR occupations.name LIKE '%介護%'
        );
    SQL
  end
end