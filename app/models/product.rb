class Product
  include ActiveModel::Model

  PRODUCT_TYPES = {
    dev: DevProduct,
    usr: UsrProduct
  }

  # TEMPLATE = "https://raw.githubusercontent.com/AweSim-OSC/rails-application-template/remote_source/awesim.rb"
  TEMPLATE = "/users/appl/jnicklas/Development/rails-application-template/awesim.rb"

  attr_accessor :name
  attr_accessor :found
  attr_accessor :title
  attr_accessor :description
  attr_accessor :git_remote

  validates :name, presence: true

  validate :app_does_not_exist, on: :create_app
  validates :git_remote, presence: true, if: "type == :usr", on: :create_app

  validate :manifest_is_valid, on: [:show_app, :list_apps]
  validate :gemfile_is_valid, on: :show_app

  def app_does_not_exist
    errors.add(:name, "already exists as an app") if !name.empty? && router.path.exist?
  end

  def manifest_is_valid
    errors.add(:manifest, "is missing, add a title and description to fix this") unless app.manifest.exist?
    errors.add(:manifest, "is corrupt, please edit the file to fix this") if app.manifest.exist? && !app.manifest.valid?
  end

  def gemfile_is_valid
    unless gemfile.exist? || gemfile_lock.exist?
      errors.add(:base, "App is missing <code>Gemfile</code>") unless gemfile.exist?
      errors.add(:base, "App is missing <code>Gemfile.lock</code>") unless gemfile_lock.exist?
      return
    end
    errors.add(:base, "Gemfile missing <code>rails_12factor</code> gem") unless gemfile_specs.detect {|s| s.name == "rails_12factor"}
    errors.add(:base, "Gemfile missing <code>dotenv-rails</code> gem") unless gemfile_specs.detect {|s| s.name == "dotenv-rails"}
    errors.add(:base, "Gemfile missing <code>ood_appkit</code> gem") unless gemfile_specs.detect {|s| s.name == "ood_appkit"}
  end

  class NotFound < StandardError; end

  class << self
    def build(arguments = {})
      type = arguments.delete(:type)
      raise ArgumentError, "Need to specify type of product" unless type
      PRODUCT_TYPES[type].new arguments
    end

    def all(type)
      PRODUCT_TYPES[type].all
    end

    def find(type, name)
      PRODUCT_TYPES[type].find(name)
    end
  end

  def app
    OodApp.new(router)
  end

  def gemfile
    router.path.join("Gemfile")
  end

  def gemfile_lock
    router.path.join("Gemfile.lock")
  end

  def gemfile_specs
    @gemfile_specs ||= Bundler::LockfileParser.new(File.read(gemfile_lock)).specs
  end

  def persisted?
    found
  end

  def new_record?
    !persisted?
  end

  def initialize(attributes={})
    super
    @found ||= false
    if persisted?
      @title ||= app.title
      @description ||= app.manifest.description
      @git_remote ||= get_git_remote
    end
  end

  def save
    if self.valid?(:create_app)
      stage && write_manifest
    else
      false
    end
  end

  def update(attributes)
    @title = attributes[:title] if attributes[:title]
    @description = attributes[:description] if attributes[:description]
    @git_remote = attributes[:git_remote] if attributes[:git_remote]
    if self.valid?
      write_manifest
      set_git_remote if git_remote != get_git_remote
      true
    else
      false
    end
  end

  def restart
    router.path.join("tmp").mkpath
    FileUtils.touch router.path.join("tmp", "restart.txt")
  end

  def destroy
    `kill -9 $(lsof -t #{router.path}) && sleep 1`
    FileUtils.rm_rf(router.path)
  end

  def permissions?
    true
  end

  def permissions(context)
    Permission.all(context, self)
  end

  def build_permission(context, attributes = {})
    Permission.build(attributes.merge(context: context, product: self))
  end

  def users
    permissions(:user)
  end

  def groups
    permissions(:group)
  end

  private
    def stage
      target = router.path
      target.mkpath
      if git_remote.blank?
        FileUtils.cp_r Rails.root.join("vendor/my_app/."), target
      else
        unless clone_git_repo(target)
          target.rmtree if target.exist?
          return false
        end
      end
      FileUtils.chmod 0750, target
      true
    rescue
      router.path.rmtree if router.path.exist?
      raise
    end

    def write_manifest
      File.open(router.path.join('manifest.yml'), 'w') do |f|
        f.write({
          'name' => title,
          'description' => description
        }.to_yaml)
      end if (!title.blank? || !description.blank?) || !router.path.join('manifest.yml').exist?
      true
    end

    def get_git_remote
      `cd #{router.path} 2> /dev/null && HOME="" git config --get remote.origin.url 2> /dev/null`.strip
    end

    def set_git_remote
      `cd #{router.path} 2> /dev/null && HOME="" git remote set-url origin #{git_remote} 2> /dev/null`
    end

    def clone_git_repo(target)
      o, s = Open3.capture2e({"HOME" => ""}, "git", "clone", git_remote, target.to_s)
      unless s.success?
        errors.add(:git_remote, "was unable to be cloned")
        Rails.logger.error(o)
        return false
      end
      true
    end
end
