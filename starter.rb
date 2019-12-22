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
      @opts.each do |name, value|
        args << "#{name}: #{value.inspect}"
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

comment_lines 'Gemfile', /^gem 'tzinfo-data'/

# 环境变量
add_gem 'dotenv-rails', '~> 2.7', '>= 2.7.5'
stage_two do
  %w[.env.development.local	.env.test.local	.env.production.local	.env.local].each do |fn|
    append_file '.gitignore', "#{fn}\n"
  end
  create_file '.env', <<~ENV
    # copy this file to .env.local for development
    # don't change this file!!!
    SITE_TITLE='#{@app_name.humanize.upcase}'
    COPYRIGHT='Tanmer Inc.'
    #{@app_name.upcase}_PGSQL_HOST=
    #{@app_name.upcase}_PGSQL_PORT=
    #{@app_name.upcase}_PGSQL_USERNAME=
    #{@app_name.upcase}_PGSQL_PASSWORD=
    #{@app_name.upcase}_PGSQL_DATABASE_PREFIX='#{@app_name}'
    SECRET_KEY_BASE=
    ELASTIC_APM_SERVER_URL=
    SENTRY_DSN=
    RELEASE_COMMIT=
  ENV

  create_file '.env.local.example', <<~ENV
    #{@app_name.upcase}_PGSQL_HOST='localhost'
    #{@app_name.upcase}_PGSQL_PORT='5432'
    #{@app_name.upcase}_PGSQL_USERNAME='#{ask_wizard('PGSQL 用户名')}'
    #{@app_name.upcase}_PGSQL_PASSWORD='#{ask_wizard('PGSQL 密码')}'
    SECRET_KEY_BASE=#{SecureRandom.hex(8)}
  ENV
end

# 数据库配置

stage_two do
  create_file 'config/database.yml', <<~YAML, force: true
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
add_gem 'pry-remote', '~> 0.1.8', group: %i[development test]

# 开发工具
add_gem 'guard-rails', '~> 0.8.1', group: :development
add_gem 'guard-bundler', '~> 2.2', '>= 2.2.1', group: :development
add_gem 'guard-livereload', '~> 2.5', '>= 2.5.2', group: :development
add_gem 'guard-rspec', '~> 4.7', '>= 4.7.3', group: :development
add_gem 'rubocop-tanmer', '~> 0.2.0', group: %i[development test], require: false
add_gem 'yard', '~> 0.9.20', group: %i[development]

stage_two do
  run 'guard init'
  append_file 'Guardfile', <<~RUBY.indent(2), after: "guard 'rails' do\n"
    ignore(%r{config/routes\.rb})
    ignore(%r{config/routes/})
    ignore(%r{config/locales/})
    ignore(%r{lib/templates/})
  RUBY

  gsub_file 'Guardfile', "guard 'rails' do", "guard 'rails', port: ENV['PORT'] || '3000' do"
  create_file '.rubocop.yml', <<~YAML
    require:
      - rubocop-rspec
      - rubocop-rails
    inherit_gem:
      rubocop-tanmer:
        - config/default.yml
    AllCops:
      TargetRubyVersion: 2.3
  YAML
  append_file '.gitignore', <<~TEXT
    /.yardoc
    /doc/
  TEXT
  create_file 'lib/tasks/yard.rake', <<~RUBY
    require 'yard'

    YARD::Rake::YardocTask.new do |t|
      t.files = [
        'app/**/*.rb',
        '-',
        'README.md'
      ]
      t.stats_options = ['--list-undoc']
    end
  RUBY
end

# 测试工具
add_gem 'rspec-rails', '~> 3.9', group: %i[development test]
add_gem 'factory_bot_rails', '~> 5.1', '>= 5.1.1', group: %i[development test]
add_gem 'shoulda-matchers', '~> 4.1', '>= 4.1.2', group: %i[development test]
add_gem 'simplecov', '~> 0.17.0', group: %i[development test]
add_gem 'database_cleaner', '~> 1.7', group: %i[development test]
add_gem 'capybara', '~> 3.29', group: %i[development test]

