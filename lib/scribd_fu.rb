module ScribdFu

  ConfigPath = "config/scribd_fu.yml".freeze

  # A list of content types supported by iPaper.
  ContentTypes = [
    'application/pdf',
    'application/msword',
    'application/mspowerpoint',
    'application/vnd.ms-powerpoint',
    'application/excel',
    'application/vnd.ms-excel',
    'application/postscript',
    'text/plain',
    'text/rtf',
    'application/rtf',
    'application/vnd.oasis.opendocument.text',
    'application/vnd.oasis.opendocument.presentation',
    'application/vnd.oasis.opendocument.spreadsheet',
    'application/vnd.sun.xml.writer',
    'application/vnd.sun.xml.impress',
    'application/vnd.sun.xml.calc',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.template',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
    'application/vnd.openxmlformats-officedocument.presentationml.template',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.template'
  ]

  # RegExp that matches AWS S3 URLs
  S3 = /^https?:\/\/s3.amazonaws.com/
  CLOUD_FRONT = /^http:\/\/[A-Za-z0-9]*.cloudfront.net/

  # Available parameters for the JS API
  # http://www.scribd.com/publisher/api/api?method_name=Javascript+API
  Available_JS_Params = [ :height, :width, :page, :my_user_id, :search_query,
                          :jsapi_version, :disable_related_docs, :mode, :auto_size, :hide_disabled_buttons, :hide_full_screen_button]

  class ScribdFuError < StandardError #:nodoc:
  end

  class ScribdFuUploadError < ScribdFuError #:nodoc:
  end


  class << self

    def included(base) #:nodoc:
      base.extend ClassMethods
    end

    # Login, store, and return a handle to the Scribd user account
    def scribd_user
      begin
        # Ensure we can login to Scribd, and get a handle on the account
        Scribd::API.instance.key    = config[:key]
        Scribd::API.instance.secret = config[:secret]
        @scribd_user = Scribd::User.login(config[:user], config[:password])
      rescue
        raise ScribdFuError, "Your Scribd credentials are incorrect"
      end
    end

    # Upload a file to Scribd
    def upload(obj, file_path)
      begin
        args = { :file => escape(file_path), :access => access_level }
        res = if obj.ipaper_my_user_id
          scribd_user
          args[:my_user_id] = obj.ipaper_my_user_id
          Scribd::Document.create(args)
        else
          scribd_user.upload(args)
        end
        obj.update_attributes({:ipaper_id => res.doc_id, :ipaper_access_key => res.access_key})
      rescue
        raise ScribdFuUploadError, "Sorry, but #{obj.class} ##{obj.id} could not be uploaded to Scribd"
      end
    end

    # Delete an iPaper document
    def destroy(document)
      document.destroy
    end

    # Read, store, and return the ScribdFu config file's contents
    def config
      path = defined?(Rails) ? File.join(Rails.root, ConfigPath) : ConfigPath
      raise ScribdFuError, "#{path} does not exist" unless File.file?(path)

      # Load the config file and strip any whitespace from the values
      @config ||= YAML.load_file(path).each_pair{|k,v| {k=>v.to_s.strip}}.symbolize_keys!
    end

    # Get the preferred access level for iPaper documents
    def access_level
      config[:access] || 'private'
    end

    # Load, store, and return the associated iPaper document
    def load_ipaper_document(id)
      # Yes, catch-all rescues are bad, but the end rescue
      # should return nil, so laziness FTW.
      scribd_user.find_document(id) rescue nil
    end

    # Replace spaces with '%20' (needed by Paperclip models).
    def escape(str)
      basename = File.basename(str, ".*")
      File.join(File.dirname(str), "#{url_encode(basename)}#{File.extname(str)}").to_s
    end

    def url_encode(str)
      str.to_s.gsub(/[^a-zA-Z0-9_\-.]/n){ sprintf("%%%02X", $&.unpack("C")[0]) }
    end

    # See if a URL is S3 or CloudFront based
    def amazon_based?(url)
      url =~ S3 || url =~ CLOUD_FRONT
    end

    # Strip off any trailing "?1234567890" cache strings
    # They cause headaches on Scribd's end.
    def strip_cache_string(url)
      pos = url.rindex('?')
      (pos) ? url[0, pos] : url
    end

  end

  module ClassMethods

    # Load and inject ScribdFu goodies
    # opts can be :on => :create, defaults to :on => :save
    def has_ipaper_and_uses(str, opts = {:on => :save })
      check_environment
      load_base_plugin(str)

      include InstanceMethods

      attr_accessor :ipaper_my_user_id

      send("after_#{opts[:on]}", :upload_to_scribd) # This *MUST* be an after_save
      before_destroy :destroy_ipaper_document
    end

    private

      # Configure ScribdFu for this particular environment
      def check_environment
        load_rscribd
        check_config
      end

      def check_config
        ScribdFu::config
      end

      # Load the rscribd gem
      def load_rscribd
        begin
          require 'rscribd'
        rescue LoadError
          raise ScribdFuError, 'Please install the rscribd gem'
        end
      end

      # Load Attachment_Fu specific methods and files
      def load_attachment_fu
        require 'scribd_fu/attachment_fu'
        include ScribdFu::AttachmentFu::InstanceMethods
      end

      # Load Shrine specific methods and files
      def load_shrine
        require 'scribd_fu/shrine'
        include ScribdFu::Shrine::InstanceMethods
      end

      # Load Paperclip specific methods and files
      def load_paperclip
        require 'scribd_fu/paperclip'
        include ScribdFu::Paperclip::InstanceMethods
      end

      # Load either AttachmentFu or Paperclip-specific methods
      def load_base_plugin(str)
        if str == 'AttachmentFu'
          load_attachment_fu
        elsif str == 'Paperclip'
          load_paperclip
        elsif str == 'Shrine'
          load_shrine
        else
          raise ScribdFuError, "Sorry, only Attachment_fu and Paperclip are supported."
        end
      end

  end

  module InstanceMethods

    def self.included(base)
      base.extend ClassMethods
    end

    # Upload the associated file to Scribd for iPaper conversion
    # This is called +after_save+ and cannot be called earlier,
    # so don't get any ideas.
    def upload_to_scribd
      ScribdFu::upload(self, file_path) if scribdable?
    end

    # Checks whether the associated file is convertable to iPaper
    def scribdable?
      ContentTypes.include?(get_content_type) && ipaper_id.blank?
    end

    # Responds true if the conversion is converting
    def conversion_processing?
      !(conversion_complete? || conversion_successful? || conversion_error?)
    end

    # Responds true if the conversion is complete -- note that this gives no
    # indication as to whether the conversion had an error or was succesful,
    # just that the conversion completed.
    def conversion_complete?
      ipaper_document && ipaper_document.conversion_status != 'PROCESSING'
    end

    # Responds true if the document has been converted.
    def conversion_successful?
      ipaper_document && ipaper_document.conversion_status =~ /^DISPLAYABLE|DONE$/
    end

    # Responds true if there was a conversion error while converting to iPaper.
    def conversion_error?
      ipaper_document && ipaper_document.conversion_status == 'ERROR'
    end

    # Responds the Scribd::Document associated with this model, or nil if it does not exist.
    def ipaper_document
      @document ||= ScribdFu::load_ipaper_document(ipaper_id)
    end

    # Destroys the scribd document for this record. This is called +before_destroy+
    def destroy_ipaper_document
      ScribdFu::destroy(ipaper_document) if ipaper_document
    end

    # Display the iPaper document in a view
    def display_ipaper(options = {})
      id = options.delete(:id) || to_param
      view_mode = options.delete(:view_mode) || 'list'
      view_height = "height='#{options.delete(:height)}'" || 'data-auto-height="true"'

      <<-END
        <iframe class="scribd_iframe_embed" src="http://www.scribd.com/embeds/#{ipaper_id}/content?start_page=1&view_mode=#{view_mode}&access_key=#{ipaper_access_key}" #{view_height} scrolling="no" id="scribd_#{id}" width="100%" frameborder="0"></iframe><script type="text/javascript">(function() { var scribd = document.createElement("script"); scribd.type = "text/javascript"; scribd.async = true; scribd.src = "http://www.scribd.com/javascripts/embed_code/inject.js"; var s = document.getElementsByTagName("script")[0]; s.parentNode.insertBefore(scribd, s); })();</script>
      END
    end

  end

end

# Let's do this.
ActiveRecord::Base.send(:include, ScribdFu) if Object.const_defined?("ActiveRecord")

