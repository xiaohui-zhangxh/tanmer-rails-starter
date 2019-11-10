# frozen_string_literal: true

# >----------------------------[ Core script ]------------------------------<

module Gemfile
  class GemInfo
    def initialize(name) @name=name; @group=[]; @opts={}; end
    attr_accessor :name, :version
    attr_reader :group, :opts

    def opts=(new_opts={})
      new_group = new_opts.delete(:group)
      if (new_group && self.group != new_group)
        @group = ([self.group].flatten + [new_group].flatten).compact.uniq.sort
      end
      @opts = (self.opts || {}).merge(new_opts)
    end

    def group_key() @group end

    def gem_args_string
      args = ["'#{@name}'"]
      args << "'#{@version}'" if @version
      @opts.each do |name,value|
        args << ":#{name}=>#{value.inspect}"
      end
      args.join(', ')
    end
  end

  @geminfo = {}

  class << self
    # add(name, version, opts={})
    def add(name, *args)
      name = name.to_s
      version = args.first && !args.first.is_a?(Hash) ? args.shift : nil
      opts = args.first && args.first.is_a?(Hash) ? args.shift : {}
      @geminfo[name] = (@geminfo[name] || GemInfo.new(name)).tap do |info|
        info.version = version if version
        info.opts = opts
      end
    end

    def write
      File.open('Gemfile', 'a') do |file|
        file.puts
        grouped_gem_names.sort.each do |group, gem_names|
          indent = ""
          unless group.empty?
            file.puts "group :#{group.join(', :')} do" unless group.empty?
            indent="  "
          end
          gem_names.sort.each do |gem_name|
            file.puts "#{indent}gem #{@geminfo[gem_name].gem_args_string}"
          end
          file.puts "end" unless group.empty?
          file.puts
        end
      end
    end

    private
    #returns {group=>[...gem names...]}, ie {[:development, :test]=>['rspec-rails', 'mocha'], :assets=>[], ...}
    def grouped_gem_names
      {}.tap do |_groups|
        @geminfo.each do |gem_name, geminfo|
          (_groups[geminfo.group_key] ||= []).push(gem_name)
        end
      end
    end
  end
end
def add_gem(*all) Gemfile.add(*all); end

def say_custom(tag, text); say "\033[1m\033[36m" + tag.to_s.rjust(10) + "\033[0m" + "  #{text}" end
def say_loud(tag, text); say "\033[1m\033[36m" + tag.to_s.rjust(10) + "  #{text}" + "\033[0m" end
def say_recipe(name); say "\033[1m\033[36m" + "recipe".rjust(10) + "\033[0m" + "  Running #{name} recipe..." end
def say_wizard(text); say_custom(@current_recipe || 'composer', text) end

def ask_wizard(question)
  ask "\033[1m\033[36m" + ("option").rjust(10) + "\033[1m\033[36m" + "  #{question}\033[0m"
end

def whisper_ask_wizard(question)
  ask "\033[1m\033[36m" + ("choose").rjust(10) + "\033[0m" + "  #{question}"
end

def yes_wizard?(question)
  answer = ask_wizard(question + " \033[33m(y/n)\033[0m")
  case answer.downcase
    when "yes", "y"
      true
    when "no", "n"
      false
    else
      yes_wizard?(question)
  end
end

def no_wizard?(question); !yes_wizard?(question) end

def multiple_choice(question, choices)
  say_custom('option', "\033[1m\033[36m" + "#{question}\033[0m")
  values = {}
  choices.each_with_index do |choice,i|
    values[(i + 1).to_s] = choice[1]
    say_custom( (i + 1).to_s + ')', choice[0] )
  end
  answer = whisper_ask_wizard("Enter your selection:") while !values.keys.include?(answer)
  values[answer]
end

@current_recipe = nil
@configs = {}

@after_blocks = []
def stage_two(&block); @after_blocks << [@current_recipe, block]; end
@stage_three_blocks = []
def stage_three(&block); @stage_three_blocks << [@current_recipe, block]; end
@stage_four_blocks = []
def stage_four(&block); @stage_four_blocks << [@current_recipe, block]; end
@before_configs = {}
def before_config(&block); @before_configs[@current_recipe] = block; end

