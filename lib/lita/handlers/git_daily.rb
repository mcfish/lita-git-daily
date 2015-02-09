require 'systemu'

module Lita
  module Handlers
    class GitDaily < Handler

      config :repos, type: String
      config :github, type: String

      $release_list = nil

      route(/^@list$/,         :output_release_list )
      route(/^@release-open$/, :release_open        )
      route(/^@release-close/, :release_close       )
      route(/^@hotfix-open/,   :hotfix_open         )
      route(/^@hotfix-close/,  :hotfix_close        )
      route(/^@ok (.+)/,       :user_confirm        )
      route(/^@sync/,          :sync                )
      route(/^@status/,        :status              )
      route(/^@help/,          :help                )

      def git_exec(arg)
        Dir::chdir(config.repos)
        `yes | git #{arg}`.split("\n")
      end

      def get_status
        git_exec('branch -a').each do |br|
          return 'open'        if br.strip =~ /^remotes\/origin\/release\//
          return 'hotfix-open' if br.strip =~ /^remotes\/origin\/hotfix\//
        end
        return 'close'
      end

      def get_release_list
        status = get_status
        return {} if status == 'close'
        return $release_list unless $release_list.nil?
        $release_list = {}
        cmd = status == 'open' ? 'daily release list' : 'daily hotfix list'
        git_exec(cmd).each do |row|
          if row =~ /[0-9a-f]+ = .+/
            ci = row.split('=')
            $release_list[ci[1].strip] ||= []
            $release_list[ci[1].strip].push(ci[0].strip)
          end
        end
        $release_list
      end

      def output_release_list(response)
        count = 0
        get_release_list.each do |author,list|
          lines = []
          lines << "[#{author}]"
          list.each do |hash|
            count += 1
            lines << config.github + hash
          end
          response.reply indent_lines(lines)
        end
        response.reply '> Check list is clean.' unless count > 0
      end

      def release_open(response)
        response.reply '> Release process is already open!' and return if get_status == 'open'
        response.reply '> Hotfix process is already open!'  and return if get_status == 'hotfix-open'
        status, stdout, stderr = systemu 'git daily release open', :stdin => 'yes'
        if stderr
          err_lines = []
          stderr.split(/\n/).each do |row|
            err_lines << row if row =~ /fatal/
            err_lines << row if row =~ /error/i
          end
          response.reply indent_lines(err_lines)
        end

        lines = []
        stdout.split(/\n/).each do |row|
          next if row =~ /Confirm/
          next if row =~ /yN/
          lines << row
        end
        response.reply indent_lines(lines)

        output_release_list(response)
      end

      def release_close(response)
        return unless get_status == 'open'
        return response.reply '> Not finished test yet!' unless get_release_list.empty?
        output = false
        lines = []
        git_exec('daily release close').each do |row|
          output = true if row == 'push master to origin'
          lines << row if output
        end
        lines << 'Please deploy master branch to production servers.'
        response.reply indent_lines(lines)
        $release_list = nil
      end

      def hotfix_open(response)
        return response.reply '> Release process is already open!' if get_status == 'open'
        return response.reply '> Hotfix process is already open!'  if get_status == 'hotfix-open'
        # for hotfix
        lines = []
        git_exec('checkout master').each do |row|
          lines << row
        end

        status, stdout, stderr = systemu 'git daily hotfix open', :stdin => 'yes'
        if stderr
          err_lines = []
          stderr.split(/\n/).each do |row|
            err_lines << row if row =~ /fatal/
            err_lines << row if row =~ /error/i
          end
          response.reply indent_lines(err_lines)
        end

        stdout.split(/\n/).each do |row|
          next if row =~ /Confirm/
          next if row =~ /yN/
          lines << row
        end
        response.reply indent_lines(lines)
      end

      def hotfix_close(response)
        return unless get_status == 'hotfix-open'
        return response.reply '> Not finished test yet!' unless get_release_list.empty?
        output = false
        lines = []
        git_exec('daily hotfix close').each do |row|
          output = true  if row =~ /push/
          output = false if row =~ /Merge made/
          lines << row if output
        end

        # for hotfix
        git_exec('checkout develop').each do |row|
          lines << row
        end

        lines << 'Please deploy master branch to production servers.'
        response.reply indent_lines(lines)
        $release_list = nil
      end

      def user_confirm(response)
        author = response.matches.first.first
        return if $release_list.nil?
        if $release_list.key?(author)
          $release_list.delete(author)
          response.reply "> Has been approved. Thanks, #{response.user.mention_name}"
        else
          response.reply "> Unexpected commiter '#{author}'"
        end
      end

      def sync(response)
        status = get_status
        return response.reply '> Release process is not running!' if status == 'close'
        cmd = status == 'open' ? 'daily release sync' : 'daily hotfix sync'
        git_exec(cmd).each do |row|
          response.reply row
        end
        $release_list = nil
        output_release_list(response)
      end

      def status(response)
        response.reply "> Release process is '#{get_status}'"
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
        response.reply indent_lines(lines)
      end

      private

      def indent_lines(lines)
        ">>>" + lines.join("\n")
      end

    end

    Lita.register_handler(GitDaily)
  end
end
