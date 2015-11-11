module ScribdFu
  module Shrine

    module ClassMethods
    end

    module InstanceMethods

      def self.included(base)
        base.extend ClassMethods
      end

      # Returns a URL for a thumbnail for this model's attachment.
      def thumbnail_url
        (ipaper_document && ipaper_document.thumbnail_url) || attached_file.url
      end

      # Returns the content type for this model's attachment.
      def get_content_type
        self.send(prefix).mime_type
      end

      # Yields the correct path to the file, either the local filename or the S3 URL.
      def file_path
        ScribdFu::strip_cache_string(attached_file.url)
      end

      private

        # Figure out what Paperclip is calling the attached file object
        # ie. has_attached_file :attachment => "attachment"
        def prefix
          @prefix ||= self.class.column_names.detect{|c| c.ends_with?("_data")}.gsub("_data", '')
        end

        # Return the attached file object
        def attached_file
          @file ||= self.send(prefix)
        end

    end

  end
end
