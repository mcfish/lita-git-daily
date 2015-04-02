require 'systemu'
module Lita
  module Handlers
    class GitDaily < Handler

      config :channel_config, type: Hash

      on(:connected) do |payload|
        $git_config = config.channel_config.map do |room_id, hash|
          [ room_id, hash.merge({:release_list => nil}) ]
        end.to_h
      end

      route(/^@list$/,         :output_release_list )
      route(/^@release-open$/, :release_open        )
      route(/^@release-close/, :release_close       )
      route(/^@hotfix-open/,   :hotfix_open         )
      route(/^@hotfix-close/,  :hotfix_close        )
      route(/^@ok (.+)/,       :user_confirm        )
      route(/^@sync/,          :sync                )
      route(/^@status/,        :status              )
      route(/^@help/,          :help                )

      def git_exec(arg, repos)
        Dir::chdir(repos)
        `yes | git #{arg}`.split("\n")
      end

      def get_status(repos)
        git_exec('branch -a', repos).each do |br|
          return 'open'        if br.strip =~ /^remotes\/origin\/release\//
          return 'hotfix-open' if br.strip =~ /^remotes\/origin\/hotfix\//
        end
        return 'close'
      end

      def get_release_list(response)
        room_id = response.message.source.room
        repos  = $git_config[room_id][:repos]
        status = get_status(repos)
        return {} if status == 'close'
        return $git_config[room_id][:release_list] unless $git_config[room_id][:release_list].nil?
        $git_config[room_id][:release_list] = {}
        cmd = status == 'open' ? 'daily release list' : 'daily hotfix list'
        git_exec(cmd, repos).each do |row|
          if row =~ /[0-9a-f]+ = .+/
            ci = row.split('=')
            $git_config[room_id][:release_list][ci[1].strip] ||= []
            $git_config[room_id][:release_list][ci[1].strip].push(ci[0].strip)
          end
        end
        $git_config[room_id][:release_list]
      end

      def output_release_list(response)
        count = 0
        get_release_list(response).each do |author,list|
          lines = []
          lines << "[#{author}]"
          list.each do |hash|
            count += 1
            lines << $git_config[response.message.source.room][:github] + hash
          end
          reply_indent_lines(response, lines)
        end
        response.reply '> Check list is clean.' unless count > 0
      end

      def release_open(response)
        status = get_status($git_config[response.message.source.room][:repos])
        response.reply '> Release process is already open!' and return if status == 'open'
        response.reply '> Hotfix process is already open!'  and return if status == 'hotfix-open'
        status, stdout, stderr = systemu 'git daily release open', :stdin => 'yes'
        if stderr
          err_lines = []
          stderr.split(/\n/).each do |row|
            err_lines << row if row =~ /fatal/
            err_lines << row if row =~ /error/i
          end
          reply_indent_lines(response, err_lines)
        end

        lines = []
        stdout.split(/\n/).each do |row|
          next if row =~ /Confirm/
          next if row =~ /yN/
          lines << row
        end
        reply_indent_lines(response, lines)

        output_release_list(response)
      end

      def release_close(response)
        repos = $git_config[response.message.source.room][:repos]
        return unless get_status(repos) == 'open'
        return response.reply '> Not finished test yet!' unless get_release_list(response).empty?
        output = false
        lines = []
        git_exec('daily release close', repos).each do |row|
          output = true if row == 'push master to origin'
          lines << row if output
        end
        lines << 'Please deploy master branch to production servers.'
        reply_indent_lines(response, lines)
        $git_config[response.message.source.room][:release_list] = nil
      end

      def hotfix_open(response)
        repos  = $git_config[response.message.source.room][:repos]
        status = get_status(repos)
        return response.reply '> Release process is already open!' if status == 'open'
        return response.reply '> Hotfix process is already open!'  if status == 'hotfix-open'
        # for hotfix
        lines = []
        git_exec('checkout master', repos).each do |row|
          lines << row
        end

        status, stdout, stderr = systemu 'git daily hotfix open', :stdin => 'yes'
        if stderr
          err_lines = []
          stderr.split(/\n/).each do |row|
            err_lines << row if row =~ /fatal/
            err_lines << row if row =~ /error/i
          end
          reply_indent_lines(response, err_lines)
        end

        stdout.split(/\n/).each do |row|
          next if row =~ /Confirm/
          next if row =~ /yN/
          lines << row
        end
        reply_indent_lines(response, lines)
      end

      def hotfix_close(response)
        repos = $git_config[response.message.source.room][:repos]
        return unless get_status(repos) == 'hotfix-open'
        return response.reply '> Not finished test yet!' unless get_release_list(response).empty?
        output = false
        lines = []
        git_exec('daily hotfix close', repos).each do |row|
          output = true  if row =~ /push/
          output = false if row =~ /Merge made/
          lines << row if output
        end

        # for hotfix
        git_exec('checkout develop', repos).each do |row|
          lines << row
        end

        lines << 'Please deploy master branch to production servers.'
        reply_indent_lines(response, lines)
        $git_config[response.message.source.room][:release_list] = nil
      end

      def user_confirm(response)
        author  = response.matches.first.first
        room_id = response.message.source.room
        return if $git_config[room_id][:release_list].nil?
        if $git_config[room_id][:release_list].key?(author)
          $git_config[room_id][:release_list].delete(author)
          response.reply "> Has been approved. Thanks, #{response.user.mention_name}"
        else
          response.reply "> Unexpected commiter '#{author}'"
        end
      end

      def sync(response)
        repos  = $git_config[response.message.source.room][:repos]
        status = get_status(repos)
        return response.reply '> Release process is not running!' if status == 'close'
        cmd = status == 'open' ? 'daily release sync' : 'daily hotfix sync'
        lines = []
        git_exec(cmd, repos).each do |row|
          lines << row
        end
        reply_indent_lines(response, lines)
        $git_config[response.message.source.room][:release_list] = nil
        output_release_list(response)
      end

      def status(response)
        response.reply "> Release process is '#{get_status($git_config[response.message.source.room][:repos])}'"
      end

      def help(response)
        lines = []
        lines << "@release-open:  git-daily open"
        lines << "@release-close: git-daily close"
        lines << "@hotfix-open:   git daily hotfix open"
        lines << "@hotfix-close:  git daily hotfix close"
        lines << "@list:          Show release list:"
        lines << "@status:        Show release status"
        lines << "@help:          Show this help"
        reply_indent_lines(response, lines)
      end

      private

      def reply_indent_lines(response, lines)
        return if lines.size == 0
        response.reply(">>>" + lines.join("\n"))
      end

    end

    Lita.register_handler(GitDaily)
  end
end
