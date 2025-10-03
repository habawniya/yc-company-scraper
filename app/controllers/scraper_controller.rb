# app/controllers/scraper_controller.rb
require 'ferrum'
require 'nokogiri'
require 'cgi'
require 'csv'
require 'open-uri'
require 'concurrent'

class ScraperController < ApplicationController
  def ycombinator
    browser = Ferrum::Browser.new(timeout: 60)
    browser.goto(filtered_url)

    companies = []
    company_links = []

    # STEP 1: Scroll until limit reached
    loop do
      browser.evaluate("window.scrollBy(0, document.body.scrollHeight)")
      sleep 1

      html = Nokogiri::HTML(browser.body)

      html.css("a._company_i9oky_355").each do |company_data|
        name = company_data.at_css("span._coName_i9oky_470")&.text&.strip
        location = company_data.at_css("span._coLocation_i9oky_486")&.text&.strip
        description = company_data.at_css("div[class='mb-1.5 text-sm'] span")&.text&.strip
        batch = company_data.at_css("div[class='_pillWrapper_i9oky_33'] span[class*='pill']")&.text&.strip

        companies << {
          name: name,
          location: location,
          description: description,
          batch: batch
        }

        company_links << company_data["href"]

        break if limit_reached?(companies)
      end

      break if limit_reached?(companies)
    end
    
    # STEP 2: Fetch company detail pages with thread pool (max 10 at a time)
    pool = Concurrent::FixedThreadPool.new(10)

    companies.each_with_index do |company, index|
      pool.post do
        begin
          relative_url = company_links[index]
          full_url = "https://www.ycombinator.com#{relative_url}"
           sleep 0.5

          detail_html = Nokogiri::HTML(
            URI.open(full_url, ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE)
          )

          # Website
          website = detail_html.at_css(
            "a.flex.h-9.w-9.items-center.justify-center.rounded-md.border.bg-white[href^='http']:not([href*='linkedin.com'])"
          )&.[]("href")

          # Founders
          founders = detail_html.css("div.flex.flex-row.items-center.gap-x-2").map do |block|
            founder_name = block.at_css("div.text-xl.font-bold")&.text&.strip
            linkedin = block.at_css("div.flex.gap-x-1.flex a[href*='linkedin.com']")&.[]("href")
            { name: founder_name, linkedin: linkedin }
          end

          company[:website] = website
          company[:founders] = founders
        rescue => e
          Rails.logger.error "Error fetching #{full_url}: #{e.message}"
          company[:website] = nil
          company[:founders] = []
        end
      end
    end

    pool.shutdown
    pool.wait_for_termination

    # STEP 3: Convert to CSV
    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["Name", "Location", "Description", "Batch", "Website", "Founders"]

      companies.each do |company|
        founders_info = company[:founders]&.map { |f| "#{f[:name]} (#{f[:linkedin]})" }&.join("; ")
        csv << [
          company[:name],
          company[:location],
          company[:description],
          company[:batch],
          company[:website],
          founders_info
        ]
      end
    end

    # puts companies.count
    send_data csv_data, filename: "ycombinator_companies.csv"
  ensure
    browser&.quit
  end

  private

  BASE_URL = "https://www.ycombinator.com/companies"

  def filters
    params[:filters]&.permit(
      :regions, :batch, :industry, :team_size, :isHiring, :nonprofit, :top_company
    )&.to_h || {}
  end

  def limit
    params[:n]&.to_i
  end

  def filtered_url
    return BASE_URL if filters.empty?

    query = filters.map do |key, value|
      value = value.is_a?(Array) ? value.to_json : value.to_s
      "#{key}=#{CGI.escape(value)}"
    end.join("&")

    "#{BASE_URL}?#{query}"
  end

  def limit_reached?(companies)
    limit && companies.size >= limit
  end
end
