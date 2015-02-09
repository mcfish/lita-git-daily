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
          response.reply "[#{author}]"
          list.each do |hash|
            count += 1
            response.reply $githab + hash
          end
        end
        response.reply 'Check list is clean.' unless count > 0
      end

      def release_open(response)
        response.reply 'Release process is already open!' and return if get_status == 'open'
        response.reply 'Hotfix process is already open!'  and return if get_status == 'hotfix-open'
        status, stdout, stderr = systemu 'git daily release open', :stdin => 'yes'
        if stderr
          stderr.split(/\n/).each do |row|
            response.reply row if row =~ /fatal/
            response.reply row if row =~ /error/i
          end
        end

        stdout.split(/\n/).each do |row|
          next if row =~ /Confirm/
          next if row =~ /yN/
          response.reply row
        end

        output_release_list(response)
      end

      def release_close(response)
        return unless get_status == 'open'
        return response.reply 'Not finished test yet!' unless get_release_list.empty?
        output = false
        git_exec('daily release close').each do |row|
          output = true if row == 'push master to origin'
          response.reply row if output
        end
        response.reply 'Please deploy master branch to production servers.'
        $release_list = nil
      end

      def hotfix_open(response)
        return response.reply 'Release process is already open!' if get_status == 'open'
        return response.reply 'Hotfix process is already open!'  if get_status == 'hotfix-open'
        # for hotfix
        git_exec('checkout master').each do |row|
          response.reply row
        end

        status, stdout, stderr = systemu 'git daily hotfix open', :stdin => 'yes'
        if stderr
          stderr.split(/\n/).each do |row|
            response.reply row if row =~ /fatal/
            response.reply row if row =~ /error/i
          end
        end

        stdout.split(/\n/).each do |row|
          next if row =~ /Confirm/
          next if row =~ /yN/
          response.reply row
        end
      end

      def hotfix_close(response)
        return unless get_status == 'hotfix-open'
        return response.reply 'Not finished test yet!' unless get_release_list.empty?
        output = false
        git_exec('daily hotfix close').each do |row|
          output = true  if row =~ /push/
          output = false if row =~ /Merge made/
          response.reply row if output
        end

        # for hotfix
        git_exec('checkout develop').each do |row|
          response.reply row
        end

        response.reply 'Please deploy master branch to production servers.'
        $release_list = nil
      end

      def user_confirm(response)
        author = response.matches
        return if $release_list.nil?
        if $release_list.key?(author)
          $release_list.delete(author)
          response.reply "Has been approved. Thanks, #{m.user.nick}"
        else
          response.reply "Unexpected commiter '#{author}'"
        end
      end

      def sync(response)
        status = get_status
        return response.reply 'Release process is not running!' if status == 'close'
        cmd = status == 'open' ? 'daily release sync' : 'daily hotfix sync'
        git_exec(cmd).each do |row|
          response.reply row
        end
        $release_list = nil
        output_release_list(m)
      end

      def status(response)
        response.reply "Release process is '#{get_status}'"
      end

      def help(response)
        response.reply "@release-open:  git-daily open"
        response.reply "@release-close: git-daily close"
        response.reply "@hotfix-open:   git daily hotfix open"
        response.reply "@hotfix-close:  git daily hotfix close"
        response.reply "@list:          Show release list:"
        response.reply "@status:        Show release status"
        response.reply "@help:          Show this help"
        response.reply "about git daily https://github.com/koichiro/git-daily"
      end

    end

    Lita.register_handler(GitDaily)
  end
end
