module Payday

  # The PDF renderer. We use this internally in Payday to render pdfs, but really you should just need to call
  # {{Payday::Invoiceable#render_pdf}} to render pdfs yourself.
  class PdfRenderer

    attr_accessor :invoice, :pdf
    attr_writer :font, :font_size

    def font
      @font || 'Helvetica'
    end

    def font_size
      @font_size || 8
    end

    # Renders the given invoice as a pdf on disk
    def render_to_file(invoice, path)
      generate_pdf(invoice)
      pdf.render_file(path)
    end

    # Renders the given invoice as a pdf, returning a string
    def render(invoice)
      generate_pdf(invoice)
      pdf.render
    end

    protected

      def generate_pdf(invoice)
        self.invoice = invoice
        self.pdf = setup

        render_header
        render_line_items
        render_footer

        pdf
      end

      def setup
        Prawn::Document.new(:page_size => invoice_or_default(invoice, :page_size)).tap do |pdf|
          if font.is_a?(Hash)
            pdf.font_families.update(font)
            pdf.font font.first.first
          else
            pdf.font font
          end

          pdf.font_size font_size
        end
      end

      def render_header
        render_stamp
        render_company_banner
        render_bill_to_ship_to
        render_invoice_details_table
      end

      def render_line_items
        render_line_items_table
        render_totals_table
      end

      def render_footer
        render_notes
        render_page_numbers
      end

      def render_stamp
        stamp = case
          when invoice.refunded? then t 'status.refunded'
          when invoice.paid? then t 'status.paid'
          when invoice.overdue? then t 'status.overdue'
        end

        if stamp
          pdf.bounding_box([150, pdf.cursor - 50], :width => pdf.bounds.width - 300) do
            pdf.fill_color "cc0000"
            pdf.text stamp, :align => :center, :size => 25, :rotate => 15, :style => :bold
            pdf.fill_color "000000"
          end
        end
      end

      def render_company_banner
        # render the logo
        image = invoice_or_default(invoice, :invoice_logo)
        height = nil
        width = nil

        # Handle images defined with a hash of options
        if image.is_a?(Hash)
          data = image
          image = data[:filename]
          width, height = data[:size].split("x").map(&:to_f)
        end

        if File.extname(image) == ".svg"
          logo_info = pdf.svg(File.read(image), :at => pdf.bounds.top_left, :width => width, :height => height)
          logo_height = logo_info[:height]
        else
          logo_info = pdf.image(image, :at => pdf.bounds.top_left, :width => width, :height => height)
          logo_height = logo_info.scaled_height
        end

        # render the company details
        table_data = []
        table_data << [bold_cell(pdf, invoice_or_default(invoice, :company_name).strip, :size => 12)]

        invoice_or_default(invoice, :company_details).lines.each { |line| table_data << [line] }

        table = pdf.make_table(table_data, :cell_style => { :borders => [], :padding => 0 })
        pdf.bounding_box([pdf.bounds.width - table.width, pdf.bounds.top], :width => table.width, :height => table.height + 5) do
          table.draw
        end

        pdf.move_cursor_to(pdf.bounds.top - logo_height - 20)
      end

      def render_bill_to_ship_to
        bill_to_cell_style = { :borders => [], :padding => [2, 0]}
        bill_to_ship_to_bottom = 0

        # render bill to
        pdf.float do
          table = pdf.table([[bold_cell(pdf, t('invoice.bill_to'))],
              [invoice.bill_to]], :column_widths => [200], :cell_style => bill_to_cell_style)
          bill_to_ship_to_bottom = pdf.cursor
        end

        # render ship to
        if defined?(invoice.ship_to) && !invoice.ship_to.nil?
          table = pdf.make_table([[bold_cell(pdf, t('invoice.ship_to'))],
              [invoice.ship_to]], :column_widths => [200], :cell_style => bill_to_cell_style)

          pdf.bounding_box([pdf.bounds.width - table.width, pdf.cursor], :width => table.width, :height => table.height + 2) do
            table.draw
          end
        end

        # make sure we start at the lower of the bill_to or ship_to details
        bill_to_ship_to_bottom = pdf.cursor if pdf.cursor < bill_to_ship_to_bottom
        pdf.move_cursor_to(bill_to_ship_to_bottom - 20)
      end

      def render_invoice_details_table
        data = invoice_details_table_data

        if data.length > 0
          pdf.table data, :cell_style => { :borders => [], :padding => [1, 10, 1, 1], :font_style => :bold } do
            columns(-1).align = :right
          end
        end
      end

      def invoice_details_table_data
        table_data = []

        # Invoice number
        if defined?(invoice.invoice_number) && invoice.invoice_number
          table_data << [t('invoice.invoice_no'), invoice.invoice_number.to_s]
        end

        # Due at
        if defined?(invoice.due_at) && invoice.due_at
          if invoice.due_at.is_a?(Date) || invoice.due_at.is_a?(Time)
            due_date = invoice.due_at.strftime(Payday::Config.default.date_format)
          else
            due_date = invoice.due_at.to_s
          end

          table_data << [t('invoice.due_date'), due_date]
        end

        # Paid at
        if defined?(invoice.paid_at) && invoice.paid_at
          if invoice.paid_at.is_a?(Date) || invoice.due_at.is_a?(Time)
            paid_date = invoice.paid_at.strftime(Payday::Config.default.date_format)
          else
            paid_date = invoice.paid_at.to_s
          end

          table_data << [t('invoice.paid_date'), paid_date]
        end

        # Refunded on
        if defined?(invoice.refunded_at) && invoice.refunded_at
          if invoice.refunded_at.is_a?(Date) || invoice.due_at.is_a?(Time)
            refunded_date = invoice.refunded_at.strftime(Payday::Config.default.date_format)
          else
            refunded_date = invoice.refunded_at.to_s
          end

          table_data << [bold_cell(pdf, I18n.t('payday.invoice.refunded_date', :default => "Refunded Date:")),
              bold_cell(pdf, refunded_date, :align => :right)]
        end

        # Include invoice details
        table_data += invoice.invoice_details.to_a if defined?(invoice.invoice_details)

        table_data
      end

      def render_line_items_table
        table_data = line_items_table_data

        pdf.move_cursor_to(pdf.cursor - 20)
        pdf.table(table_data, :width => pdf.bounds.width, :header => true,
            :cell_style => {:border_width => 0.5, :border_color => "cccccc", :padding => [5, 10]},
            :row_colors => ["dfdfdf", "ffffff"]) do

          # Header row styling
          rows(0).borders = []
          rows(0).columns(1..-1).align = :center
          rows(0).font_style = :bold

          # Left align the number columns
          columns(1..3).rows(1..row_length - 1).style(:align => :right)

          # Set the column widths correctly
          natural = natural_column_widths
          natural[0] = width - natural[1] - natural[2] - natural[3]

          column_widths = natural
        end
      end

      def line_items_table_data
        [
          # Header
          [
            t('line_item.description'),
            t('line_item.unit_price'),
            t('line_item.quantity'),
            t('line_item.amount')
          ],
          # Content
          *invoice.line_items.map do |line|
            [
              line.description,
              (line.display_price || number_to_currency(line.price)),
              (line.display_quantity || BigDecimal.new(line.quantity.to_s).to_s("F")),
              number_to_currency(line.amount)
            ]
          end
        ]
      end

      def render_totals_table
        font_size = self.font_size

        table = pdf.make_table(totals_table_data, :cell_style => { :borders => [] }) do
          columns(0).font_style = :bold
          columns(1).align = :right
          rows(-1).size = font_size + 4
        end

        pdf.bounding_box([pdf.bounds.width - table.width, pdf.cursor], :width => table.width, :height => table.height + 2) do
          table.draw
        end
      end

      def totals_table_data
        table_data = []

        if invoice.tax_rate > 0 || invoice.shipping_rate > 0
          table_data << [t('invoice.subtotal'), number_to_currency(invoice.subtotal)]
        end

        if invoice.tax_rate > 0
          table_data << [t('invoice.tax'), number_to_currency(invoice.tax)]
        end

        if invoice.shipping_rate > 0
          table_data << [t('invoice.shipping'), number_to_currency(invoice.shipping)]
        end

        table_data << [t('invoice.total'), number_to_currency(invoice.total)]
        table_data
      end

      def render_notes
        if defined?(invoice.notes) && invoice.notes
          pdf.move_cursor_to(pdf.cursor - 30)
          pdf.text(t('invoice.notes'), :style => :bold)
          pdf.line_width = 0.5
          pdf.stroke_color = "cccccc"
          pdf.stroke_line([0, pdf.cursor - 3, pdf.bounds.width, pdf.cursor - 3])
          pdf.move_cursor_to(pdf.cursor - 10)
          pdf.text(invoice.notes.to_s)
        end
      end

      def render_page_numbers
        if pdf.page_count > 1
          pdf.number_pages("<page> / <total>", :at => [pdf.bounds.right - 18, -15])
        end
      end

      def invoice_or_default(invoice, property)
        if invoice.respond_to?(property) && invoice.send(property)
          invoice.send(property)
        else
          Payday::Config.default.send(property)
        end
      end

      # Looks up a translation, first checking for custom invoice-specific translations
      def t(key)
        t = defined?(invoice.payday_translation) ? invoice.payday_translation(key) : nil
        t || I18n.t("payday.#{key}")
      end

      def cell(pdf, text, options = {})
        Prawn::Table::Cell::Text.make(pdf, text, options)
      end

      def bold_cell(pdf, text, options = {})
        cell(pdf, text, options.merge(:font_style => :bold))
      end

      # Converts this number to a formatted currency string
      def number_to_currency(number)
        currency = Money::Currency.wrap(invoice_or_default(invoice, :currency))
        number = number * currency.subunit_to_unit
        number = number.round unless Money.infinite_precision
        Money.new(number, currency).format
      end

      def max_cell_width(cell_proxy)
        max = 0
        cell_proxy.each do |cell|
          if cell.natural_content_width > max
            max = cell.natural_content_width
          end
        end

        max
      end
  end
end
