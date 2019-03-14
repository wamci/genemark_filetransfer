require 'sequel'
require 'optparse'
require 'require_all'
require 'net/ssh'
require 'net/scp'
require 'dotenv/load'
require 'fileutils'
require 'json'
require 'csv'
require 'logger'

DB = Sequel.connect(ENV['DB_CONNECTION_STRING'])
require_all 'lib'

class Main
  
  def initialize
    log_path = ENV['LOG_PATH']
    FileUtils.mkdir_p(log_path) unless Dir.exist? log_path
    @log = Logger.new("#{log_path}/process_log.txt", 'daily')
    @log.info('Application Initialisation')
    @options = {}
    @options[:create_folder] = false
    @iontorrent_ip = ENV['ION_IP']
    @iontorrent_user = ENV['ION_USER']
    @results_path = ENV['RESULTS_PATH']
    @output_path = ENV['OUTPUT_PATH'] + '/'
    @processing_logs = ProcessingLog.new
    @animal_results = AnimalResult.new
    @oracle_db = OracleDatabase.new
  end

  def get_options
    OptionParser.new do |opts|
      opts.banner = "Usage: opt_test.rb [options]"
      opts.on('-f', '--folder FOLDER', 'Folder for processing') { |text| @options[:folder] = text }
      opts.on('-c', '--create', 'Create folder for first time processing') do
        @options[:create_folder] = true
      end
    end.parse!
  end

  def run
    get_options
    if @options[:folder].nil?
      # AUTO RUN
      @log.info('Auto run selected')
      server_list = filter_folders get_folder_list
      successfully_processed_list = @processing_logs.successfully_processed.map { |hash| hash.folder }
      @log.debug("Auto: server list count = #{server_list.length}")
      @log.debug("Auto: processed list count = #{successfully_processed_list.length}")
      if server_list.length > 0 && successfully_processed_list.length > 0
        @processing_logs.store_server_list server_list.reject {|folder_name| successfully_processed_list.include? folder_name }
      end
      check_next_unprocessed
    else
      # MANUAL RUN
      @log.info('Manual run selected')
      manual_folder = @options[:folder]
      manual_folder_name = manual_folder.split('/').last
      @log.debug("Manual: processing #{manual_folder_name}")
      if Dir.exist? manual_folder
        manual_folder_files = Dir["#{manual_folder}/*"]
        filtered_bam_list = filter_bam_only manual_folder_files
        bam_count = filtered_bam_list.length
        @log.debug("Manual: bam list count = #{bam_count}")
        if bam_count < 384
          @log.debug("Manual: bam count less than 384\nManual: removing contents from #{manual_folder}/.")
          FileUtils.rm_rf("#{manual_folder}/.", secure: true)
          transfer_bam_files get_bam_list(manual_folder_name), manual_folder_name
          transfer_json_file manual_folder_name
          @log.debug("Manual: bam and json files updated in #{manual_folder}")
        end
        json_file_path = "#{manual_folder}/startplugin.json"
        if File.file? json_file_path
          if @options[:create_folder]
            @log.debug("Manual: creating new folder #{manual_folder}")
            @processing_logs.insert_new_folder manual_folder_name
          end
          folderObj = @processing_logs.get_folder manual_folder_name
          unless folderObj.nil?
            folderObj.mark_as_processing
            @log.debug("Manual: deleting animal data for #{manual_folder_name}")
            @animal_results.clear_animal_data_for_folder manual_folder_name
            @log.debug("Manual: processing json file for #{manual_folder_name}")
            process_json_file json_file_path, manual_folder_name
            @log.debug("Manual: retrieving animal data for #{manual_folder_name}")
            update_animals_from_animal_db manual_folder_name
            @log.debug("Manual: creating csv for #{@output_path + manual_folder_name}")
            export_csv @output_path, manual_folder_name
            @log.debug("Manual: csv successfully created for #{manual_folder_name}. Job complete")
            folderObj.mark_as_complete
          else
            @log.error("Manual: unable to retrieve folder object from database for #{manual_folder_name}")
          end
        else
          @log.error("Manual: problem with JSON file for #{manual_folder_name}")
        end
      else
        @log.error("Manual: #{@options[:folder]} does not exist")
      end
    end
  end
  
  def check_next_unprocessed
    next_unprocessed = @processing_logs.process_next
    if next_unprocessed
      next_unprocessed.mark_as_processing
      process_folder next_unprocessed
      # check_next_unprocessed
    end
  end

  def process_folder(folderObj)
    folder_name = folderObj[:folder]
    @log.debug("Auto: processing: #{folder_name}")
    filtered_bam_list = filter_bam_only get_bam_list(folder_name)
    bam_count = filtered_bam_list.length
    @log.debug("Auto: bam list count = #{bam_count}")
    if bam_count > 0
      folderObj.update_bam_count(bam_count)
      FileUtils.mkdir_p(@output_path + folder_name)
      transfer_bam_files filtered_bam_list, folder_name
      transfer_json_file folder_name
      @log.debug("Auto: bam and json files updated in #{folder_name}")
      @log.debug("Auto: processing json file for #{folder_name}")
      process_json_file get_json_file_path(folder_name), folder_name
      @log.debug("Auto: retrieving animal data for #{folder_name}")
      update_animals_from_animal_db folder_name
      @log.debug("Auto: creating csv for #{@output_path + folder_name}")
      export_csv @output_path, folder_name
      @log.debug("Auto: csv successfully created for #{folder_name}. Job complete")
      @processing_logs.mark_as_complete
    end
  end

  def get_folder_list
    ssh = Net::SSH.start(@iontorrent_ip, @iontorrent_user)
    folder_list = ssh.exec!("cd #{@results_path} && ls").split("\n")
    ssh.close()
    folder_list
  end

  def get_bam_list(folder)
    ssh = Net::SSH.start(@iontorrent_ip, @iontorrent_user)
    bam_list = ssh.exec!("cd #{@results_path + folder} && ls | grep .bam").split("\n")
    ssh.close()
    bam_list
  end

  def get_json_file_path(folder)
    ssh = Net::SSH.start(@iontorrent_ip, @iontorrent_user)
    plugin_folder_file_list = ssh.exec!("cd #{@results_path + folder}/plugin_out && ls").split("\n")
    ssh.close()
    lic_folder_name = plugin_folder_file_list.keep_if {|v| v.include? 'LIC'}.first
    "#{@results_path + folder}/plugin_out/#{lic_folder_name}/startplugin.json"
  end

  def filter_folders(list)
    list.keep_if { |v| v =~ /Auto_user/ && !v.include?('_tn_') }
  end

  def filter_bam_only(list)
    list.keep_if { |v| v.end_with? '.bam' }
  end

  def transfer_bam_files(bam_list, folder)
    output_folder_path = "#{@output_path + folder}/"
    Net::SCP.start(@iontorrent_ip, @iontorrent_user, password: ENV['ION_PASS']) do |scp|
      bam_list.each do |bam|
        download_path = "#{@results_path + folder}/#{bam}"
        scp.download!(download_path, output_folder_path)
      end
    end
  end

  def transfer_json_file(folder)
    output_folder_path = "#{@output_path + folder}/"
    json_download_path = get_json_file_path folder
    Net::SCP.download!(@iontorrent_ip, @iontorrent_user, json_download_path, output_folder_path, ssh: { password: ENV['ION_PASS'] })
  end

  def process_json_file(json_file_path, folder)
    json_file = JSON.parse(File.read(json_file_path), symbolize_names: true)
    unless json_file.nil?
      json_file[:plan][:barcodedSamples].each do |sample|
        animal = { aliquot_id: nil, aliquot_id_alt: nil, full_path: '', folder_name: '', bam_file_name: '' }
        aliquot_ids = sample[0].to_s.split('_')
        animal[:aliquot_id] = aliquot_ids[0]
        animal[:aliquot_id_alt] = aliquot_ids[1]
        animal[:bam_file_name] = sample[1][:barcodeSampleInfo].keys[0].to_s
        animal[:full_path] = "#{@output_path + folder}/"
        animal[:folder_name] = folder
        @animal_results.add_animal_result animal
      end
    else
      @log.error("Problem with JSON file for #{folder}")
    end
  end

  def update_animals_from_animal_db(folder)
    animal_list = @animal_results.get_animals_for_folder(folder)
    animal_list.each do |animal|
      additional_animal_info = @oracle_db.get_animal_info animal
      @animal_results.update_animal_extra animal, additional_animal_info
    end
  end

  def export_csv(output_path, folder)
    data = @animal_results.get_animals_for_folder(folder).map(&:to_export)
    csv_path = "#{output_path + folder}/AnimalResults_#{DateTime.now.strftime("%Y%m%d%H%M%S")}.csv"
    CSV.open(csv_path, "wb") do |csv|
      csv << data.first.keys
      data.each do |hash|
        csv << hash.values
      end
    end
  end

end

Main.new.run