# spec/controllers/scraper_controller_spec.rb
require 'rails_helper'
require 'stringio'
require 'concurrent'

RSpec.describe ScraperController, type: :controller do
  describe "GET #ycombinator" do
    let(:browser_double) { instance_double(Ferrum::Browser) }
    let(:html_body) do
      '<html>
        <a class="_company_i9oky_355" href="/companies/test-co">
          <span class="_coName_i9oky_470">Test Co</span>
          <span class="_coLocation_i9oky_486">NY, USA</span>
          <div class="mb-1.5 text-sm"><span>Awesome startup</span></div>
          <div class="_pillWrapper_i9oky_33"><span class="pill">Winter 2024</span></div>
        </a>
      </html>'
    end

    let(:detail_html_body) do
      '<html>
        <a class="flex h-9 w-9 items-center justify-center rounded-md border bg-white" href="https://testco.com"></a>
        <div class="flex flex-row items-center gap-x-2">
          <div class="text-xl font-bold">Alice Founder</div>
          <div class="flex gap-x-1 flex">
            <a href="https://linkedin.com/in/alice">LinkedIn</a>
          </div>
        </div>
      </html>'
    end

    before do
      # Mock Ferrum browser
      allow(Ferrum::Browser).to receive(:new).and_return(browser_double)
      allow(browser_double).to receive(:goto)
      allow(browser_double).to receive(:evaluate).with("window.scrollBy(0, document.body.scrollHeight)")
      # Simulate scroll loop ending quickly
      allow(browser_double).to receive(:body).and_return(html_body, '') 
      allow(browser_double).to receive(:quit)

      # Mock URI.open for fetching company detail pages
      allow(URI).to receive(:open).and_return(StringIO.new(detail_html_body))

      # Run thread pool tasks immediately to avoid async issues
      allow(Concurrent::FixedThreadPool).to receive(:new).and_return(Concurrent::ImmediateExecutor.new)
    end

    it "returns a CSV file with companies including details" do
      get :ycombinator, params: { n: 1 } # limit to exit loop

      expect(response).to have_http_status(:success)
      expect(response.header['Content-Type']).to include 'text/csv'
      expect(response.body).to include(
        "Test Co",
        "NY, USA",
        "Awesome startup",
        "Winter 2024",
        "https://testco.com",
        "Alice Founder (https://linkedin.com/in/alice)"
      )
    end

    context "when limit param is set" do
      it "respects the limit" do
        get :ycombinator, params: { n: 1 }

        csv_lines = response.body.split("\n")
        expect(csv_lines.size).to eq(2)  # header + 1 row
        expect(response).to have_http_status(:success)
      end
    end

    context "when filters are passed" do
      it "builds filtered URL" do
        get :ycombinator, params: { n: 1, filters: { regions: "United States", batch: "Winter 2024" } }

        expected_query = "regions=United+States&batch=Winter+2024"
        expect(browser_double).to have_received(:goto)
          .with("https://www.ycombinator.com/companies?#{expected_query}")
      end
    end
  end
end
