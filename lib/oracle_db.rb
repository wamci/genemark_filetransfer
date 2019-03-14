ORACLE_DB = Sequel.connect(ENV['ORACLE_DB_CONNECTION_STRING'])
class OracleDatabase
  def get_animal_info(animal)
    sql = <<-SQL
            SELECT a.aliquot_id, a.external_reference, TO_CHAR(au.u_animal_key) AS u_animal_key, au.u_animal_id
            FROM lims.aliquot a
            INNER JOIN lims.aliquot_user au ON a.aliquot_id = au.aliquot_id
            WHERE a.aliquot_id = ?
          SQL

    ORACLE_DB.fetch(sql, animal[:aliquot_id]).first
  end
end
