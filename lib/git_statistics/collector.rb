module GitStatistics
  class Collector

    attr_accessor :repo, :repo_path, :commits_path, :commits, :verbose

    def initialize(verbose, limit, fresh, pretty)
      @verbose = verbose
      @repo = Utilities.get_repository

      raise "No Git repository found" if @repo.nil?

      @repo_path = File.expand_path("..", @repo.path) + File::Separator
      @commits_path = @repo_path + ".git_statistics" + File::Separator
      @commits = Commits.new(@commits_path, fresh, limit, pretty)
    end

    def collect(branch, time_since = "", time_until = "")
      # Create pipe for git log to acquire branches
      pipe = open("|git --no-pager branch --no-color")

      # Collect branches to use for git log
      branches = branch ? ["", ""] : collect_branches(pipe)

      # Create pipe for the git log to acquire commits
      pipe = open("|git --no-pager log #{branches.join(' ')} --date=iso --reverse"\
                  " --no-color --find-copies-harder --numstat --encoding=utf-8 "\
                  "--summary #{time_since} #{time_until} "\
                  "--format=\"%H,%an,%ae,%ad,%p\"")

      # Use a buffer approach to queue up lines from the log for each commit
      buffer = []
      pipe.each do |line|

        line = Utilities.clean_string(line)

        # Extract the buffer (commit) when we match ','x5 in the log format (delimeter)
        if line.split(',').size == 5

          # Sometimes 'git log' doesn't populate the buffer (i.e., merges), try fallback option if so
          buffer = fall_back_collect_commit(buffer[0].split(',').first) if buffer.one?

          extract_commit(buffer) if not buffer.empty?
          buffer = []

          # Save commits to file if size exceeds limit or forced
          @commits.flush_commits
          @repo = Utilities.get_repository
        end

        buffer << line
      end

      # Extract the last commit
      extract_commit(buffer) unless buffer.empty?
      @commits.flush_commits(true)
    end

    def fall_back_collect_commit(sha)
      # Create pipe for the git log to acquire commits
      pipe = open("|git --no-pager show #{sha} --date=iso --reverse"\
                  " --no-color --find-copies-harder --numstat --encoding=utf-8 "\
                  "--summary --format=\"%H,%an,%ae,%ad,%p\"")

      buffer = pipe.map { |line| Utilities.clean_string(line) }

      # Check that the buffer has valid information (i.e., sha was valid)
      if !buffer.empty? && buffer.first.split(',').first == sha
        buffer
      else
        nil
      end
    end

    def collect_branches(pipe)
      # Acquire all available branches from repository
      branches = []
      pipe.each do |line|

        # Remove the '*' leading the current branch
        line = line[1..-1] if line[0] == '*'
        branches << Utilities.clean_string(line)
      end

      return branches
    end

    def acquire_commit_data(line)
      # Split up formated line
      commit_info = line.split(',')

      # Initialize commit data
      data = (@commits[commit_info[0]] ||= Hash.new(0))
      data[:author] = commit_info[1]
      data[:author_email] = commit_info[2]
      data[:time] = commit_info[3]
      data[:files] = []

      # Flag commit as merge if necessary (determined if two parents)
      if commit_info[4].nil? || commit_info[4].split(' ').one?
        data[:merge] = false
      else
        data[:merge] = true
      end

      return {:sha => commit_info[0], :data => data}
    end

    def extract_commit(buffer)
      # Acquire general commit information
      commit_data = acquire_commit_data(buffer[0])

      puts "Extracting #{commit_data[:sha]}" if @verbose

      # Abort if the commit sha extracted form the buffer is invalid
      if commit_data[:sha].scan(/[\d|a-f]{40}/)[0].nil?
        puts "Invalid buffer containing commit information"
        return
      end

      # Identify all changed files for this commit
      files = identify_changed_files(buffer[2..-1])

      # No files were changed in this commit, abort commit
      if files.nil?
        puts "No files were changed"
        return
      end

      # Acquire blob for each changed file and process it
      files.each do |file|
        blob = get_blob(commit_data[:sha], file)

        # Only process blobs, or log the submodules and problematic files
        if blob.instance_of?(Grit::Blob)
          process_blob(commit_data[:data], blob, file)
        elsif blob.instance_of?(Grit::Submodule)
          puts "Ignoring submodule #{blob.name}"
        else
          puts "Problem processing file #{file[:file]}"
        end
      end
      return commit_data[:data]
    end

    def get_blob(sha, file)
      # Split up file for Grit navigation
      file = file[:file].split(File::Separator)

      # Acquire blob of the file for this specific commit
      blob = Utilities.find_blob_in_tree(@repo.tree(sha), file)

      # If we cannot find blob in current commit (deleted file), check previous commit
      if blob.nil? || blob.instance_of?(Grit::Tree)
        prev_commit = @repo.commits(sha).first.parents[0]
        return nil if prev_commit.nil?

        prev_tree = @repo.tree(prev_commit.id)
        blob = Utilities.find_blob_in_tree(prev_tree, file)
      end
      return blob
    end

    def identify_changed_files(buffer)
      return buffer if buffer.nil?

      # For each modification extract the details
      changed_files = []
      buffer.each do |line|

        # Extract changed file information if it exists
        data = extract_change_file(line)
        unless data.nil?
          changed_files << data
          next  # This line is processed, skip to next
        end

        # Extract details of create/delete files if it exists
        data = extract_create_delete_file(line)
        unless data.nil?
          augmented = false
          # Augment changed file with create/delete information if possible
          changed_files.each do |file|
            if file[:file] == data[:file]
              file[:status] = data[:status]
              augmented = true
              break
            end
          end
          changed_files << data if !augmented
          next  # This line is processed, skip to next
        end

        # Extract details of rename/copy files if it exists
        data = extract_rename_copy_file(line)
        unless data.nil?
          augmented = false
          # Augment changed file with rename/copy information if possible
          changed_files.each do |file|
            if file[:file] == data[:new_file]
              file[:status] = data[:status]
              file[:old_file] = data[:old_file]
              file[:similar] = data[:similar]
              augmented = true
              break
            end
          end
          changed_files << data if !augmented
          next  # This line is processed, skip to next
        end
      end
      return changed_files
    end

    def process_blob(data, blob, file)
      # Initialize a hash to hold information regarding the file
      file_hash = Hash.new(0)
      file_hash[:name] = file[:file]
      file_hash[:additions] = file[:additions]
      file_hash[:deletions] = file[:deletions]
      file_hash[:status] = file[:status]

      # Add file information to commit itself
      data[file[:status].to_sym] += 1 if file[:status] != nil
      data[:additions] += file[:additions]
      data[:deletions] += file[:deletions]

      # Acquire specifics on blob
      file_hash[:binary] = blob.binary?
      file_hash[:image] = blob.image?
      file_hash[:vendored] = blob.vendored?
      file_hash[:generated] = blob.generated?

      # Identify the language of the blob if possible
      file_hash[:language] = blob.language.nil? ? "Unknown" : blob.language.name
      data[:files] << file_hash

      return data
    end

    def extract_change_file(line)
      # Use regex to detect a rename/copy changed file | 1  2  /path/{test => new}/file.txt
      changes = line.scan(/^([-|\d]+)\s+([-|\d]+)\s+(.+)\s+=>\s+(.+)/)[0]
      changes = changes_are_right_size(changes, 4) do |changes|
        split_file = Utilities.split_old_new_file(changes[2], changes[3])
        {:additions => changes[0].to_i,
          :deletions => changes[1].to_i,
          :file => Utilities.clean_string(split_file[:new_file]),
          :old_file => Utilities.clean_string(split_file[:old_file])}
      end
      return changes unless changes.nil?

      # Use regex to detect a changed file | 1  2  /path/test/file.txt
      changes = line.scan(/^([-|\d]+)\s+([-|\d]+)\s+(.+)/)[0]
      changes_are_right_size(changes, 3) do |changes|
        {:additions => changes[0].to_i,
          :deletions => changes[1].to_i,
          :file => Utilities.clean_string(changes[2])}
      end
    end

    def extract_create_delete_file(line)
      # Use regex to detect a create/delete file | create mode 100644 /path/test/file.txt
      changes = line.scan(/^(create|delete) mode \d+ ([^\\\n]*)/)[0]
      changes_are_right_size(changes, 2) do |changes|
        {:status => Utilities.clean_string(changes[0]),
          :file => Utilities.clean_string(changes[1])}
      end
    end

    def extract_rename_copy_file(line)
      # Use regex to detect a rename/copy file | copy /path/{test => new}/file.txt
      changes = line.scan(/^(rename|copy)\s+(.+)\s+=>\s+(.+)\s+\((\d+)/)[0]
      changes_are_right_size(changes, 4) do |changes|
        split_file = Utilities.split_old_new_file(changes[1], changes[2])
        {:status => Utilities.clean_string(changes[0]),
          :old_file => Utilities.clean_string(split_file[:old_file]),
          :new_file => Utilities.clean_string(split_file[:new_file]),
          :similar => changes[3].to_i}
      end
    end

    def changes_are_right_size(changes, size = 4)
      if !changes.nil? && changes.size == size
        yield changes
      else
        nil
      end
    end
  end
end
