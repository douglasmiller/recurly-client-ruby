module Recurly
  class Pager
    attr_accessor :client
    attr_reader :data, :next

    def initialize(client:, path:, options: {})
      @client = client
      @path = path
      @options = map_array_params(options)
      @next = build_path(@path, @options)
    end

    # Performs a request with the pager `limit` set to 1 and only returns the first
    # result in the response.
    def first
      # Modify the @next url to set the :limit to 1
      original_next = @next
      @next = build_path(@path, @options.merge(limit: 1))
      fetch_next!
      # Restore the @next url to the original
      @next = original_next
      @data.first
    end

    # Makes a HEAD request to the API to determine how many total records exist.
    def count
      @client.get_resource_count(self.next)
    end

    # Enumerates each "page" from the server.
    # This method yields a given block with the array of items
    # in the page `data` and the page number the pagination is on
    # `page_num` which is 0-indexed.
    #
    # @example
    #   plans = client.list_plans()
    #   plans.each_page do |data|
    #     data.each do |plan|
    #       puts "Plan: #{plan.id}"
    #     end
    #   end
    # @example
    #   plans = client.list_plans()
    #   plans.each_page.each_with_index do |data, page_num|
    #     puts "Page Number: #{page_num}"
    #     data.each do |plan|
    #       puts "Plan: #{plan.id}"
    #     end
    #   end
    def each_page(&block)
      if block_given?
        page_enumerator.each(&block)
      else
        page_enumerator
      end
    end

    # Enumerates each item on the server. Each item is yielded to the
    # block presenting the effect of a continuous stream of items.
    # In reality, the pager is fetching blocks of data (pages) under the hood.
    # This method yields a given block with the next item to process.
    #
    # @example
    #   plans = client.list_plans()
    #   plans.each do |plan|
    #     puts "Plan: #{plan.id}"
    #   end
    # @example
    #   plans = client.list_plans()
    #   plans.each.each_with_index do |plan, idx|
    #     puts "Plan #{idx}: #{plan.id}"
    #   end
    def each(&block)
      if block_given?
        item_enumerator.each(&block)
      else
        item_enumerator
      end
    end

    def has_more?
      !!@has_more
    end

    def requires_client?
      true
    end

    private

    def item_enumerator
      Enumerator.new do |yielder|
        page_enumerator.each do |data|
          data.each do |item|
            yielder << item
          end
        end
      end
    end

    def page_enumerator
      Enumerator.new do |yielder|
        loop do
          fetch_next!
          yielder << data
          unless has_more?
            rewind!
            break
          end
        end
      end
    end

    def fetch_next!
      page = @client.next_page(self.next)
      @data = page.data.map { |d| JSONParser.from_json(d) }
      @has_more = page.has_more
      @next = page.next
    end

    def rewind!
      @data = []
      @next = build_path(@path, @options)
    end

    def build_path(path, options)
      if options.empty?
        path
      else
        "#{path}?#{URI.encode_www_form(options)}"
      end
    end

    # Converts array parameters to CSV strings to maintain consistency with
    # how the server expects the request to be formatted while providing the
    # developer with an array type to maintain developer happiness!
    def map_array_params(params)
      @options = params.map do |key, param|
        new_param = param.is_a?(Array) ? param.join(",") : param
        [key, new_param]
      end.to_h
    end
  end
end
