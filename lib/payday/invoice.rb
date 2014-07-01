module Payday

  # Basically just an invoice. Stick a ton of line items in it, add some details, and then render it out!
  class Invoice
    include Payday::Invoiceable

    attr_accessor :invoice_number, :bill_to, :ship_to, :notes, :line_items, :shipping_rate,
                  :tax_rate, :due_at, :paid_at, :refunded_at, :currency, :invoice_details

    def initialize(options =  {})
      self.invoice_number = options[:invoice_number] || nil
      self.bill_to = options[:bill_to] || nil
      self.ship_to = options[:ship_to] || nil
      self.notes = options[:notes] || nil
      self.line_items = options[:line_items] || []
      self.shipping_rate = options[:shipping_rate] || nil
      self.tax_rate = options[:tax_rate] || nil
      self.due_at = options[:due_at] || nil
      self.paid_at = options[:paid_at] || nil
      self.refunded_at = options[:refunded_at] || nil
      self.currency = options[:currency] || nil
      self.invoice_details = options[:invoice_details] || []
    end

    # The tax rate that we're applying, as a BigDecimal
    def tax_rate=(value)
      @tax_rate = BigDecimal.new(value.to_s)
    end

    # Shipping rate
    def shipping_rate=(value)
      @shipping_rate = BigDecimal.new(value.to_s)
    end
  end
end
