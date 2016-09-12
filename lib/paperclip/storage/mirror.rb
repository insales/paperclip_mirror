module Paperclip
  module Storage
    module Mirror
      def self.extended(base)
        base.instance_eval do
          @__mirrors = {}
          @options[:mirrors].each do |mirror_name, mirror_options|
            @__mirrors[mirror_name] = ::Paperclip::Attachment.new(
              name,
              instance,
              mirror_options.merge(styles: @options[:styles])
            )
          end
          @__fs_mirror = ::Paperclip::Attachment.new(
            name,
            instance,
            { storage: :filesystem }.merge(styles: @options[:styles])
          )
        end
      end

      def flush_deletes
        to_delete = @queued_for_delete.dup
        [@__fs_mirror, *@__mirrors.values].each do |mirror|
          mirror.instance_variable_set('@queued_for_delete', to_delete.dup)
          mirror.flush_deletes
        end
        @queued_for_delete = []
      end

      def file_for_style(style_name)
        ::Paperclip::FileAdapter.new(open(@__fs_mirror.path(style_name)))
      end

      def flush_writes
        styles_to_write = @queued_for_write.keys
        @queue = @queued_for_write.dup

        @__fs_mirror.instance_variable_set('@queued_for_write', @queue)
        Paperclip.log "Writing to FS styles #{styles_to_write}"
        @__fs_mirror.flush_writes

        if !instance.respond_to?("#{name}_processing?") || instance.send("#{name}_processing?") # Hack for delayed_paperclip
          # This happens during processing, not initial creation
          @__mirrors.each do |mirror_name, mirror|
            files_to_write = Hash[styles_to_write.map { |style_name| [style_name, file_for_style(style_name)] }]
            mirror.instance_variable_set('@queued_for_write', files_to_write)
            Paperclip.log "Writing to mirror #{mirror_name} styles #{styles_to_write}"
            mirror.flush_writes
          end
          unless @options[:keep_local_files]
            @__fs_mirror.send(:queue_some_for_delete, :original, *styles.keys)
            @__fs_mirror.flush_deletes
          end
        end
        @queued_for_write = {}
      end

      def exists?(style_name = default_style)
        @__mirrors.values.reduce(true) { |acc, mirror| acc && mirror.exists?(style_name) }
      end

      def copy_to_local_file(style, local_dest_path)
        @__fs_mirror.copy_to_local_file(style, local_dest_path)
      end

      def get_mirror(mirror_name)
        return @__fs_mirror unless @__mirrors[mirror_name]
        @__mirrors[mirror_name]
      end

      def url(style_name = @options[:default_style], options = {})
        get_mirror(@options[:default_mirror]).url(style_name, options)
      end

      def path(style_name = @options[:default_style])
        get_mirror(@options[:default_mirror]).path(style_name)
      end

      private

      def queue_some_for_delete(*styles)
        @__mirrors.values.each do |mirror|
          @queued_for_delete += styles.uniq.map do |style|
            mirror.path(style) if exists?(style)
          end.compact
        end
        super
      end

      def queue_all_for_delete
        unless @options[:preserve_files]
          @__mirrors.values.each do |mirror|
            @queued_for_delete += [:original, *styles.keys].uniq.map do |style|
              mirror.path(style) if exists?(style)
            end.compact
          end
        end
        super
      end
    end
  end
end