stage_two do
  generate 'rspec:install'
  append_file 'Rakefile', "load 'rspec/rails/tasks/rspec.rake'\n"
  append_file '.gitignore', "/coverage\n"
  uncomment_lines 'spec/rails_helper.rb', /'spec', 'support'/
  insert_into_file 'spec/rails_helper.rb', after: "ENV['RAILS_ENV'] ||= 'test'\n" do
    <<~RUBY
      if ENV['RAILS_ENV'] == 'test' && ENV['COVERAGE']
        require 'simplecov'
        SimpleCov.start 'rails'
      end
    RUBY
  end
  create_file 'spec/support/shoulda.rb', <<~RUBY
    require 'shoulda-matchers'
    Shoulda::Matchers.configure do |config|
      config.integrate do |with|
        with.test_framework :rspec
        with.library :rails
      end
    end
  RUBY
  create_file 'spec/support/factory_bot.rb', <<~RUBY
    RSpec.configure do |config|
      config.include FactoryBot::Syntax::Methods
    end
  RUBY
  comment_lines 'spec/rails_helper.rb', 'config.use_transactional_fixtures = true'
  create_file 'spec/support/database_cleaner.rb', <<~RUBY
    RSpec.configure do |config|
      config.use_transactional_fixtures = false
      config.before(:suite) do
        if config.use_transactional_fixtures?
          raise(<<-MSG)
            Delete line `config.use_transactional_fixtures = true` from rails_helper.rb
            (or set it to false) to prevent uncommitted transactions being used in
            JavaScript-dependent specs.

            During testing, the app-under-test that the browser driver connects to
            uses a different database connection to the database connection used by
            the spec. The app's database connection would not be able to access
            uncommitted transaction data setup over the spec's database connection.
          MSG
        end
        DatabaseCleaner.clean_with(:truncation)
      end

      config.before(:each) do
        DatabaseCleaner.strategy = :transaction
      end

      config.before(:each, type: :feature) do
        # :rack_test driver's Rack app under test shares database connection
        # with the specs, so continue to use transaction strategy for speed.
        driver_shares_db_connection_with_specs = Capybara.current_driver == :rack_test

        unless driver_shares_db_connection_with_specs
          # Driver is probably for an external browser with an app
          # under test that does *not* share a database connection with the
          # specs, so use truncation strategy.
          DatabaseCleaner.strategy = :truncation
        end
      end

      config.before(:each) do
        DatabaseCleaner.start
      end

      config.append_after(:each) do
        DatabaseCleaner.clean
      end
    end
  RUBY
end

# 配置通用组件

add_gem 'kaminari', '~> 1.1', '>= 1.1.1'
add_gem 'kaminari-i18n', '~> 0.5.0'
add_gem 'rails-i18n', '~> 6.0'
add_gem 'request_store', '~> 1.4', '>= 1.4.1'
add_gem 'strip_attributes', '~> 1.9'

# 配置 application
inject_into_file 'config/application.rb', after: /config.load_defaults.*\n/ do
  <<~RUBY.indent(4)
    config.i18n.default_locale = :'zh-CN'
    config.time_zone = 'Beijing'
    config.generators.assets = false
    config.generators.helper = false
    config.generators.stylesheets = false
    config.generators.jbuilder = false
    config.active_record.schema_format = :sql
    config.to_prepare do
      Dir.glob(Rails.root.join('app/loaders/**/*_loader.rb')).each do |file|
        load file
      end
    end
  RUBY
end

# 添加监控组件
add_gem 'elastic-apm', '~> 3.1', require: false
add_gem 'sentry-raven', '~> 2.12.2', require: false

stage_two do
  create_file 'config/initializers/elastic_apm.rb', <<~RUBY
    if ENV['ELASTIC_APM_SERVER_URL'].present?
      require 'elastic_apm'
      config.elastic_apm.service_name = "#{@app_name}-\#{Rails.env}"
    end
  RUBY
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