# this application template only supports Rails version 4.1 and newer
case Rails::VERSION::MAJOR.to_s
when "6"

else
  say_wizard "You are using Rails version #{Rails::VERSION::STRING} which is not supported. Use Rails 6"
  raise StandardError.new "Rails #{Rails::VERSION::STRING} is not supported. Use Rails 6"
end

# >----------------------------[ Core script end ]------------------------------<

@app_name = Rails.application.class.name.underscore.split('/').first

# init
# add_user

uncomment_lines 'Gemfile', /^gem 'tzinfo-data'/

# 环境变量
add_gem 'figaro', '~> 1.1', '>= 1.1.1'
stage_two do
  application_yml = <<~YAML
    SITE_TITLE: '#{@app_name.humanize.upcase}'
    COPYRIGHT: Tanmer Inc.
    #{@app_name.upcase}_PGSQL_HOST: localhost
    #{@app_name.upcase}_PGSQL_PORT: '5432'
    #{@app_name.upcase}_PGSQL_USERNAME: #{ask_wizard('PGSQL 用户名')}
    #{@app_name.upcase}_PGSQL_PASSWORD: #{ask_wizard('PGSQL 密码')}
    #{@app_name.upcase}_PGSQL_DATABASE_PREFIX: #{@app_name}

    SECRET_KEY_BASE:
    ELASTIC_APM_SERVER_URL:
    SENTRY_DSN:
    RELEASE_COMMIT:
  YAML

  create_file 'config/application.yml', application_yml
  create_file 'config/application.yml.example', application_yml
end

# 数据库配置

stage_two do
  remove_file 'config/database.yml'
  create_file 'config/database.yml', <<~YAML
    default: &default
      adapter: postgresql
      encoding: unicode
      pool: <%= ENV.fetch('RAILS_MAX_THREADS') { 5 } %>
      host: <%= ENV.fetch('#{app_name.upcase}_PGSQL_HOST') %>
      port: <%= ENV.fetch('#{app_name.upcase}_PGSQL_PORT') %>
      username: <%= ENV.fetch('#{app_name.upcase}_PGSQL_USERNAME') %>
      password: <%= ENV.fetch('#{app_name.upcase}_PGSQL_PASSWORD', nil) %>

    development:
      <<: *default
      database: <%= ENV.fetch('#{app_name.upcase}_PGSQL_DATABASE_PREFIX') %>_dev

    test:
      <<: *default
      database: <%= ENV.fetch('#{app_name.upcase}_PGSQL_DATABASE_PREFIX') %>_test

    production:
      <<: *default
      database: <%= ENV.fetch('#{app_name.upcase}_PGSQL_DATABASE_PREFIX') %>_prod
  YAML
end

# 调试工具
add_gem 'pry-rails', '~> 0.3.9', group: %i[development test]

# 开发工具
add_gem 'guard-rails', '~> 0.8.1', group: :development
add_gem 'guard-bundler', '~> 2.2', '>= 2.2.1', group: :development
add_gem 'guard-livereload', '~> 2.5', '>= 2.5.2', group: :development
add_gem 'rubocop', '~> 0.76.0', group: %i[development test], require: false
add_gem 'rubocop-rspec', '~> 1.36', group: %i[development test]

stage_two do
  run 'guard init'
  create_file '.rubocop.yml', <<~YAML
    AllCops:
      TargetRubyVersion: 2.3
  YAML
end

# 测试工具
add_gem 'rspec-rails', '~> 3.9', group: %i[development test]
stage_two do
  generate 'rspec:install'
end

# 配置 application
inject_into_file 'config/application.rb', after: /config.load_defaults.*\n/ do
  <<~RUBY.indent(4)
    config.i18n.default_locale = :'zh-CN'
    config.time_zone = 'Beijing'
    config.generators.assets = false
    config.generators.helper = false
    config.generators.stylesheets = false
    config.generators.jbuilder = false
  RUBY
end

# 添加监控组件
add_gem 'elastic-apm', '~> 3.1', require: false
stage_two do
  create_file 'config/initializers/elastic_apm.rb', <<~RUBY
    if ENV['ELASTIC_APM_SERVER_URL'].present?
      require 'elastic_apm'
      config.elastic_apm.service_name = "#{@app_name}-\#{Rails.env}"
    end
  RUBY
