require 'securerandom'

module NginxStage
  # This generator stages and generates the per-user NGINX environment.
  class PunConfigGenerator < Generator
    desc 'Generate a new per-user nginx config and process'

    footer <<-EOF.gsub(/^ {4}/, '')
    Examples:
        To generate a per-user nginx environment & launch nginx:

            nginx_stage pun --user=bob --app-init-url='http://www.ood.com/nginx/init?redir=$http_x_forwarded_escaped_uri'

        this will add a URI redirect if the user accesses an app that doesn't exist.

        To generate ONLY the per-user nginx environment:

            nginx_stage pun --user=bob --skip-nginx

        this will return the per-user nginx config path and won't run nginx. In addition
        it will remove the URI redirect from the config unless we specify `--app-init-url`.
    EOF

    include PunConfigView

    # Accepts `user` as an option and validates user
    add_user_support


    # Block starting up PUNs for users with disabled shells
    # This is not relevant if running in a jail
    # We'll defer to the cluster to decide if an account is locked.
    add_hook :block_user_with_disabled_shell do
      next if !NginxStage.pun_jail_dir.nil?
      raise InvalidUser, "user has disabled shell: #{user}" if user.shell == NginxStage.disabled_shell
    end

    # Accepts `skip_nginx` as an option
    add_skip_nginx_support

    # @!method app_init_url
    #   The app initialization URL the user is redirected to if can't find the
    #   app in the per-user NGINX config
    #   @return [String] app init redirect url
    add_option :app_init_url do
      {
        opt_args: ["-a", "--app-init-url=APP_INIT_URL", "# The user is redirected to the APP_INIT_URL if app doesn't exist"],
        default: nil,
        before_init: -> (uri) do
          raise InvalidAppInitUri, "invalid app-init-url syntax: #{uri}" if uri =~ /[^-\w\/?$=&.:]/
          uri
        end
      }
    end

    # Create the user's personal per-user NGINX `/tmp` location for the various
    # nginx cache directories
    add_hook :create_user_tmp_root do
      empty_directory tmp_root
    end

    # Create the namespace for the user's PUN
    # Stash the pid of the process leader so
    # it can be used later.
    add_hook :create_namespace do
      next if NginxStage.pun_jail_dir.nil?
      (NginxStage.pun_jail_pid, NginxStage.pun_mount_pid) = create_namespace(user)
      warn "Jail " + NginxStage.pun_jail_pid
      warn "Mount" + NginxStage.pun_mount_pid
    end

    # Create the user's personal per-user NGINX `/log` location for the various
    # nginx log files (e.g., 'error.log' & 'access.log')
    add_hook :create_user_log_roots do
      empty_directory File.dirname(error_log_path)
      empty_directory File.dirname(access_log_path)
      if !NginxStage.pun_jail_dir.nil?
        FileUtils.touch(error_log_path)
        FileUtils.touch(access_log_path)
        assign_to_namespace(NginxStage.pun_jail_pid, error_log_path)
        assign_to_namespace(NginxStage.pun_jail_pid, access_log_path)
        bind_to_namespace(NginxStage.pun_mount_pid, error_log_path, '/root/.pun_state/logs/error.log')
        bind_to_namespace(NginxStage.pun_mount_pid, access_log_path, '/root/.pun_state/logs/access.log')
      end
    end

    # Create per-user NGINX pid root
    add_hook :create_pid_root do
      empty_directory File.dirname(pid_path)
      # if jailing, this isn't the nginx/passenger pid, it's the
      # process leader (pid = 1) in the namespace. kill this and everything gets cleaned.
      if !NginxStage.pun_jail_dir.nil?
        File.write(pid_path, NginxStage.pun_jail_pid)
      end
    end

    # Create and secure the nginx socket root. The socket file needs to be only
    # accessible by the reverse proxy user.
    add_hook :create_and_secure_socket_root do
      socket_root = File.dirname(socket_path)
      empty_directory socket_root
      FileUtils.chmod 0700, socket_root
      FileUtils.chown NginxStage.proxy_user, nil, socket_root if Process.uid == 0
      if !NginxStage.pun_jail_dir.nil?
        FileUtils.chmod 0750, socket_root
        assign_to_namespace(NginxStage.pun_jail_pid, socket_root)
        bind_to_namespace(NginxStage.pun_mount_pid, socket_root, '/root/.pun_state/run')
      end
    end

    # Generate per user secret_key_base file if it doesn't already exist
    add_hook :create_secret_key_base do
      begin
        secret = SecretKeyBaseFile.new(user)
        secret.generate unless secret.exist?
      rescue => e
        $stderr.puts "Failed to write secret to path: #{secret.path}"
        $stderr.puts e.message
        $stderr.puts e.backtrace
        abort
      end
      if !NginxStage.pun_jail_dir.nil?
        assign_to_namespace(NginxStage.pun_jail_pid, secret.path)
        bind_to_namespace(NginxStage.pun_mount_pid, secret.path, '/root/.pun_state/secret_key')
      end
    end

    # Generate the per-user NGINX config from the 'pun.conf.erb' template
    add_hook :create_config do
      template "pun.conf.erb", config_path if NginxStage.pun_jail_dir.nil?
      if !NginxStage.pun_jail_dir.nil?
        template "pun-jailed.conf.erb", config_path
        assign_to_namespace(NginxStage.pun_jail_pid, config_path)
        bind_to_namespace(NginxStage.pun_mount_pid, config_path, '/root/.pun_state/pun.conf')
      end
    end

    # Run the per-user NGINX process (exit quietly on success)
    add_hook :exec_nginx do
      next if !NginxStage.pun_jail_dir.nil?
      if !skip_nginx
        o, s = Open3.capture2e(
          NginxStage.nginx_env(user: user),
          [
            NginxStage.nginx_bin,
            "(#{user})"
          ],
          *NginxStage.nginx_args(user: user)
        )
        s.success? ? exit : abort(o)
      end
    end

    # If skip nginx, then output path to the generated per-user NGINX config
    add_hook :output_pun_config_path do
      next if !NginxStage.pun_jail_dir.nil?
      puts config_path
    end

    add_hook :dump_ns do
      puts enter_namespace(NginxStage.pun_jail_pid, 'find', ['/root', '-ls'])
    end

    private
      # per-user NGINX config path
      def config_path
        NginxStage.pun_config_path(user: user)
      end
  end
end