run 'yarn add bootstrap@4 --silent'
run 'yarn add jquery --silent'
run 'yarn add popper.js --silent'
run 'yarn upgrade --silent'

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

  create_file 'app/views/layouts/application.html.erb', <<~HTML, force: true
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

      <body class="theme-default">
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
    import './themes/default'
  JS
  create_file 'app/javascript/bootstrap-ui/themes/default/index.scss', <<~SCSS
    @import "~bootstrap/scss/functions";
    @import "~bootstrap/scss/mixins";
    @import './variable_inits';
    @import "~bootstrap/scss/variables";
    @import './variable_overrides';
    @import "~bootstrap/scss/root";
    @import "~bootstrap/scss/reboot";
    @import "~bootstrap/scss/type";
    @import "~bootstrap/scss/images";
    @import "~bootstrap/scss/code";
    @import "~bootstrap/scss/grid";
    @import "~bootstrap/scss/tables";
    @import "~bootstrap/scss/forms";
    @import "~bootstrap/scss/buttons";
    @import "~bootstrap/scss/transitions";
    @import "~bootstrap/scss/dropdown";
    @import "~bootstrap/scss/button-group";
    @import "~bootstrap/scss/input-group";
    @import "~bootstrap/scss/custom-forms";
    @import "~bootstrap/scss/nav";
    @import "~bootstrap/scss/navbar";
    @import "~bootstrap/scss/card";
    @import "~bootstrap/scss/breadcrumb";
    @import "~bootstrap/scss/pagination";
    @import "~bootstrap/scss/badge";
    @import "~bootstrap/scss/jumbotron";
    @import "~bootstrap/scss/alert";
    @import "~bootstrap/scss/progress";
    @import "~bootstrap/scss/media";
    @import "~bootstrap/scss/list-group";
    @import "~bootstrap/scss/close";
    @import "~bootstrap/scss/toasts";
    @import "~bootstrap/scss/modal";
    @import "~bootstrap/scss/tooltip";
    @import "~bootstrap/scss/popover";
    @import "~bootstrap/scss/carousel";
    @import "~bootstrap/scss/spinners";
    @import "~bootstrap/scss/utilities";
    @import "~bootstrap/scss/print";
    @import './component_overrides';
    @import './custom_styles';
  SCSS

  create_file 'app/javascript/bootstrap-ui/themes/default/_variable_inits.scss', <<~SCSS
    // 说明: 在读取 bootstrap/scss/variables 之前定义变量, 都放在这里

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

    $border-radius:               0.1rem;
    $border-radius-lg:            0.1rem;
    $border-radius-sm:            0.1rem;

  SCSS

  create_file 'app/javascript/bootstrap-ui/themes/default/_variable_overrides.scss', <<~SCSS
    // 说明: 在读取 bootstrap/scss/variables 之后覆盖变量, 都放在这里

    $input-focus-bg: rgba($input-focus-border-color, 0.15);
  SCSS

  create_file 'app/javascript/bootstrap-ui/themes/default/component_overrides/_index.scss', <<~SCSS
    // 覆盖 bootstrap 组件样式, 根据 bootstrap 源代码对应的文件名，在本目录创建一个文件，单独覆盖。
    // 然后统一在这个文件导入

    // @import "./buttons";
    // @import "./custom-forms";
  SCSS

  create_file 'app/javascript/bootstrap-ui/themes/default/_custom_styles.scss', <<~SCSS
    // 自定义样式, 放入这里

    main.container {
      margin-top: 46px;
    }
  SCSS

  prepend_to_file 'app/javascript/packs/application.js', <<~JS
    import "core-js/stable";
    import "regenerator-runtime/runtime";

  JS
  inject_into_file 'app/javascript/packs/application.js', after: "require(\"channels\")\n" do
    <<~JS

      window.$ = window.jQuery = jQuery
      import '../bootstrap-ui'
    JS
  end

  # 配置 webpacker
  inject_into_file 'config/webpacker.yml', after: /^development:[.\n]+? *<<: \*default\n/ do
    <<~YAML.indent(2)
      extract_css: true # this is for dev
    YAML
  end

  prepend_to_file 'config/webpack/environment.js', "// https://github.com/rails/webpacker/blob/master/docs/webpack.md\n"
  inject_into_file 'config/webpack/environment.js',
                   "const webpack = require('webpack')\n",
                   after: "const { environment } = require('@rails/webpacker')\n"
  inject_into_file 'config/webpack/environment.js', before: "module.exports = environment" do
    <<~JS
      environment.plugins.prepend(
        'Provide',
        new webpack.ProvidePlugin({
          $: 'jquery',
          jQuery: 'jquery',
          Popper: ['popper.js', 'default']
        })
      )
    JS
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

  create_file 'app/views/devise/sessions/new.html.erb', <<~HTML, force: true
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

stage_three do
  create_file 'README.md', <<~MARKDOWN
    # README

    This Rails project is composed by [tanmer-rails-starter](https://github.com/xiaohui-zhangxh/tanmer-rails-starter)

    ## 起步使用

    ## 开发

    ```shell
    # 启动 yard 文档，可查阅代码中的文档
    bundle exec yard server
    ````

    ### 定义 css 样式

    所有样式，尽可能都在 `app/javascript/bootstrap-ui` 的主题目录中定义，没有特别需求，不要在
    `app/assets/stylesheets` 目录中定义。

    ## 编译

    ## 测试

    ```shell
    # 测试
    bundle exec rspec
    # 测试并生产代码覆盖率统计
    COVERAGE=1 bundle exec rspec
    ```
    ## 发布
  MARKDOWN
end

# >-----------------------------[ Final Gemfile Write ]------------------------------<
Gemfile.write

# >-----------------------------[ Run 'Bundle Install' ]-------------------------------<
say_wizard "Installing gems. This will take a while."
Bundler.with_unbundled_env do
  run 'bundle install --quiet'
end
say_wizard "Updating gem paths."
Gem.clear_paths

Bundler.with_unbundled_env do
# >-----------------------------[ Run 'stage_two' Callbacks ]-------------------------------<

say_wizard "Stage Two (running recipe 'stage_two' callbacks)."
@after_blocks.each{|b| config = @configs[b[0]] || {}; @current_recipe = b[0]; puts @current_recipe; b[1].call}
end
