class AnimalResult < Sequel::Model Sequel.qualify('genemark_filetransfer', 'animal_results')
  def add_animal_result(animal)
    begin
      AnimalResult.insert aliquot_id:     animal[:aliquot_id],
                          aliquot_id_alt: animal[:aliquot_id_alt],
                          path:           animal[:full_path],
                          folder_name:    animal[:folder_name],
                          file_name:      animal[:bam_file_name]
    rescue Sequel::UniqueConstraintViolation
      # TODO: handle exception
      p "Animal: #{animal} has already been added to the database."
    end
  end

  def get_animals_for_folder(folder)
    AnimalResult.where(folder_name: folder).order(:file_name).all
  end

  def update_animal_extra(animal, extra_info)
    animal.update animal_key: extra_info[:u_animal_key],
                  birth_id:   extra_info[:u_animal_id],
                  barcode:    extra_info[:external_reference]
  end

  def clear_animal_data_for_folder(folder)
    animals = AnimalResult.where(folder_name: folder).all
    AnimalResult.where(folder_name: folder).delete if animals.length > 0
  end

  def to_export
    { aliquot_id:     aliquot_id,
      aliquot_id_alt: aliquot_id_alt,
      animal_key:     animal_key,
      birth_id:       birth_id,
      barcode:        barcode,
      path:           path,
      folder_name:     folder_name,
      file_name:      file_name }
  end
end