end

add_gem 'sentry-raven', '~> 2.12', '>= 2.12.2', require: false
stage_two do
  create_file 'config/initializers/sentry.rb', <<~RUBY
    require 'raven/base'
    if ENV['SENTRY_DSN'].present? && !(Rails.env.development? || Rails.env.test?)
      Raven.configure do |config|
        config.dsn = ENV['SENTRY_DSN']
        config.sanitize_fields = Rails.application.config.filter_parameters.map(&:to_s)
        config.release = ENV['RELEASE_COMMIT']
      end
      Raven.inject
    end
  RUBY
end

# 配置 UI

add_gem 'bootstrap_form', '~> 4.3'
add_gem 'meta-tags', '~> 2.13'

run 'yarn add bootstrap@4'
run 'yarn add jquery'
run 'yarn add popper.js'
run 'yarn upgrade'

stage_two do
  generate 'meta_tags:install'

  remove_file 'app/assets/stylesheets/application.css'
  create_file 'app/assets/stylesheets/application.scss', <<~SCSS
    /*
    *= require_self
    *= require_tree .
    */

    @import 'rails_bootstrap_forms';
  SCSS

  remove_file 'app/views/layouts/application.html.erb'
  create_file 'app/views/layouts/application.html.erb', <<~HTML
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
      <%= display_meta_tags site: ENV['SITE_TITLE'] %>
      <%= csrf_meta_tags %>
      <%= csp_meta_tag %>
      <%= stylesheet_pack_tag 'application' %>
      <%= stylesheet_link_tag 'application', media: 'all' %>
    </head>

    <body>
      <%= render 'layouts/top_nav' %>
      <main role="main" class="container">
        <%= yield %>
      </main>
      <%= render 'layouts/footer' %>
      <%= javascript_pack_tag 'application' %>
    </body>
  </html>
  HTML

  create_file 'app/views/layouts/_top_nav.html.erb', <<~HTML
    <nav class="navbar navbar-expand-md navbar-dark bg-dark fixed-top">
      <a class="navbar-brand" href="#">Navbar</a>
      <button class="navbar-toggler" type="button" data-toggle="collapse" data-target="#navbarsExampleDefault" aria-controls="navbarsExampleDefault" aria-expanded="false" aria-label="Toggle navigation">
        <span class="navbar-toggler-icon"></span>
      </button>

      <div class="collapse navbar-collapse" id="navbarsExampleDefault">
        <ul class="navbar-nav mr-auto">
          <li class="nav-item active">
            <a class="nav-link" href="#">Home <span class="sr-only">(current)</span></a>
          </li>
          <li class="nav-item">
            <a class="nav-link" href="#">Link</a>
          </li>
          <li class="nav-item">
            <a class="nav-link disabled" href="#" tabindex="-1" aria-disabled="true">Disabled</a>
          </li>
          <li class="nav-item dropdown">
            <a class="nav-link dropdown-toggle" href="#" id="dropdown01" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false">Dropdown</a>
            <div class="dropdown-menu" aria-labelledby="dropdown01">
              <a class="dropdown-item" href="#">Action</a>
              <a class="dropdown-item" href="#">Another action</a>
              <a class="dropdown-item" href="#">Something else here</a>
            </div>
          </li>
        </ul>
        <form class="form-inline my-2 my-lg-0">
          <input class="form-control mr-sm-2" type="text" placeholder="Search" aria-label="Search">
          <button class="btn btn-secondary my-2 my-sm-0" type="submit">Search</button>
        </form>
      </div>
    </nav>
  HTML

  create_file 'app/views/layouts/_footer.html.erb', <<~HTML
    <footer class="container-lg width-full px-3">
      <div class="position-relative d-flex flex-justify-between pt-6 pb-2 mt-6 f6 text-gray border-top border-gray-light ">
        <ul class="list-style-none d-flex flex-wrap">
          <li class="mr-3">© <%= Time.now.year %> <%= ENV['COPYRIGHT'] %></li>
        </ul>
      </div>
    </footer>
  HTML

  create_file 'app/javascript/bootstrap-ui/index.js', <<~JS
    import 'bootstrap'
    import './custom.scss'
  JS

  create_file 'app/javascript/bootstrap-ui/custom.scss', <<~SCSS
    @import "~bootstrap/scss/functions";
    @import "~bootstrap/scss/mixins";

    $font-family-sans-serif:
    // Safari for macOS and iOS (San Francisco)
    -apple-system,
    // Chrome < 56 for macOS (San Francisco)
    BlinkMacSystemFont,
    // Windows
    "Segoe UI",
    // Android
    "Roboto",
    // Basic web fallback
    "Helvetica Neue", Arial, sans-serif,
    // Emoji fonts
    "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol";

    $theme-colors: (
      "primary": #0074d9,
      // "primary": #4a9e7b,
      "danger": #ff4136
    );

    $grid-breakpoints: (
      xs: 0,
      sm: 576px,
      md: 768px,
      lg: 992px,
      xl: 1200px
    );

    $container-max-widths: (
      sm: 540px,
      md: 720px,
      lg: 960px,
      xl: 1140px
    );

    $grid-columns: 12;
    $grid-gutter-width: 30px;

    $font-size-base: 0.85rem;

    $line-height-base: 1;
    $line-height-lg: 1;
    $line-height-sm: 1;
    $input-padding-y: 0.25rem;
    $input-padding-x: 0.25rem;

    // $border-radius:               0.25rem;
    // $border-radius-lg:            0.3rem;
    // $border-radius-sm:            0.2rem;
    $border-radius:               0.1rem;
    $border-radius-lg:            0.1rem;
    $border-radius-sm:            0.1rem;

    // 以上是不需要用到 bootstrap/scss/variables 中的变量
    // 以下是需要用到 bootstrap/scss/variables 中的变量
    @import "~bootstrap/scss/variables";

    $input-focus-bg: rgba($input-focus-border-color, 0.15);

    @import '~bootstrap/scss/bootstrap';

    body {
      padding-top: 5rem;
    }
  SCSS

  inject_into_file 'app/javascript/packs/application.js', after: "require(\"channels\")\n" do
    <<~JS
      import '../bootstrap-ui'
    JS
  end

  inject_into_file 'config/webpacker.yml', after: /^development:[.\n]+? *<<: \*default\n/ do
    <<~YAML.indent(2)
      extract_css: true
    YAML
  end
