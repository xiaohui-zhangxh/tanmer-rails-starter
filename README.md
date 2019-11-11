# Tanmer Rails Starter

```shell
project_name=myapp
mkdir $project_name
cd $project_name
# 安装 ruby, 创建独立的 gem 集合
rvm use 2.6.3@$project_name --create --ruby-version
# 更新 bundler
gem install bundler
bundle config mirror.https://rubygems.org https://gems.ruby-china.com
# 安装 rails
gem install rails
# 生成 rails 项目
rails new . -d postgresql --skip-turbolinks --skip-test --skip-system-test --webpacker vue
# 提交 git 更改
git add .
git commit -m "init"
```

```shell
# 应用 tanmer rails starter
DISABLE_SPRING=1 LOCATION=https://raw.githubusercontent.com/xiaohui-zhangxh/tanmer-rails-starter/master/starter.rb rake app:template
```
