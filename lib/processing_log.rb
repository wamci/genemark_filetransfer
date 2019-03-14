class ProcessingLog < Sequel::Model Sequel.qualify('genemark_filetransfer','processing_logs')
  
  def successfully_processed
    ProcessingLog.where(bam_count: 384).exclude(finished_at: nil).all
  end

  def store_server_list(list)
    if list.length > 0
      list.each do |folder|
        insert_new_folder folder
      end
    end
  end

  def insert_new_folder(folder)
    begin
      ProcessingLog.insert folder: folder,
                           bam_count: 0
    rescue Sequel::UniqueConstraintViolation
      # TODO: handle exception
      p "Folder: #{folder} has already been added to the database."
    end
  end

  def process_next
    ProcessingLog.where(finished_at: nil)
                 .where(Sequel[:attempts] < 10)
                 .order(:attempts, :created_at)
                 .first
  end

  def get_folder(folder)
    ProcessingLog.where(folder: folder).first
  end

  def mark_as_processing
    update(processing_at: DateTime.now, attempts: (Sequel[:attempts] + 1))
    reload
  end

  def mark_as_complete
    update(finished_at: DateTime.now)
    reload
  end

  def update_bam_count(count)
    update(bam_count: count)
    reload
  end
end