end

# 用户登录
add_gem 'devise', '~> 4.7', '>= 4.7.1'
add_gem 'devise-i18n', '~> 1.8', '>= 1.8.2'

stage_two do
  generate "devise:install"
  inject_into_file 'config/environments/development.rb',
                   "  config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }",
                   after: "config.action_mailer.perform_caching = false\n"
  generate 'devise user'
  generate 'devise:views'
  generate 'devise:i18n:views -f'
  generate 'devise:i18n:locale zh-CN'

  remove_file 'app/views/devise/sessions/new.html.erb'
  create_file 'app/views/devise/sessions/new.html.erb', <<~HTML
    <h2><%= t('.sign_in') %></h2>
    <%= bootstrap_form_for(resource, as: resource_name, url: session_path(resource_name)) do |f| %>
      <%= f.email_field :email, autofocus: true, autocomplete: "email" %>
      <%= f.password_field :password, autocomplete: "current-password" %>
      <%= f.form_group do %>
        <%= f.check_box :remember_me, custom: :switch %>
      <% end %>
      <%= f.form_group do %>
        <%= f.submit t('.sign_in') %>
      <% end %>
    <% end %>
    <%= render "devise/shared/links" %>
  HTML
end

# >-----------------------------[ Final Gemfile Write ]------------------------------<
Gemfile.write

# >-----------------------------[ Run 'Bundle Install' ]-------------------------------<
say_wizard "Installing gems. This will take a while."
Bundler.with_clean_env do
  run 'bundle install --without production --quiet'
end
say_wizard "Updating gem paths."
Gem.clear_paths

Bundler.with_clean_env do
# >-----------------------------[ Run 'stage_two' Callbacks ]-------------------------------<

say_wizard "Stage Two (running recipe 'stage_two' callbacks)."
@after_blocks.each{|b| config = @configs[b[0]] || {}; @current_recipe = b[0]; puts @current_recipe; b[1].call}
end
