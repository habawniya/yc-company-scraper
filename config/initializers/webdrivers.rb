# config/initializers/webdrivers.rb
require 'webdrivers/chromedriver'

# Force webdrivers to use a specific Chromedriver version compatible with Chromium 140
Webdrivers::Chromedriver.required_version = '140.0.7339.185'
