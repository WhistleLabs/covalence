require 'open3'
require 'highline'

require_relative '../../../covalence'

module Covalence
  class PopenWrapper
    class << self

      def run(cmds, path, args,
              stdin_io: STDIN,
              stdout_io: STDOUT,
              stderr_io: STDERR,
              debug: Covalence::DEBUG_CLI,
              dry_run: false,
              ignore_exitcode: false)

        # TODO: implement path prefix for the docker runs, see @tf_cmd
        cmd_string = [*cmds]
        # TODO: cmd escape issues with -var.
        cmd_string += [*args] unless args.blank?
        cmd_string << path unless path.blank?

        #TODO debug command string maybe
        #TODO debug command args maybe

        run_cmd = cmd_string.join(' ')
        print_cmd_string(run_cmd)
        if dry_run
          run_cmd = Covalence::DRY_RUN_CMD
        end

        if debug
          return 0 unless HighLine.new.agree('Execute? [y/n]')
        end

        spawn_subprocess(ENV, run_cmd, {
          stdin_io: stdin_io,
          stdout_io: stdout_io,
          stderr_io: stderr_io,
          ignore_exitcode: ignore_exitcode
        })
      end

      def logger
        Covalence::LOGGER
      end

      def run_in_workdir(cmds, path, args, workdir,
                         stdin_io: STDIN,
                         stdout_io: STDOUT,
                         stderr_io: STDERR,
                         debug: Covalence::DEBUG_CLI,
                         dry_run: false,
                         ignore_exitcode: false)

        logger.info "#{path} cmds: #{cmds}, path: #{path}, args: #{args}, workdir: #{workdir}"
        # TODO: implement path prefix for the docker runs, see @tf_cmd
        cmd_string = [*cmds]
        # TODO: cmd escape issues with -var.
        cmd_string += [*args] unless args.blank?
        ## cmd_string << path unless path.blank?

        run_cmd = cmd_string.join(' ')
        print_cmd_string(run_cmd)
        if dry_run
          run_cmd = Covalence::DRY_RUN_CMD
        end

        if debug
          return 0 unless HighLine.new.agree('Execute? [y/n]')
        end

        spawn_subprocess_with_workdir(ENV, run_cmd, workdir, path,{
            stdin_io: stdin_io,
            stdout_io: stdout_io,
            stderr_io: stderr_io,
            ignore_exitcode: ignore_exitcode
        })
      end

      private
      def print_cmd_string(cmd_string)
        Covalence::LOGGER.warn "---"
        Covalence::LOGGER.warn cmd_string
      end

      def spawn_subprocess_with_workdir(env, run_cmd, workdir, path,
                           stdin_io: STDIN,
                           stdout_io: STDOUT,
                           stderr_io: STDERR,
                           ignore_exitcode: false)

        logger.info "#{path} run_cmd: #{run_cmd}"
        Signal.trap("INT") {} #Disable parent process from exiting, orphaning the child fork below
        wait_thread = nil
        prefix=path.gsub(/^\/workspace*/,'')
        Open3.popen3(env, "prefixout -p '#{prefix} ' -- " + run_cmd, :chdir=>workdir) do |stdin, stdout, stderr, wait_thr|
          mappings = { stdin_io => stdin, stdout => stdout_io, stderr => stderr_io }
          wait_thread = wait_thr

          Signal.trap("INT") {
            Process.kill("INT", wait_thr.pid)
            Process.wait(wait_thr.pid, Process::WNOHANG)
            exit(wait_thr.value.exitstatus)
          } # let SIGINT drop into the child process

          handle_io_streams(mappings, stdin_io)
        end

        Signal.trap("INT") { exit } #Restore parent SIGINT

        return 0 if ignore_exitcode
        exit(wait_thread.value.exitstatus) unless wait_thread.value.success?
        return wait_thread.value.exitstatus
      end

      def spawn_subprocess(env, run_cmd,
                           stdin_io: STDIN,
                           stdout_io: STDOUT,
                           stderr_io: STDERR,
                           ignore_exitcode: false)
        Signal.trap("INT") {} #Disable parent process from exiting, orphaning the child fork below
        wait_thread = nil

        Open3.popen3(env, run_cmd) do |stdin, stdout, stderr, wait_thr|
          mappings = { stdin_io => stdin, stdout => stdout_io, stderr => stderr_io }
          wait_thread = wait_thr

          Signal.trap("INT") {
            Process.kill("INT", wait_thr.pid)
            Process.wait(wait_thr.pid, Process::WNOHANG)

            exit(wait_thr.value.exitstatus)
          } # let SIGINT drop into the child process

          handle_io_streams(mappings, stdin_io)
        end

        Signal.trap("INT") { exit } #Restore parent SIGINT

        return 0 if ignore_exitcode
        exit(wait_thread.value.exitstatus) unless wait_thread.value.success?
        return wait_thread.value.exitstatus
      end

      def handle_io_streams(mappings, stdin_io)
        inputs = mappings.keys
        streams_ready_for_eof_check = []

        until inputs.empty? || (inputs.size == 1 && inputs.first == stdin_io) do

          readable_inputs, _ = IO.select(inputs, [], [])
          streams_ready_for_eof_check = readable_inputs

          streams_ready_for_eof_check.select(&:eof).each do |src|
            Covalence::LOGGER.debug "Stopping redirection from an IO in EOF: " + src.inspect
            # `select`ing an IO which has reached EOF blocks forever.
            # So you have to delete such IO from the array of IOs to `select`.
            inputs.delete src

            # You must close the child process' STDIN immeditely after the parent's STDIN reached EOF,
            # or some kinds of child processes never exit.
            # e.g.) echo foobar | joumae run -- cat
            # After the `echo` finished outputting `foobar`, you have to tell `cat` about that or `cat` will wait for more inputs forever.
            mappings[src].close if src == stdin_io
          end

          break if inputs.empty? || (inputs.size == 1 && inputs.first == stdin_io)

          readable_inputs.each do |input|
            begin
              data = input.read_nonblock(1024)
              output = mappings[input]
              output.write(data)
              output.flush
            rescue EOFError => e
              Covalence::LOGGER.debug "Reached EOF: #{e}"
              inputs.delete input
            rescue Errno::EPIPE => e
              Covalence::LOGGER.debug "Handled error: #{e}: io: #{input.inspect}"
              inputs.delete input
            end
          end #readable_inputs
        end #until inputs.empty?
      end #handle_io_streams

    end
  end
end
