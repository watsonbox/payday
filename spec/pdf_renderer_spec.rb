require 'spec_helper'

module Payday
  describe PdfRenderer do
    before do
      Dir.mkdir("tmp") unless File.exists?("tmp")
      Config.default.reset
    end

    let(:invoice) { new_invoice(invoice_params) }
    let(:invoice_params) { {} }

    # Note: Testing certain protected renderer methods is okay because
    # these are template methods and hence an interface for derived classes
    context 'with a dummy Prawn document' do
      let(:document) { double.as_null_object }
      before { allow(Prawn::Document).to receive("new").and_return(document) }

      it 'should use Helvetica as the default font' do
        expect(document).to receive(:font).with('Helvetica')
        invoice.render_pdf
      end

      it 'should support a custom built-in font' do
        invoice.renderer.font = 'Courier'
        expect(document).to receive(:font).with('Courier')
        invoice.render_pdf
      end

      it 'should support custom font files' do
        font_families = double
        font = invoice.renderer.font = {
          "Museo Sans" => {
            :normal => "/path/to/museosans_500.ttf",
            :bold => "/path/to/museosans_900.ttf"
          }
        }

        expect(font_families).to receive(:update).with(font)
        expect(document).to receive(:font_families).and_return(font_families)
        expect(document).to receive(:font).with('Museo Sans')

        invoice.render_pdf
      end

      it 'should have a default font size of 8' do
        expect(document).to receive(:font_size).with(8)
        invoice.render_pdf
      end

      it 'should support a custom font size' do
        invoice.renderer.font_size = 12
        expect(document).to receive(:font_size).with(12)
        invoice.render_pdf
      end

      context 'there are additional taxes' do
        let(:invoice_params) { { :tax_rate => 0.1 } }

        it 'should include a subtotal line in the totals table' do
          invoice.render_pdf
          expect(invoice.renderer.send(:totals_table_data).map { |k, v| k }).to eq(['Subtotal:', 'Tax:', 'Total:'])
        end
      end

      context 'there are no additional taxes' do
        let(:invoice_params) { { :tax_rate => 0 } }

        it 'should not include a subtotal line in the totals table' do
          invoice.render_pdf
          expect(invoice.renderer.send(:totals_table_data).map { |k, v| k }).to eq(['Total:'])
        end
      end
    end

    # The following tests actually check rendered output. We probably don't want too many tests like this
    # because whenever a small change to PDF output is required, the expected assets must all be updated.
    # In a sense these are integration tests - in general we should trust the Prawn API.

    it "should render to a file" do
      File.unlink("tmp/testing.pdf") if File.exists?("tmp/testing.pdf")

      invoice.render_pdf_to_file("tmp/testing.pdf")

      expect(File.exists?("tmp/testing.pdf")).to be_true
    end

    context 'with some invoice details' do
      let(:invoice_params) { {
        :invoice_details => { "Ordered By:" => "Alan Johnson", "Paid By:" => "Dude McDude" }
      } }

      it "should render an invoice correctly to a string" do
        Payday::Config.default.company_details = "10 This Way\nManhattan, NY 10001\n800-111-2222\nawesome@awesomecorp.com"

        invoice.line_items = [
          LineItem.new(:price => 20, :quantity => 5, :description => "Pants"),
          LineItem.new(:price => 10, :quantity => 3, :description => "Shirts"),
          LineItem.new(:price => 5, :quantity => 200, :description => "Hats")
        ] * 30

        expect(invoice.render_pdf).to match_binary_asset 'testing.pdf'
      end
    end

    context 'paid, with an svg logo' do
      before do
        Payday::Config.default.invoice_logo = { :filename => "spec/assets/tiger.svg", :size => "100x100" }
      end

      let(:invoice_params) { { :paid_at => Date.civil(2012, 2, 22) } }

      it 'should render an invoice correctly to a string' do
        invoice.line_items = [
          LineItem.new(:price => 20, :quantity => 5, :description => "Pants"),
          LineItem.new(:price => 10, :quantity => 3, :description => "Shirts"),
          LineItem.new(:price => 5, :quantity => 200.0, :description => "Hats")
        ] * 3

        expect(invoice.render_pdf).to match_binary_asset 'svg.pdf'
      end
    end

    def new_invoice(params = {})
      default_params = {
        :tax_rate => 0.1,
        :notes => "These are some crazy awesome notes!",
        :invoice_number => 12,
        :due_at => Date.civil(2011, 1, 22),
        :bill_to => "Alan Johnson\n101 This Way\nSomewhere, SC 22222",
        :ship_to => "Frank Johnson\n101 That Way\nOther, SC 22229",
        :line_items => [
          LineItem.new(:price => 20, :quantity => 5, :description => "Pants"),
          LineItem.new(:price => 10, :quantity => 3, :description => "Shirts"),
          LineItem.new(:price => 5, :quantity => 200.0, :description => "Hats")
        ]
      }

      Invoice.new(default_params.merge(params))
    end
  end
end
