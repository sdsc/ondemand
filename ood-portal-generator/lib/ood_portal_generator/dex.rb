require 'active_support'
require 'active_support/core_ext'
require 'digest/sha1'
require 'fileutils'

module OodPortalGenerator
  # A view class that renders a Dex configuration
  class Dex
    # @param opts [#to_h] the options describing the context used to render the Dex config
    def initialize(opts = {}, view)
      opts = opts.to_h.each_with_object({}) { |(k, v), h| h[k.to_sym] = v unless v.nil? }
      config = opts.fetch(:dex, {})
      if config.nil? || config == false
        @enable = false
        return
      else
        @enable = true
      end
      ssl = config.fetch(:ssl, !view.ssl.nil?)
      protocol = ssl ? "https://" : "http://"
      servername = view.servername || OodPortalGenerator.fqdn
      http_port = config.fetch(:http_port, "5556")
      https_port = config.fetch(:https_port, "5554")
      port = ssl ? https_port : http_port
      @dex_config = {}
      @dex_config[:issuer] = "#{protocol}#{servername}:#{port}"
      @dex_config[:storage] = {
        type: 'sqlite3',
        config: { file: config.fetch(:storage_file, File.join(self.class.config_dir, 'dex.db')) },
      }
      @dex_config[:web] = {
        http: "0.0.0.0:#{http_port}",
      }
      @dex_config[:web][:https] = "0.0.0.0:#{https_port}" if ssl
      tls_cert = config.fetch(:tls_cert, nil)
      tls_key = config.fetch(:tls_key, nil)
      if ssl && ! view.ssl.nil? && tls_cert.nil? && tls_key.nil?
        view.ssl.each do |ssl_line|
          items = ssl_line.split(' ', 2)
          next unless items.size == 2
          value = items[1].gsub(/"|'/, '')
          newpath = File.join(self.class.config_dir, File.basename(value))
          case items[0].downcase
          when 'sslcertificatefile'
            tls_cert = newpath
          when 'sslcertificatekeyfile'
            tls_key = newpath
          else
            next
          end
          if File.exists?(value)
            FileUtils.cp(value, newpath, preserve: true, verbose: true)
            FileUtils.chown(OodPortalGenerator.dex_user, OodPortalGenerator.dex_group, newpath, verbose: true)
          end
        end
      end
      @dex_config[:web][:tlsCert] = tls_cert unless tls_cert.nil?
      @dex_config[:web][:tlsKey] = tls_key unless tls_key.nil?
      grpc = config.fetch(:grpc, nil)
      @dex_config[:grpc] = grpc unless grpc.nil?
      expiry = config.fetch(:expiry, nil)
      @dex_config[:expiry] = expiry unless expiry.nil?
      @dex_config[:telemetry] = { http: '0.0.0.0:5558' }
      client_protocol = view.protocol
      if view.port && ['443','80'].include?(view.port.to_s)
        client_port = ''
      else
        client_port = ":#{view.port}"
      end
      client_id = view.servername || OodPortalGenerator.fqdn
      client_redirect_uri = "#{client_protocol}#{client_id}#{client_port}/oidc"
      client_name = config.fetch(:client_name, "OnDemand")
      client_secret = config.fetch(:client_secret, Digest::SHA1.hexdigest(client_id))
      @dex_config[:staticClients] = [{
        id: client_id,
        redirectURIs: [client_redirect_uri],
        name: client_name,
        secret: client_secret,
      }]
      connectors = config.fetch(:connectors, nil)
      @dex_config[:connectors] = connectors unless connectors.nil?
      @dex_config[:oauth2] = { skipApprovalScreen: true }
      @dex_config[:enablePasswordDB] = connectors.nil?
      if connectors.nil?
        @dex_config[:staticPasswords] = [{
          email: 'ood@localhost',
          hash: '$2a$10$2b2cU8CPhOTaGrs1HRQuAueS7JTT5ZHsHSzYiFPm1leZck7Mc8T4W',
          username: 'ood',
          userID: '08a8684b-db88-4b73-90a9-3cd1661f5466',
        }]
      end
      frontend = config.fetch(:frontend, nil)
      @dex_config[:frontend] = frontend unless frontend.nil?
      if enabled? && self.class.installed?
        view.oidc_uri = '/oidc'
        view.oidc_redirect_uri = client_redirect_uri
        view.oidc_provider_metadata_url = "#{@dex_config[:issuer]}/.well-known/openid-configuration"
        view.oidc_client_id = client_id
        view.oidc_remote_user_claim = 'email' if connectors.nil?
        view.oidc_client_secret = client_secret
        view.logout_redirect = "/oidc?logout=#{client_protocol}#{client_id}#{client_port}".gsub('://', '%3A%2F%2F')
      end
    end

    # Render the config as a YAML string
    # @return [String] YAML string
    def render
      config = @dex_config.deep_transform_keys!(&:to_s)
      config.to_yaml
    end

    def enabled?
      !!@enable
    end

    def self.installed?
      File.directory?(config_dir) && File.executable?('/usr/local/bin/ondemand-dex')
    end

    def self.config_dir
      '/etc/ood/dex'
    end
  end
end
